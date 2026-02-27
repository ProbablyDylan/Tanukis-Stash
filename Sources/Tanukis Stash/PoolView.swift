//
//  PoolView.swift
//  Tanuki
//

import SwiftUI
import Kingfisher
import AlertToast
import os.log

@MainActor
struct PoolView: View {
    let poolId: Int

    init(poolId: Int, pool: PoolContent? = nil, initialPosts: [PostContent] = []) {
        self.poolId = poolId;
        _pool = State(initialValue: pool);
        _posts = State(initialValue: initialPosts);
        _isLoading = State(initialValue: !initialPosts.isEmpty);
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

    @State private var AUTHENTICATED = UserDefaults.standard.bool(forKey: "AUTHENTICATED")
    @Namespace private var gridTransition

    private let limit = 75
    private let gridColumns = [
        GridItem(.flexible(minimum: 75)),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

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
            if scrolledIndex == nil { scrolledIndex = currentIndex; }
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
        .toast(isPresenting: Binding<Bool>(
            get: { [1, 3, 4, 5].contains(displayToastType) },
            set: { _ in }
        )) {
            getToast()
        }
        .onChange(of: displayToastType) { _, newValue in
            if newValue == 2 { clearToast() }
        }
        .navigationDestination(item: $selectedArtist) { artist in
            TagView(tagName: artist)
        }
    }

    // MARK: - Carousel

    private var carouselView: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
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
                    MediaView(post: post, geometry: geometry)
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
                .padding(EdgeInsets(top: 0, leading: -10, bottom: 0, trailing: -10))

                    // Metadata bar
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(post.rating.uppercased()) · #\(post.id)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up")
                                    Text("\(post.score.total)")
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "heart.fill")
                                    Text("\(post.fav_count)")
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "bubble.right")
                                    Text("\(post.comment_count)")
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        artistView(for: post)
                    }
                    .padding(12)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
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

    @ViewBuilder
    private func artistView(for post: PostContent) -> some View {
        if post.tags.artist.count == 1 {
            NavigationLink(destination: TagView(tagName: post.tags.artist[0])) {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette.fill")
                    Text(post.tags.artist[0])
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        } else if post.tags.artist.count > 1 {
            Menu {
                ForEach(post.tags.artist, id: \.self) { artist in
                    Button(artist) {
                        selectedArtist = artist;
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette.fill")
                    Text(post.tags.artist.joined(separator: ", "))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                LazyVGrid(columns: gridColumns) {
                    ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                        Button {
                            currentIndex = index;
                            scrolledIndex = index;
                            withAnimation(.easeInOut(duration: 0.25)) { showGrid = false }
                        } label: {
                            gridCell(post: post, isSelected: index == currentIndex)
                        }
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
                prefetchThumbnails()
            }
            .onAppear {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
    }

    private func gridCell(post: PostContent, isSelected: Bool) -> some View {
        ZStack {
            if let urlStr = post.preview.url {
                KFImage(URL(string: urlStr))
                    .placeholder {
                        ProgressView()
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(width: 100, height: 150)
                    }
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: 150)
                    .shadow(color: Color.primary.opacity(0.3), radius: 1)
            } else {
                Text("Deleted")
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: 150)
                    .background(Color.gray.opacity(0.90))
            }
            VStack {
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                    Text(post.score.total.formatted(.number.notation(.compactName)))
                    Image(systemName: "heart.fill")
                        .padding(.leading, 1)
                    Text(post.fav_count.formatted(.number.notation(.compactName)))
                    Image(systemName: "bubble.right")
                        .padding(.leading, 1)
                    Text(post.comment_count.formatted(.number.notation(.compactName)))
                }
                .font(.system(size: 10))
                .fontWeight(.bold)
                .foregroundColor(Color.white)
                .frame(maxWidth: .infinity)
                .padding(5.0)
                .background(Color.gray.opacity(0.50))
            }
        }
        .matchedGeometryEffect(id: "post_\(post.id)", in: gridTransition, isSource: showGrid)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .padding(0.1)
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
                        Task {
                            favorited = favorited
                                ? await unFavoritePost(postId: post.id)
                                : await favoritePost(postId: post.id)
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
                    if let post = currentPost {
                        ShareLink(
                            item: URL(string: "https://\(UserDefaults.standard.string(forKey: "api_source") ?? "e926.net")/posts/\(post.id)")!,
                            label: { Label("Share Link", systemImage: "link") }
                        )
                    }
                    Button {
                        prepareAndShareContent()
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

        posts = allPosts;
        allLoaded = true;
        isLoading = false;
        prefetchThumbnails();
        if let first = posts.first {
            favorited = first.is_favorited;
        }
        await fetchCurrentPostVote();
    }

    private func prefetchThumbnails() {
        let urls = posts.compactMap { URL(string: $0.preview.url ?? "") }
        ImagePrefetcher(urls: urls).start()
    }

    private func fetchCurrentPostVote() async {
        guard let post = currentPost else { return }
        our_score = await getVote(postId: post.id)
        score_valid = [-1, 0, 1].contains(our_score)
    }

    // MARK: - Sharing

    private func prepareAndShareContent() {
        guard let post = currentPost else { return }
        preparingShare = true
        Task {
            do {
                let tempURL = try await downloadToTemp(post: post)
                await MainActor.run {
                    shareItems = [tempURL]
                    showShareSheet = true
                    preparingShare = false
                }
            } catch {
                os_log("%{public}s", log: .default, "prepareAndShareContent error: \(String(describing: error))")
                await MainActor.run { preparingShare = false; displayToastType = 1 }
            }
        }
    }

    private func downloadToTemp(post: PostContent) async throws -> URL {
        let ext = post.file.ext
        let downloadURL: URL

        if ext == "webm" || ext == "mp4" {
            guard let url = getVideoLink(post: post) else { throw URLError(.fileDoesNotExist) }
            downloadURL = url
        } else {
            guard let urlString = post.file.url, let url = URL(string: urlString) else {
                throw URLError(.badURL)
            }
            downloadURL = url
        }

        let destExt = ext == "webm" ? "mp4" : ext
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(post.id).\(destExt)")

        if !FileManager.default.fileExists(atPath: destURL.path) {
            let (downloadedURL, _) = try await URLSession.shared.download(from: downloadURL)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: downloadedURL, to: destURL)
        }
        return destURL
    }

    // MARK: - Toast

    private func clearToast() {
        let current = displayToastType
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if current == displayToastType {
                displayToastType = 0
            }
        }
    }

    private func getToast() -> AlertToast {
        switch displayToastType {
        case 1:
            clearToast()
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Failed to save")
        case 3:
            clearToast()
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Photos permission required")
        case 4:
            clearToast()
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Failed to move file")
        case 5:
            clearToast()
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "No video available")
        default:
            clearToast()
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Unknown error")
        }
    }
}
