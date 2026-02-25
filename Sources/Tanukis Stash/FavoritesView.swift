//
//  FavoritesView.swift
//  Tanuki
//

import SwiftUI
import Kingfisher

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
    @State private var infoText: String = "Loading favorites...";
    @State private var sortOption: FavoriteSortOption = .newest;

    private var searchTag: String {
        "fav:\(UserDefaults.standard.string(forKey: "username") ?? "")"
    }

    var limit = 75;
    var vGridLayout = [
        GridItem(.flexible(minimum: 75)),
        GridItem(.flexible()),
        GridItem(.flexible())
    ];

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
            LazyVGrid(columns: vGridLayout) {
                ForEach(Array(sortedPosts.enumerated()), id: \.element.id) { i, post in
                    PostPreviewFrame(post: post, search: searchTag)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task {
                                await unfavorite(post: post)
                            }
                        } label: {
                            Label("Unfavorite", systemImage: "heart.slash")
                        }
                    }
                    .onAppear {
                        if i >= posts.count - 18 {
                            Task {
                                await loadMorePosts()
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
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
            posts = await fetchRecentPosts(page, limit, searchTag);
            prefetchThumbnails();
        }
    }

    func unfavorite(post: PostContent) async {
        let _ = await unFavoritePost(postId: post.id);
        withAnimation {
            posts.removeAll { $0.id == post.id }
        }
    }

    func loadPosts() async {
        infoText = "Loading favorites...";
        page = 1;
        posts = await fetchRecentPosts(page, limit, searchTag);
        if posts.count == 0 {
            infoText = "No favorites found";
        }
        prefetchThumbnails();
    }

    func loadMorePosts() async {
        guard !isLoading else { return; }
        isLoading = true;
        page += 1;
        posts += await fetchRecentPosts(page, limit, searchTag);
        isLoading = false;
        prefetchThumbnails();
    }

    func prefetchThumbnails() {
        let prefetchURLs = posts.compactMap { URL(string: $0.preview.url ?? "") };
        ImagePrefetcher(urls: prefetchURLs).start();
    }
}
