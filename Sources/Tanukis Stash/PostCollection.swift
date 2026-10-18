import Foundation
import os.log

private let kCollectionPageSize = 75;
private let kCollectionMaxPages = 20;
// A family is walked level by level; this bounds the climb to the top of the
// tree and the descent from it, so a pathological tree can't run away.
private let kFamilyMaxLevels = 8;
// Parent ids per `~parent:` OR query (the API takes 40 tags; stay well under).
private let kFamilyBatchSize = 20;

// A set of posts that belong together and can be paged through in order.
enum PostCollection: Hashable, Identifiable {
    case pool(Int)
    // Any post of a parent/child tree. The loader climbs to the top of the tree
    // from it and collects every descendant: parents, siblings, children and
    // their children.
    case family(anchor: Int)

    var id: String {
        switch self {
        case .pool(let id): return "pool:\(id)";
        case .family(let anchor): return "family:\(anchor)";
        }
    }

    // Pools first (a post can be in several), then its parent/child family.
    // Empty means the post is plain and belongs in PostView.
    static func collections(for post: PostContent) -> [PostCollection] {
        var result = post.pools.map { PostCollection.pool($0) };
        if post.hasFamily {
            result.append(.family(anchor: post.id));
        }
        return result;
    }
}

// The listing endpoint cannot return pool order (`order:id` is ascending post
// id), so the pool's own post_ids is the source of truth. Posts the pool no
// longer lists sort last, by id.
func orderedByPool(_ posts: [PostContent], postIds: [Int]) -> [PostContent] {
    var position: [Int: Int] = [:];
    for (index, id) in postIds.enumerated() where position[id] == nil {
        position[id] = index;
    }
    return posts.sorted { lhs, rhs in
        let l = position[lhs.id] ?? Int.max;
        let r = position[rhs.id] ?? Int.max;
        return l != r ? l < r : lhs.id < rhs.id;
    };
}

// Depth-first from the top of the tree: each post, then its children (and
// theirs) in ascending post id, so a branch stays together. `preferredRoot` (the
// top the climb reached) comes first. A post whose parent isn't loaded
// (hidden, blacklisted, deleted) starts its own branch, as does anything
// unreachable from a root.
func orderedFamilyTree(_ posts: [PostContent], preferredRoot: Int) -> [PostContent] {
    var byId: [Int: PostContent] = [:];
    for post in posts { byId[post.id] = post; }
    var childrenOf: [Int: [PostContent]] = [:];
    var roots: [PostContent] = [];
    for post in byId.values {
        if let parent = post.relationships.parent_id, byId[parent] != nil {
            childrenOf[parent, default: []].append(post);
        } else {
            roots.append(post);
        }
    }
    for key in Array(childrenOf.keys) { childrenOf[key]?.sort { $0.id < $1.id }; }
    roots.sort { lhs, rhs in
        if (lhs.id == preferredRoot) != (rhs.id == preferredRoot) { return lhs.id == preferredRoot; }
        return lhs.id < rhs.id;
    };

    var result: [PostContent] = [];
    var visited = Set<Int>();
    func visit(_ post: PostContent) {
        guard visited.insert(post.id).inserted else { return; }
        result.append(post);
        for child in childrenOf[post.id] ?? [] { visit(child); }
    }
    roots.forEach(visit);
    // Only reachable with corrupt parent links (a cycle has no root).
    for post in byId.values.sorted(by: { $0.id < $1.id }) { visit(post); }
    return result;
}

// Which parent ids still need a `parent:` query to find their children: every
// loaded post that lists children, plus every listed child that did not load
// (inactive or hidden — it can still have visible children of its own).
func familyExpansionTargets(members: [Int: PostContent], expanded: Set<Int>) -> [Int] {
    var targets = Set<Int>();
    for post in members.values where !post.relationships.children.isEmpty {
        targets.insert(post.id);
        for child in post.relationships.children where members[child] == nil {
            targets.insert(child);
        }
    }
    return targets.subtracting(expanded).sorted();
}

struct PostCollectionLoad {
    var posts: [PostContent];
    // Only set for pool collections; carries the name, description and size.
    var pool: PoolContent?;
    // A page failed (partial results kept), or the pool's order is unknown.
    var failed: Bool;
}

// All pages of one listing query, de-duplicated. `failed` when a page failed
// (what loaded before it is kept).
private func fetchAllPages(_ tags: String) async -> (posts: [PostContent], failed: Bool) {
    let ignoringBlacklist = showsBlacklistedInCollections();
    var all: [PostContent] = [];
    var seen = Set<Int>();
    var page = 1;
    while page <= kCollectionMaxPages {
        if Task.isCancelled { break; }
        let result = await fetchRecentPosts(page, kCollectionPageSize, tags, ignoringBlacklist: ignoringBlacklist);
        if result.failed { return (all, true); }
        for post in result.posts where seen.insert(post.id).inserted {
            all.append(post);
        }
        if !result.hasMore { break; }
        page = result.page + 1;
    }
    return (all, false);
}

// Loads every post of `collection` in collection order. `seed` — the post the
// user is on — is always included even if the blacklist or the page cap would
// have dropped it, and is placed by the same ordering rules, so the viewer can
// stay on it.
func fetchPostCollection(_ collection: PostCollection, seed: PostContent?) async -> PostCollectionLoad {
    switch collection {
    case .pool(let id):
        return await fetchPoolCollection(id, seed: seed);
    case .family(let anchor):
        return await fetchFamilyCollection(anchor: anchor, seed: seed);
    }
}

private func fetchPoolCollection(_ id: Int, seed: PostContent?) async -> PostCollectionLoad {
    let pool = await fetchPool(poolId: id);
    let loaded = await fetchAllPages("pool:\(id) order:id");
    var failed = loaded.failed;
    var all = loaded.posts;

    if let seed, !all.contains(where: { $0.id == seed.id }) {
        all.append(seed);
    }
    if let pool {
        all = orderedByPool(all, postIds: pool.post_ids);
    } else {
        os_log("fetchPostCollection: pool metadata unavailable, order unknown", log: .default);
        failed = true;
    }
    return PostCollectionLoad(posts: all, pool: pool, failed: failed);
}

// The whole parent/child tree around `anchor`, found level by level (about two
// to five small requests for a typical family):
//   1. climb: `~id:P ~parent:P` fetches a parent and its other children in one
//      request; repeat while the parent has a parent of its own.
//   2. descend: every post lists its children's ids, so the ids that still need
//      expanding are known; query them in batches (`~parent:A ~parent:B …`)
//      until a level adds nothing.
private func fetchFamilyCollection(anchor: Int, seed: PostContent?) async -> PostCollectionLoad {
    guard let start = seed?.id == anchor ? seed : await getPost(postId: anchor) else {
        return PostCollectionLoad(posts: seed.map { [$0] } ?? [], pool: nil, failed: true);
    }
    var failed = false;
    var members: [Int: PostContent] = [start.id: start];
    var expanded = Set<Int>();

    func absorb(_ batch: (posts: [PostContent], failed: Bool)) {
        failed = failed || batch.failed;
        for post in batch.posts where members[post.id] == nil { members[post.id] = post; }
    }

    var top = start;
    var levels = 0;
    while let parentId = top.relationships.parent_id, levels < kFamilyMaxLevels {
        if Task.isCancelled { break; }
        absorb(await fetchAllPages("~id:\(parentId) ~parent:\(parentId)"));
        expanded.insert(parentId);
        // A parent that is hidden, blacklisted or deleted can't be climbed past.
        guard let parent = members[parentId] else { break; }
        top = parent;
        levels += 1;
    }

    var depth = 0;
    while depth < kFamilyMaxLevels {
        if Task.isCancelled { break; }
        let targets = familyExpansionTargets(members: members, expanded: expanded);
        if targets.isEmpty { break; }
        var index = 0;
        while index < targets.count {
            let batch = Array(targets[index..<min(index + kFamilyBatchSize, targets.count)]);
            // A lone `~tag` isn't an OR query; spell it plainly.
            let tags = batch.count == 1
                ? "parent:\(batch[0])"
                : batch.map { "~parent:\($0)" }.joined(separator: " ");
            absorb(await fetchAllPages(tags));
            expanded.formUnion(batch);
            index += kFamilyBatchSize;
        }
        depth += 1;
    }

    // The page the user is on stays in the list even when it is not part of
    // this tree (swiped to another collection's page, then switched here).
    if let seed, members[seed.id] == nil { members[seed.id] = seed; }
    return PostCollectionLoad(
        posts: orderedFamilyTree(Array(members.values), preferredRoot: top.id),
        pool: nil,
        failed: failed
    );
}
