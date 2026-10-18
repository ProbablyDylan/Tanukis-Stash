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
        // Picks up vote/favorite totals cast in a pushed PostView, which can't
        // write back here directly — see PostStatsSync.swift.
        .onAppear { applyPendingPostStatsUpdates(to: &posts); }
        // Reloads whenever the active collection changes; the previous load
        // is cancelled, so a stale collection can never overwrite a newer one.
        .task(id: active) { await load(); }
        .task { await loadPoolNames(); }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { topBarItems }
        .postActionsToolbar(post: currentPost, isVisible: !showGrid, mutate: mutatePost)
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
                showsRelated: false,
                matchedGeometry: MediaMatchedGeometry(namespace: gridTransition, isSource: !showGrid),
                bottomInset: 60
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

    // MARK: - Position indicator

    private var positionIndicator: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if loadFailed {
                Button {
                    Task { await load(); }
                } label: {
                    Label("\(posts.count) / \(totalCount) · Retry", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
            } else if let index = currentIndex {
                Text("\(index + 1) / \(totalCount)")
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
                showGrid.toggle();
            } label: {
                Image(systemName: showGrid ? "square.stack" : "square.grid.2x2")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }

    // MARK: - Data

    private func mutatePost(_ postId: Int, _ change: (inout PostContent) -> Void) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return; }
        change(&posts[index]);
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
        let result = await fetchPostCollection(active, seed: currentPost ?? seed);
        // A cancelled load (collection switched, view gone) must not touch state.
        guard !Task.isCancelled else { return; }
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
