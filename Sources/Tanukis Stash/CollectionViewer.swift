//
//  CollectionViewer.swift
//  Tanuki
//
//  Pager + grid over a post's pool or parent/child family. Entered
//  automatically from PostEntry; also opened for pool links (PoolDestination).
//

import SwiftUI
import Kingfisher
import os.log

@MainActor
struct CollectionViewer: View {
    let collections: [PostCollection];
    let seed: PostContent?;
    let search: String;
    let highlightCommentId: Int?;

    init(
        primary: PostCollection,
        others: [PostCollection] = [],
        seed: PostContent? = nil,
        search: String = "",
        highlightCommentId: Int? = nil,
        pool: PoolContent? = nil
    ) {
        collections = [primary] + others;
        self.seed = seed;
        self.search = search;
        self.highlightCommentId = highlightCommentId;
        _active = State(initialValue: primary);
        // Entering never waits on the network: the tapped post is page one
        // until the collection arrives.
        _posts = State(initialValue: seed.map { [$0] } ?? []);
        _scrolledId = State(initialValue: seed?.id);
        _pool = State(initialValue: pool);
        if let pool {
            _poolNames = State(initialValue: [pool.id: Self.displayName(pool.name)]);
        }
    }

    @State private var active: PostCollection;
    @State private var posts: [PostContent];
    @State private var scrolledId: Int?;
    @State private var pool: PoolContent?;
    @State private var poolNames: [Int: String] = [:];
    @State private var showGrid = false;
    @State private var isLoading = true;
    @State private var loadFailed = false;
    // The collection `posts` was last fully loaded for. Lets .task skip the
    // reload when the viewer reappears after a push/pop.
    @State private var loadedCollection: PostCollection?;
    @State private var gridWidth: CGFloat = 0;

    @Namespace private var gridTransition;
    @Environment(\.isPadRegular) private var isPadRegular;

    private static func displayName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ");
    }

    private var currentIndex: Int? {
        posts.firstIndex { $0.id == scrolledId };
    }
    private var currentPost: PostContent? {
        currentIndex.map { posts[$0] };
    }
    private var totalCount: Int {
        if case .pool = active, let pool { return max(pool.post_count, posts.count); }
        return posts.count;
    }
    private var title: String {
        name(for: active);
    }

    private func name(for collection: PostCollection) -> String {
        switch collection {
        case .pool(let id): return poolNames[id] ?? "Pool \(id)";
        case .family: return "Related Posts";
        }
    }

    var body: some View {
        Group {
            if posts.isEmpty {
                emptyState
            } else {
                ZStack {
                    carouselView
                        .environment(\.isMediaPlaybackActive, !showGrid)
                        .opacity(showGrid ? 0 : 1)
                        .allowsHitTesting(!showGrid)
                        .accessibilityHidden(showGrid)
                        .zIndex(showGrid ? 0 : 1)
                    gridView
                        .opacity(showGrid ? 1 : 0)
                        .allowsHitTesting(showGrid)
                        .accessibilityHidden(!showGrid)
                        .zIndex(showGrid ? 1 : 0)
                }
            }
        }
        // Picks up vote/favorite totals cast on the same posts in a screen
        // pushed from here — see PostStatsSync.swift. Non-consuming: the entries
        // are also owned by the grid behind this viewer, which consumes them.
        .onAppear { overlayPendingPostStats(); }
        // Loads on first appearance and whenever the active collection changes
        // (the previous load is cancelled). Reappearing after a push/pop keeps
        // what is already loaded; a failed or interrupted load tries again.
        .task(id: active) {
            guard loadedCollection != active || loadFailed else { return; }
            await load();
        }
        .task { await loadPoolNames(); }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { topBarItems }
        .postActionsToolbar(post: currentPost, isVisible: !showGrid, mutate: mutatePost) {
            PageSelectorPill(
                posts: posts,
                currentId: scrolledId,
                total: totalCount,
                isLoading: isLoading,
                loadFailed: loadFailed,
                onSelect: jump(to:),
                onRetry: { Task { await load(); } }
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isLoading {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed {
            PostLoadFailedView(retry: load)
        } else {
            ContentUnavailableView("No posts found", systemImage: "photo.on.rectangle.angled")
        }
    }

    // MARK: - Carousel

    private var carouselView: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(posts, id: \.id) { post in
                    page(for: post)
                        .id(post.id)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledId)
    }

    private func page(for post: PostContent) -> some View {
        ScrollView(.vertical) {
            PostDetailContent(
                post: post,
                search: search,
                highlightCommentId: post.id == seed?.id ? highlightCommentId : nil,
                showsRelated: posts.count == 1 && !isLoading,
                matchedGeometry: MediaMatchedGeometry(namespace: gridTransition, isSource: !showGrid)
            )
        }
    }

    // MARK: - Grid

    private var gridView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                if case .pool = active, let pool, !pool.description.isEmpty {
                    DTextView(text: pool.description)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                // Binding-collection form keys cells by post id, so switching
                // collections (which shrinks `posts`) can't leave a live cell
                // holding a stale index.
                LazyVGrid(columns: postGridColumns(forWidth: gridWidth, isPadRegular: isPadRegular)) {
                    ForEach($posts, id: \.id) { $post in
                        Button {
                            scrolledId = post.id;
                            withAnimation(.easeInOut(duration: 0.25)) { showGrid = false }
                        } label: {
                            gridCell(post: post, isSelected: post.id == scrolledId)
                        }
                        .postContextMenu(post: $post)
                        .id(post.id)
                    }
                }
                .padding(10)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0; }
            }
            .refreshable { await load(); }
            .onAppear {
                if let scrolledId { proxy.scrollTo(scrolledId, anchor: .center); }
            }
            .onChange(of: showGrid) { _, visible in
                if visible, let scrolledId {
                    proxy.scrollTo(scrolledId, anchor: .center);
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var topBarItems: some ToolbarContent {
        if collections.count > 1 {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(collections) { collection in
                        Button {
                            switchTo(collection);
                        } label: {
                            if collection == active {
                                Label(name(for: collection), systemImage: "checkmark")
                            } else {
                                Text(name(for: collection))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.stack")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showGrid.toggle(); }
            } label: {
                Image(systemName: showGrid ? "square.stack" : "square.grid.2x2")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }

    // MARK: - Data

    private func jump(to postId: Int) {
        withAnimation(.easeInOut(duration: 0.3)) { scrolledId = postId; }
    }

    private func mutatePost(_ postId: Int, _ change: (inout PostContent) -> Void) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return; }
        change(&posts[index]);
    }

    private func overlayPendingPostStats() {
        for index in posts.indices {
            if let recorded = pendingPostStatsUpdate(for: posts[index].id), recorded != posts[index] {
                posts[index] = recorded;
            }
        }
    }

    // Keeps the current post as the lone page while the new collection loads,
    // so the user never sees the previous collection's posts under a new title.
    private func switchTo(_ collection: PostCollection) {
        guard collection != active else { return; }
        if let current = currentPost { posts = [current]; }
        pool = nil;
        isLoading = true;
        active = collection;
    }

    private func load() async {
        isLoading = true;
        loadFailed = false;
        let target = active;
        let result = await fetchPostCollection(target, seed: currentPost ?? seed);
        // A load for a collection that is no longer active (switched meanwhile,
        // including from a Retry or pull-to-refresh that .task(id:) can't
        // cancel) or that was cancelled must not touch state; the newer load
        // owns isLoading.
        guard !Task.isCancelled, target == active else { return; }
        if let loaded = result.pool {
            pool = loaded;
            poolNames[loaded.id] = Self.displayName(loaded.name);
        }
        guard !result.posts.isEmpty else {
            loadFailed = result.failed;
            isLoading = false;
            return;
        }
        let keep = scrolledId ?? result.posts.first?.id;
        posts = result.posts;
        scrolledId = keep;
        loadFailed = result.failed;
        loadedCollection = result.failed ? nil : target;
        isLoading = false;
        prefetchThumbnails(for: posts);
    }

    private func loadPoolNames() async {
        guard collections.count > 1 else { return; }
        for case .pool(let id) in collections where poolNames[id] == nil {
            if let fetched = await fetchPool(poolId: id) {
                poolNames[id] = Self.displayName(fetched.name);
            }
        }
    }
}

// The bottom-bar page selector: "13 of 16 ⌃". Tapping it opens a popover with
// a horizontally scrolling strip of numbered thumbnails to skip around.
struct PageSelectorPill: View {
    let posts: [PostContent];
    let currentId: Int?;
    let total: Int;
    let isLoading: Bool;
    let loadFailed: Bool;
    let onSelect: (Int) -> Void;
    let onRetry: () -> Void;

    @State private var expanded = false;

    private var index: Int? {
        posts.firstIndex { $0.id == currentId };
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 44)
            } else if loadFailed {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            } else if let index {
                Button {
                    expanded.toggle();
                } label: {
                    HStack(spacing: 4) {
                        Text("\(index + 1) of \(total)")
                            .monospacedDigit()
                        if posts.count > 1 {
                            Image(systemName: "chevron.up")
                                .font(.caption2.weight(.bold))
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                    }
                }
                .disabled(posts.count <= 1)
                .accessibilityLabel("Page \(index + 1) of \(total)")
                .accessibilityHint("Opens the page picker")
                .popover(isPresented: $expanded) {
                    PageStrip(posts: posts, currentId: currentId) { id in
                        expanded = false;
                        onSelect(id);
                    }
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
    }
}

private struct PageStrip: View {
    let posts: [PostContent];
    let currentId: Int?;
    let onSelect: (Int) -> Void;

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(posts.enumerated()), id: \.element.id) { offset, post in
                        Button {
                            onSelect(post.id);
                        } label: {
                            thumbnail(post, number: offset + 1, isCurrent: post.id == currentId)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Page \(offset + 1)")
                        .id(post.id)
                    }
                }
                .padding(12)
            }
            .onAppear {
                if let currentId { proxy.scrollTo(currentId, anchor: .center); }
            }
        }
        .frame(width: 300, height: 118)
    }

    private func thumbnail(_ post: PostContent, number: Int, isCurrent: Bool) -> some View {
        KFImage(URL(string: post.preview.url ?? ""))
            .resizable()
            .scaledToFill()
            .frame(width: 64, height: 86)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomTrailing) {
                Text("\(number)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 3)
            )
    }
}
