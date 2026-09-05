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
    @State private var isLoading = false
    @State private var allLoaded = false
    @State private var loadFailed = false
    @State private var infoText = "Loading pool..."

    // Current post interaction state
    @State private var showImageViewer = false
    @State private var favorited = false
    @State private var our_score = 2
    @State private var score_valid = false
    @State private var displayToastType: MediaActionState = .idle
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var preparingShare = false
    @State private var gridWidth: CGFloat = 0

    @AppStorage(UDKey.authenticated) private var AUTHENTICATED: Bool = false
    @Namespace private var gridTransition
    @Environment(\.isPadRegular) private var isPadRegular

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
            if posts.indices.contains(currentIndex) {
                favorited = posts[currentIndex].is_favorited;
            }
            await loadPosts();
        }
        .onChange(of: currentIndex) { _, newIndex in
            guard posts.indices.contains(newIndex) else { return }
            favorited = posts[newIndex].is_favorited;
            applyCurrentPostVote();
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
    }

    // MARK: - Carousel

    private var carouselView: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(posts.indices, id: \.self) { index in
                    poolPostPage(post: posts[index], index: index)
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

                    PostMetadataBar(post: post)
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
                .frame(maxWidth: isPadRegular ? 900 : .infinity)
                .frame(maxWidth: .infinity)
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
                LazyVGrid(columns: postGridColumns(forWidth: gridWidth, isPadRegular: isPadRegular)) {
                    ForEach(posts.indices, id: \.self) { index in
                        Button {
                            currentIndex = index;
                            scrolledIndex = index;
                            withAnimation(.easeInOut(duration: 0.25)) { showGrid = false }
                        } label: {
                            gridCell(post: posts[index], isSelected: index == currentIndex)
                        }
                        .postContextMenu(post: $posts[index])
                        .id(index)
                    }
                }
                .padding(10)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0; }
            }
            .refreshable {
                pool = await fetchPool(poolId: poolId);
                await loadPosts();
            }
            .onAppear {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
            .onChange(of: showGrid) { _, visible in
                if visible {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
    }

    private func gridCell(post: PostContent, isSelected: Bool) -> some View {
        PostGridCell(post: post)
            .equatable()
            .matchedGeometryEffect(id: "post_\(post.id)", in: gridTransition, isSource: showGrid)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
    }

    // MARK: - Position Indicator

    private var positionIndicator: some View {
        Group {
            if isLoading || posts.count <= 1 && !allLoaded && !loadFailed {
                ProgressView()
                    .controlSize(.small)
            } else if loadFailed {
                Button {
                    Task { await loadPosts(); }
                } label: {
                    Label("\(posts.count) / \(totalCount) · Retry", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
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
                showGrid.toggle()
            } label: {
                Image(systemName: showGrid ? "square.stack" : "square.grid.2x2")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        if !showGrid {
            if AUTHENTICATED {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        guard let post = currentPost else { return }
                        let wasFavorited = favorited;
                        favorited = !wasFavorited;
                        posts[currentIndex].is_favorited = !wasFavorited;
                        Task {
                            let success = wasFavorited
                                ? await unFavoritePost(postId: post.id)
                                : await favoritePost(postId: post.id);
                            if !success {
                                favorited = wasFavorited;
                                posts[currentIndex].is_favorited = wasFavorited;
                            }
                        }
                    } label: {
                        Image(systemName: favorited ? "heart.fill" : "heart")
                            .imageScale(.large)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: favorited)
                    }
                }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        guard let post = currentPost else { return }
                        Task { await applyVote(post: post, value: 1) }
                    } label: {
                        Image(systemName: our_score == 1 ? "arrowshape.up.fill" : "arrowshape.up")
                            .imageScale(.large)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: our_score)
                    }
                    .disabled(!score_valid)
                    Button {
                        guard let post = currentPost else { return }
                        Task { await applyVote(post: post, value: -1) }
                    } label: {
                        Image(systemName: our_score == -1 ? "arrowshape.down.fill" : "arrowshape.down")
                            .imageScale(.large)
                            .contentTransition(.symbolEffect(.replace))
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
                        saveFile(post: post, showToast: $displayToastType);
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        guard let post = currentPost else { return }
                        prepareAndShareContent(post: post, preparingShare: $preparingShare, shareItems: $shareItems, showShareSheet: $showShareSheet, displayToastType: $displayToastType, includeLink: true)
                    } label: {
                        Label("Share Link", systemImage: "link")
                    }
                    Button {
                        guard let post = currentPost else { return }
                        prepareAndShareContent(post: post, preparingShare: $preparingShare, shareItems: $shareItems, showShareSheet: $showShareSheet, displayToastType: $displayToastType)
                    } label: {
                        Label("Share Content", systemImage: "photo")
                    }
                } label: {
                    MediaActionMenuLabel(state: displayToastType, preparingShare: preparingShare)
                }
                .disabled(displayToastType == .inProgress || preparingShare)
            }
        }
    }

    // MARK: - Data Loading

    private func loadPosts() async {
        isLoading = true;
        loadFailed = false;
        infoText = "Loading pool...";
        var allPosts: [PostContent] = [];
        var currentPage = 1;
        let maxPages = 20;

        var failed = false;

        while currentPage <= maxPages {
            if Task.isCancelled {
                isLoading = false;
                return;
            }
            let result = await fetchRecentPosts(currentPage, limit, poolTag);
            if result.failed { failed = true; break; }
            let existingIds = Set(allPosts.map { $0.id });
            allPosts += result.posts.filter { !existingIds.contains($0.id) };
            if !result.hasMore { break; }
            currentPage = result.page + 1;
        }

        if Task.isCancelled {
            isLoading = false;
            return;
        }

        if allPosts.isEmpty {
            infoText = failed ? "Couldn't load pool" : "No posts found";
            isLoading = false;
            return;
        }

        scrolledIndex = currentIndex;
        posts = allPosts;
        // A page failure mid-pool keeps what loaded; the indicator offers a retry.
        allLoaded = !failed;
        loadFailed = failed;
        isLoading = false;
        prefetchThumbnails(for: posts);
        if posts.indices.contains(currentIndex) {
            favorited = posts[currentIndex].is_favorited;
        }
        applyCurrentPostVote();
    }

    // Written back into the listing so swiping away and returning doesn't
    // resurrect the vote the post was loaded with.
    private func applyVote(post: PostContent, value: Int) async {
        guard let score = await votePost(postId: post.id, value: value, no_unvote: false) else { return; }
        our_score = score;
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index].vote = score;
        }
    }

    // The pool listing already carries the authenticated user's vote.
    private func applyCurrentPostVote() {
        guard let post = currentPost else { return; }
        our_score = post.vote;
        score_valid = true;
    }

}
