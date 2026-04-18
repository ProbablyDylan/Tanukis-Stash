//
//  PoolView.swift
//  Tanuki
//

import SwiftUI
import Kingfisher

@MainActor
struct PoolView: View {
    let poolId: Int

    init(poolId: Int, pool: PoolContent? = nil, initialPosts: [PostContent] = []) {
        self.poolId = poolId;
        _pool = State(initialValue: pool);
        _posts = State(initialValue: initialPosts);
        _isLoading = State(initialValue: initialPosts.isEmpty);
    }

    // Pool & post data
    @State private var pool: PoolContent?
    @State private var posts: [PostContent]
    @State private var currentIndex = 0
    @State private var scrolledIndex: Int?
    @State private var showGrid = false
    @State private var page = 1
    @State private var isLoading = false
    @State private var allLoaded = false
    @State private var infoText = "Loading pool..."

    // Current post interaction state
    @State private var showImageViewer = false
    @State private var favorited = false
    @State private var our_score = 2
    @State private var score_valid = false
    @State private var displayToastType = 0
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var preparingShare = false
    @State private var selectedArtist: String?

    @State private var AUTHENTICATED = UserDefaults.standard.bool(forKey: UDKey.authenticated)
    @Namespace private var gridTransition

    private let limit = 75
    private var poolTag: String { "pool:\(poolId) order:id" }
    private var poolDisplayName: String {
        pool?.name.replacingOccurrences(of: "_", with: " ") ?? "Pool \(poolId)"
    }
    private var currentPost: PostContent? {
        posts.indices.contains(currentIndex) ? posts[currentIndex] : nil
    }
    private var totalCount: Int { pool?.post_count ?? posts.count }

    var body: some View {
        Group {
            if posts.isEmpty {
                ProgressView(infoText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .bottom) {
                    carouselView
                        .opacity(showGrid ? 0 : 1)
                        .zIndex(showGrid ? 0 : 1)
                    gridView
                        .opacity(showGrid ? 1 : 0)
                        .zIndex(showGrid ? 1 : 0)
                    if !showGrid {
                        positionIndicator
                            .zIndex(2)
                    }
                }
            }
        }
        .task {
            if pool == nil { pool = await fetchPool(poolId: poolId) }
            if let first = posts.first {
                favorited = first.is_favorited;
            }
            await loadPosts();
        }
        .onChange(of: currentIndex) { _, newIndex in
            guard posts.indices.contains(newIndex) else { return }
            favorited = posts[newIndex].is_favorited
            score_valid = false
            our_score = 2
            Task {
                let postId = posts[newIndex].id
                let vote = await getVote(postId: postId)
                if currentIndex == newIndex {
                    our_score = vote
                    score_valid = [-1, 0, 1].contains(vote)
                }
            }
        }
        .navigationTitle(poolDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showImageViewer) {
            if let post = currentPost {
                FullscreenImageViewer(post: post)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(activityItems: shareItems)
        }
        .postToast(displayToastType: $displayToastType)
        .navigationDestination(item: $selectedArtist) { artist in
            TagView(tagName: artist)
        }
    }

    // MARK: - Carousel

    private var carouselView: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(posts.enumerated()), id: \.offset) { index, post in
                    poolPostPage(post: post, index: index)
                        .id(index)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledIndex)
        .onChange(of: scrolledIndex) { _, newValue in
            if let newValue, newValue != currentIndex {
                currentIndex = newValue;
            }
        }
    }

    private func poolPostPage(post: PostContent, index: Int) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    MediaView(post: post)
                        .matchedGeometryEffect(id: "post_\(post.id)", in: gridTransition, isSource: !showGrid)
                        .gesture(
                            !["webm", "mp4"].contains(String(post.file.ext))
                            ? TapGesture().onEnded { showImageViewer = true }
                            : nil
                        )
                        .frame(
                            width: geometry.size.width,
                            height: CGFloat(post.file.height) * (geometry.size.width / CGFloat(post.file.width))
                        )
                }
                .aspectRatio(CGFloat(post.file.width) / CGFloat(post.file.height), contentMode: .fit)

                    PostMetadataBar(post: post, selectedArtist: $selectedArtist)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)

                    if !post.description.isEmpty {
                        DisclosureGroup {
                            DTextView(text: post.description)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Text("Description")
                                .font(.title3)
                                .fontWeight(.heavy)
                                .foregroundColor(Color.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if post.comment_count > 0 {
                        CommentsView(post: post)
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    InfoView(post: post, search: poolTag)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Spacer().frame(height: 60)
                }
            }
    }

    // MARK: - Grid

    private var gridView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                if let pool = pool, !pool.description.isEmpty {
                    DTextView(text: pool.description)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                LazyVGrid(columns: postGridColumns) {
                    ForEach(Array(posts.enumerated()), id: \.offset) { index, post in
                        Button {
                            currentIndex = index;
                            scrolledIndex = index;
                            withAnimation(.easeInOut(duration: 0.25)) { showGrid = false }
                        } label: {
                            gridCell(post: post, isSelected: index == currentIndex)
                        }
                        .postContextMenu(post: $posts[index])
                        .id(index)
                    }
                }
                .padding(10)
            }
            .refreshable {
                page = 1
                allLoaded = false
                pool = await fetchPool(poolId: poolId)
                posts = await fetchRecentPosts(page, limit, poolTag)
                prefetchThumbnails(for: posts)
            }
            .onAppear {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
    }

    private func gridCell(post: PostContent, isSelected: Bool) -> some View {
        PostGridCell(post: post)
            .matchedGeometryEffect(id: "post_\(post.id)", in: gridTransition, isSource: showGrid)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
    }

    // MARK: - Position Indicator

    private var positionIndicator: some View {
        Group {
            if isLoading || posts.count <= 1 && !allLoaded {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("\(currentIndex + 1) / \(totalCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.bottom, 8)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showGrid.toggle() }
            } label: {
                Image(systemName: showGrid ? "square.stack" : "square.grid.2x2")
            }
        }
        if !showGrid {
            if AUTHENTICATED {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        guard let post = currentPost else { return }
                        let wasFavorited = favorited;
                        favorited = !wasFavorited;
                        Task {
                            let success = wasFavorited
                                ? await unFavoritePost(postId: post.id)
                                : await favoritePost(postId: post.id);
                            if !success { favorited = wasFavorited; }
                        }
                    } label: {
                        Image(systemName: favorited ? "heart.fill" : "heart")
                            .imageScale(.large)
                            .symbolEffect(.bounce, value: favorited)
                    }
                }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        guard let post = currentPost else { return }
                        Task { our_score = await votePost(postId: post.id, value: 1, no_unvote: false) }
                    } label: {
                        Image(systemName: our_score == 1 ? "arrowshape.up.fill" : "arrowshape.up")
                            .imageScale(.large)
                            .symbolEffect(.bounce, value: our_score)
                    }
                    .disabled(!score_valid)
                    Button {
                        guard let post = currentPost else { return }
                        Task { our_score = await votePost(postId: post.id, value: -1, no_unvote: false) }
                    } label: {
                        Image(systemName: our_score == -1 ? "arrowshape.down.fill" : "arrowshape.down")
                            .imageScale(.large)
                            .symbolEffect(.bounce, value: our_score)
                    }
                    .disabled(!score_valid)
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItemGroup(placement: .bottomBar) {
                Menu {
                    Button {
                        guard let post = currentPost else { return }
                        Task { displayToastType = -1; saveFile(post: post, showToast: $displayToastType) }
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    if let post = currentPost, let shareURL = URL(string: "https://\(UserDefaults.standard.string(forKey: UDKey.apiSource) ?? "e926.net")/posts/\(post.id)") {
                        ShareLink(
                            item: shareURL,
                            label: { Label("Share Link", systemImage: "link") }
                        )
                    }
                    Button {
                        guard let post = currentPost else { return }
                        prepareAndShareContent(post: post, preparingShare: $preparingShare, shareItems: $shareItems, showShareSheet: $showShareSheet, displayToastType: $displayToastType)
                    } label: {
                        Label("Share Content", systemImage: "photo")
                    }
                } label: {
                    Image(systemName: displayToastType == 2 ? "checkmark.circle.fill" : "square.and.arrow.up")
                        .imageScale(.large)
                        .foregroundStyle(displayToastType == 2 ? Color.green : Color.primary)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.pulse, isActive: displayToastType == -1 || preparingShare)
                }
                .disabled(displayToastType == -1 || preparingShare)
            }
        }
    }

    // MARK: - Data Loading

    private func loadPosts() async {
        isLoading = true;
        infoText = "Loading pool...";
        var allPosts: [PostContent] = [];
        var currentPage = 1;

        while true {
            let fetched = await fetchRecentPosts(currentPage, limit, poolTag);
            if fetched.isEmpty { break; }
            let existingIds = Set(allPosts.map { $0.id });
            allPosts += fetched.filter { !existingIds.contains($0.id) };
            if fetched.count < limit { break; }
            currentPage += 1;
        }

        if allPosts.isEmpty {
            infoText = "No posts found";
            isLoading = false;
            return;
        }

        scrolledIndex = currentIndex;
        posts = allPosts;
        allLoaded = true;
        isLoading = false;
        prefetchThumbnails(for: posts);
        if let first = posts.first {
            favorited = first.is_favorited;
        }
        await fetchCurrentPostVote();
    }


    private func fetchCurrentPostVote() async {
        guard let post = currentPost else { return }
        our_score = await getVote(postId: post.id)
        score_valid = [-1, 0, 1].contains(our_score)
    }

}
