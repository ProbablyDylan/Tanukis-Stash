import SwiftUI

// PostView is pushed with a post captured by value (PostDestination), and
// keeps its own private @State copy — a vote or favorite cast there has no
// path back into the array a grid (SearchView/TagView/FavoritesView) is
// showing. Successful actions in PostView record the new totals here; each
// grid applies whatever's pending for its own posts when it reappears.
@MainActor private var pendingPostStatsUpdates: [Int: PostContent] = [:];

@MainActor func recordPostStatsUpdate(_ post: PostContent) {
    pendingPostStatsUpdates[post.id] = post;
}

// Non-consuming lookup for a view (PostView) that needs to keep showing the
// override on every render, as opposed to a grid that consumes it once and
// writes it permanently into its own array.
@MainActor func pendingPostStatsUpdate(for postId: Int) -> PostContent? {
    pendingPostStatsUpdates[postId];
}

// Patches `posts` in place from any pending updates that match its ids,
// consuming them. Call from a grid-hosting view's onAppear.
@MainActor func applyPendingPostStatsUpdates(to posts: inout [PostContent]) {
    guard !pendingPostStatsUpdates.isEmpty else { return; }
    for i in posts.indices {
        if let updated = pendingPostStatsUpdates.removeValue(forKey: posts[i].id) {
            posts[i] = updated;
        }
    }
}
