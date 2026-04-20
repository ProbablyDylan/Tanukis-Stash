//
//  FavoritesView.swift
//  Tanuki
//

import SwiftUI

enum FavoriteSortOption: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case highestScore = "Score"
    case mostFaved = "Favorites"
}

struct FavoritesView: View {
    @State private var posts = [PostContent]();
    @State private var page = 1;
    @State private var isLoading: Bool = false;
    @State private var allLoaded: Bool = false;
    @State private var infoText: String = "Loading favorites...";
    @State private var sortOption: FavoriteSortOption = .newest;
    @State private var scrolledPostID: Int?;

    private var searchTag: String {
        "fav:\(UserDefaults.standard.string(forKey: UDKey.username) ?? "")"
    }

    var limit = 75;
    private var sortedPosts: [PostContent] {
        switch sortOption {
        case .newest:
            return posts
        case .oldest:
            return posts.reversed()
        case .highestScore:
            return posts.sorted { $0.score.total > $1.score.total }
        case .mostFaved:
            return posts.sorted { $0.fav_count > $1.fav_count }
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            if posts.count == 0 {
                ProgressView(infoText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            PaginatedPostGrid(posts: sortedPosts, allLoaded: allLoaded, loadMore: loadMorePosts) { _, post in
                if let idx = posts.firstIndex(where: { $0.id == post.id }) {
                    NavigationLink(destination: PostView(post: post, search: searchTag)) {
                        PostGridCell(post: post)
                    }
                    .postContextMenu(post: $posts[idx], onUnfavorite: {
                        withAnimation {
                            posts.removeAll { $0.id == post.id }
                        }
                    })
                }
            }
        }
        .scrollPosition(id: $scrolledPostID)
        .task {
            if posts.count == 0 {
                await loadPosts()
            }
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
            page = 1;
            allLoaded = false;
            let result = await fetchRecentPosts(page, limit, searchTag);
            posts = result.posts;
            allLoaded = !result.hasMore;
            prefetchThumbnails(for: posts);
        }
    }

    func loadPosts() async {
        infoText = "Loading favorites...";
        page = 1;
        allLoaded = false;
        let result = await fetchRecentPosts(page, limit, searchTag);
        posts = result.posts;
        allLoaded = !result.hasMore;
        if posts.count == 0 {
            infoText = "No favorites found";
        }
        prefetchThumbnails(for: posts);
    }

    func loadMorePosts() async {
        guard !isLoading, !allLoaded else { return; }
        isLoading = true;
        page += 1;
        let result = await fetchRecentPosts(page, limit, searchTag);
        allLoaded = !result.hasMore;
        posts += result.posts;
        isLoading = false;
        prefetchThumbnails(for: posts);
    }

}
