import Foundation
import os.log

private let kCollectionPageSize = 75;
private let kCollectionMaxPages = 20;

// A set of posts that belong together and can be paged through in order.
enum PostCollection: Hashable, Identifiable {
    case pool(Int)
    case family(root: Int)

    var id: String {
        switch self {
        case .pool(let id): return "pool:\(id)";
        case .family(let root): return "family:\(root)";
        }
    }

    // Pools first (a post can be in several), then its parent/child family.
    // Empty means the post is plain and belongs in PostView.
    static func collections(for post: PostContent) -> [PostCollection] {
        var result = post.pools.map { PostCollection.pool($0) };
        if post.hasFamily {
            result.append(.family(root: post.relationships.parent_id ?? post.id));
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

// Parent first, then children in ascending post id.
func orderedFamily(_ posts: [PostContent], root: Int) -> [PostContent] {
    posts.sorted { lhs, rhs in
        if (lhs.id == root) != (rhs.id == root) { return lhs.id == root; }
        return lhs.id < rhs.id;
    };
}

struct PostCollectionLoad {
    var posts: [PostContent];
    // Only set for pool collections; carries the name, description and size.
    var pool: PoolContent?;
    // A page failed (partial results kept), or the pool's order is unknown.
    var failed: Bool;
}

// Loads every post of `collection` (pools up to 20 pages, matching the old
// PoolView cap), in collection order. `seed` — the post the user tapped — is
// always included even if the blacklist or the page cap would have dropped it,
// and is placed by the same ordering rules, so the viewer can stay on it.
func fetchPostCollection(_ collection: PostCollection, seed: PostContent?) async -> PostCollectionLoad {
    var pool: PoolContent?;
    let tags: String;
    switch collection {
    case .pool(let id):
        pool = await fetchPool(poolId: id);
        tags = "pool:\(id) order:id";
    case .family(let root):
        tags = "~id:\(root) ~parent:\(root)";
    }

    var all: [PostContent] = [];
    var seen = Set<Int>();
    var page = 1;
    var failed = false;
    while page <= kCollectionMaxPages {
        if Task.isCancelled { break; }
        let result = await fetchRecentPosts(page, kCollectionPageSize, tags);
        if result.failed { failed = true; break; }
        for post in result.posts where seen.insert(post.id).inserted {
            all.append(post);
        }
        if !result.hasMore { break; }
        page = result.page + 1;
    }

    if let seed, seen.insert(seed.id).inserted {
        all.append(seed);
    }

    switch collection {
    case .pool:
        if let pool {
            all = orderedByPool(all, postIds: pool.post_ids);
        } else {
            os_log("fetchPostCollection: pool metadata unavailable, order unknown", log: .default);
            failed = true;
        }
    case .family(let root):
        all = orderedFamily(all, root: root);
    }
    return PostCollectionLoad(posts: all, pool: pool, failed: failed);
}
