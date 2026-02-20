//
//  PoolView.swift
//  Tanuki's Stash
//

import SwiftUI
import Kingfisher

struct PoolView: View {
    let poolId: Int;

    @State private var pool: PoolContent?;
    @State private var posts = [PostContent]();
    @State private var page = 1;
    @State private var infoText: String = "Loading pool...";
    @State private var isLoading: Bool = false;

    var limit = 75;
    var vGridLayout = [
        GridItem(.flexible(minimum: 75)),
        GridItem(.flexible()),
        GridItem(.flexible())
    ];

    private var poolTag: String {
        "pool:\(poolId) order:id";
    }

    private var poolDisplayName: String {
        pool?.name.replacingOccurrences(of: "_", with: " ") ?? "Pool \(poolId)";
    }

    var body: some View {
        ScrollView(.vertical) {
            if posts.count == 0 {
                ProgressView(infoText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LazyVGrid(columns: vGridLayout) {
                ForEach(Array(posts.enumerated()), id: \.element) { i, post in
                    PostPreviewFrame(post: post, search: poolTag)
                    .onAppear {
                        if i == posts.count - 18 {
                            Task.init {
                                await loadMorePosts();
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .task {
            if pool == nil {
                pool = await fetchPool(poolId: poolId);
            }
            if posts.count == 0 {
                await loadPosts();
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(poolDisplayName)
        .refreshable {
            page = 1;
            pool = await fetchPool(poolId: poolId);
            posts = await fetchRecentPosts(page, limit, poolTag);
            prefetchThumbnails();
        }
    }

    func loadPosts() async {
        infoText = "Loading pool...";
        page = 1;
        posts = await fetchRecentPosts(page, limit, poolTag);
        if posts.count == 0 {
            infoText = "No posts found";
        }
        prefetchThumbnails();
    }

    func loadMorePosts() async {
        guard !isLoading else { return; }
        isLoading = true;
        page += 1;
        posts += await fetchRecentPosts(page, limit, poolTag);
        isLoading = false;
        prefetchThumbnails();
    }

    func prefetchThumbnails() {
        let prefetchURLs = posts.compactMap { URL(string: $0.preview.url ?? "") };
        ImagePrefetcher(urls: prefetchURLs).start();
    }
}
