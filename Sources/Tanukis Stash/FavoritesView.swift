//
//  FavoritesView.swift
//  Tanuki
//

import SwiftUI

// Sorting is done by the server so it covers the whole favorites list, not
// just the pages loaded so far. "Recent" uses the favorites endpoint (favorite
// order); the others go through posts.json with an `order:` metatag.
enum FavoriteSortOption: String, CaseIterable {
    case recent = "Recent"
    case oldest = "Oldest"
    case highestScore = "Score"
    case mostFaved = "Favorites"

    func searchTag(username: String) -> String {
        let base = "fav:\(username)";
        switch self {
        case .recent: return base;
        case .oldest: return base + " order:id";
        case .highestScore: return base + " order:score";
        case .mostFaved: return base + " order:favcount";
        }
    }
}

struct FavoritesView: View {
    @State private var posts = [PostContent]();
    @State private var page = 1;
    @State private var isLoading: Bool = false;
    @State private var hasLoaded: Bool = false;
    @State private var loadFailed: Bool = false;
    @State private var allLoaded: Bool = false;
    @State private var sortOption: FavoriteSortOption = .recent;
    @State private var scrolledPostID: Int?;
    // Bumped by every fresh load (refresh, sort change) so an in-flight
    // load-more can't append its page on top of the reset list.
    @State private var loadGeneration: Int = 0;

    private var searchTag: String {
        sortOption.searchTag(username: UserDefaults.standard.string(forKey: UDKey.username) ?? "");
    }

    var limit = 75;

    @ViewBuilder
    private var emptyState: some View {
        if isLoading || !hasLoaded {
            ProgressView("Loading favorites...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed {
            PostLoadFailedView { await loadPosts(); }
        } else if !allLoaded {
            BlacklistSkippedView { await loadMorePosts(); }
        } else {
            ContentUnavailableView("No favorites yet", systemImage: "heart")
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            if posts.isEmpty {
                emptyState
            }
            PaginatedPostGrid(posts: posts, allLoaded: allLoaded, loadMore: loadMorePosts) { _, post in
                if let idx = posts.firstIndex(where: { $0.id == post.id }) {
                    FavoriteGridCell(
                        post: $posts[idx],
                        search: searchTag,
                        onUnfavorite: {
                            withAnimation { posts.removeAll { $0.id == post.id } }
                        }
                    )
                }
            }
        }
        .scrollPosition(id: $scrolledPostID)
        // Picks up vote/favorite totals cast in PostView, which can't write
        // back into this array directly — see PostStatsSync.swift.
        .onAppear { applyPendingPostStatsUpdates(to: &posts); }
        .task {
            if posts.isEmpty {
                await loadPosts();
            }
        }
        .onChange(of: sortOption) {
            posts = [];
            hasLoaded = false;
            Task { await loadPosts(); }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Favorites")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(FavoriteSortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .refreshable {
            await loadPosts();
        }
    }

    func loadPosts() async {
        loadGeneration += 1;
        let generation = loadGeneration;
        isLoading = true;
        let result = await fetchRecentPosts(1, limit, searchTag);
        // A newer load (sort change, second refresh) supersedes this one.
        guard generation == loadGeneration else { return; }
        isLoading = false;
        hasLoaded = true;
        loadFailed = result.failed;
        guard !result.failed else { return; }
        page = result.page;
        allLoaded = !result.hasMore;
        posts = result.posts;
        prefetchThumbnails(for: posts);
    }

    func loadMorePosts() async {
        guard !isLoading, !allLoaded else { return; }
        let generation = loadGeneration;
        isLoading = true;
        let result = await fetchRecentPosts(page + 1, limit, searchTag);
        guard generation == loadGeneration else { return; }
        isLoading = false;
        guard !result.failed else { return; }
        page = result.page;
        allLoaded = !result.hasMore;
        posts += result.posts;
        prefetchThumbnails(for: result.posts);
    }

}

struct FavoriteGridCell: View {
    @Binding var post: PostContent;
    let search: String;
    let onUnfavorite: () -> Void;
    @Environment(\.selectPost) private var selectPost;

    var body: some View {
        Group {
            if let selectPost {
                Button { selectPost(post); } label: {
                    PostGridCell(post: post).equatable()
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: PostDestination(post: post, search: search)) {
                    PostGridCell(post: post).equatable()
                }
            }
        }
        .postContextMenu(post: $post, onUnfavorite: onUnfavorite)
    }
}
