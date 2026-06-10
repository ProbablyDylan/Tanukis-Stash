//
//  NavigationDestinations.swift
//  Tanuki
//
//  Value types pushed onto NavigationStacks. Destination views are built
//  lazily by appNavigationDestinations() when a value is pushed — never
//  construct destination views eagerly inside grid cells (iOS 27 hang,
//  see PostView.AUTHENTICATED comment).
//

import SwiftUI

// Hashable wrappers so String-valued destinations don't collide on a typed
// NavigationPath.
struct TagDestination: Hashable {
    let name: String;
}

struct SearchDestination: Hashable {
    let query: String;
}

// Carries the already-fetched post; identity is (post id, search context).
struct PostDestination: Hashable {
    let post: PostContent;
    let search: String;
    var highlightCommentId: Int? = nil;

    static func == (lhs: PostDestination, rhs: PostDestination) -> Bool {
        lhs.post.id == rhs.post.id
            && lhs.search == rhs.search
            && lhs.highlightCommentId == rhs.highlightCommentId;
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(post.id);
        hasher.combine(search);
        hasher.combine(highlightCommentId);
    }
}

// pool payload is an optional prefetch optimization; identity is the id.
struct PoolDestination: Hashable {
    let poolId: Int;
    var pool: PoolContent? = nil;

    static func == (lhs: PoolDestination, rhs: PoolDestination) -> Bool {
        lhs.poolId == rhs.poolId;
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(poolId);
    }
}

struct FavoritesDestination: Hashable {
}

// One registration point per NavigationStack. Attach to the stack's root
// content view — registering inside lazy containers breaks the links.
struct AppNavigationDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: PostDestination.self) { dest in
                PostView(post: dest.post, search: dest.search, highlightCommentId: dest.highlightCommentId)
            }
            .navigationDestination(for: PoolDestination.self) { dest in
                PoolView(poolId: dest.poolId, pool: dest.pool)
            }
            .navigationDestination(for: TagDestination.self) { dest in
                TagView(tagName: dest.name)
            }
            .navigationDestination(for: SearchDestination.self) { dest in
                SearchView(search: dest.query)
            }
            .navigationDestination(for: FavoritesDestination.self) { _ in
                FavoritesView()
            }
    }
}

extension View {
    func appNavigationDestinations() -> some View {
        modifier(AppNavigationDestinations())
    }
}
