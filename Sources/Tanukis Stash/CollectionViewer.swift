//
//  CollectionViewer.swift
//  Tanuki
//
//  Pager over a post's pool or parent/child family. Entered automatically from
//  PostEntry; also opened for pool links (PoolDestination). Skipping around is
//  the bottom-bar page selector's job (PageSelectorPill).
//

import SwiftUI
import Kingfisher
import os.log

// How far the first-run hint pushes the pager toward its neighbor.
private let kPagerNudgeDistance: CGFloat = 28;

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
        highlightCommentId: Int? = nil
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
    }

    @State private var active: PostCollection;
    @State private var posts: [PostContent];
    @State private var scrolledId: Int?;
    @State private var pool: PoolContent?;
    @State private var poolNames: [Int: String] = [:];
    @State private var isLoading = true;
    @State private var loadFailed = false;
    // The collection `posts` was last fully loaded for. Lets .task skip the
    // reload when the viewer reappears after a push/pop.
    @State private var loadedCollection: PostCollection?;
    // The first-run swipe hint: the pager content leans toward its neighbor.
    @State private var nudgeOffset: CGFloat = 0;
    @State private var nudgeTask: Task<Void, Never>?;
    @Environment(\.accessibilityReduceMotion) private var reduceMotion;

    private static func displayName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ");
    }

    private var currentIndex: Int? {
        posts.firstIndex { $0.id == scrolledId };
    }
    private var currentPost: PostContent? {
        currentIndex.map { posts[$0] };
    }
    // Pages in the pool that did not load: the site's rating filter (e926), deleted
    // posts, or the blacklist when collections honor it. The pill counts only what
    // can be reached, so this is surfaced separately in the page selector.
    private var hiddenCount: Int {
        if case .pool = active, let pool { return max(0, pool.post_count - posts.count); }
        return 0;
    }
    private var title: String {
        name(for: active);
    }
    // Pool-level DText shown in the page selector's header.
    private var collectionDetails: String? {
        if case .pool = active, let pool, !pool.description.isEmpty { return pool.description; }
        return nil;
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
                carouselView
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
        .postActionsToolbar(post: currentPost, mutate: mutatePost) {
            PageSelectorPill(
                details: collectionDetails,
                posts: posts,
                currentId: scrolledId,
                total: posts.count,
                hiddenCount: hiddenCount,
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
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(posts, id: \.id) { post in
                    page(for: post)
                        .id(post.id)
                        .containerRelativeFrame(.horizontal)
                        // The swipe hint reveals the neighbor, whose sections are
                        // laid out for the first time under the hint's animation;
                        // without this they slide in from where they start.
                        .transaction(value: nudgeOffset) { $0.animation = nil; }
                }
            }
            .scrollTargetLayout()
            .offset(x: nudgeOffset)
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledId)
        // Touching the pager ends the hint at once; paging takes over from there.
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { endNudge(animated: true); }
        }
        .onDisappear { endNudge(animated: false); }
    }

    private func page(for post: PostContent) -> some View {
        ScrollView(.vertical) {
            PostDetailContent(
                post: post,
                search: search,
                highlightCommentId: post.id == seed?.id ? highlightCommentId : nil
            )
        }
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
        // including from a Retry that .task(id:) can't cancel) or that was
        // cancelled must not touch state; the newer load owns isLoading.
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
        nudgeIfFirstTime();
    }

    // A one-time hint that the page swipes: the pager leans toward its neighbor
    // and springs back. Toward the next page, or the previous one when this is
    // the last; nothing for a single page. Once per install, never under Reduce
    // Motion, and only once the collection has loaded so there is a neighbor to
    // lean toward.
    private func nudgeIfFirstTime() {
        guard !UserDefaults.standard.bool(forKey: UDKey.pagerNudgeShown),
              !reduceMotion, !loadFailed, posts.count > 1,
              let index = currentIndex else { return; }
        let direction: CGFloat = index + 1 < posts.count ? 1 : -1;
        UserDefaults.standard.set(true, forKey: UDKey.pagerNudgeShown);
        nudgeTask?.cancel();
        nudgeTask = Task { @MainActor in
            // Let the page settle before it moves.
            try? await Task.sleep(for: .milliseconds(500));
            guard !Task.isCancelled else { return; }
            withAnimation(.easeOut(duration: 0.3)) {
                nudgeOffset = -direction * kPagerNudgeDistance;
            }
            try? await Task.sleep(for: .milliseconds(320));
            guard !Task.isCancelled else { return; }
            withAnimation(.spring(duration: 0.5, bounce: 0.25)) {
                nudgeOffset = 0;
            }
        }
    }

    private func endNudge(animated: Bool) {
        nudgeTask?.cancel();
        nudgeTask = nil;
        guard nudgeOffset != 0 else { return; }
        if animated {
            withAnimation(.easeOut(duration: 0.15)) { nudgeOffset = 0; }
        } else {
            nudgeOffset = 0;
        }
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

// The bottom-bar page selector: "13 of 16 ⌃⌄". Tapping it opens a popover with
// the collection's description (if it has one) above a horizontally scrolling
// strip of numbered thumbnails to skip around.
struct PageSelectorPill: View {
    let details: String?;
    let posts: [PostContent];
    let currentId: Int?;
    let total: Int;
    let hiddenCount: Int;
    let isLoading: Bool;
    let loadFailed: Bool;
    let onSelect: (Int) -> Void;
    let onRetry: () -> Void;

    @State private var expanded = false;
    @State private var selectionCount = 0;

    private enum Phase { case loading, failed, ready }

    private var phase: Phase {
        isLoading ? .loading : (loadFailed ? .failed : .ready);
    }

    private var index: Int? {
        posts.firstIndex { $0.id == currentId };
    }

    // All three states stay in the view and cross-fade by opacity. A toolbar
    // item is hosted separately from the screen, and swapping views in and out
    // of it (if/else + transitions) snapped instead of animating. Keeping them
    // all present also holds the capsule at one size while it loads.
    var body: some View {
        ZStack {
            ProgressView()
                .controlSize(.small)
                .opacity(phase == .loading ? 1 : 0)
                .accessibilityHidden(phase != .loading)
            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .opacity(phase == .failed ? 1 : 0)
            .allowsHitTesting(phase == .failed)
            .accessibilityHidden(phase != .failed)
            countButton
                .opacity(phase == .ready ? 1 : 0)
                .allowsHitTesting(phase == .ready)
                .accessibilityHidden(phase != .ready)
        }
        .animation(.smooth(duration: 0.3), value: phase)
    }

    private var countButton: some View {
        let position = (index ?? 0) + 1;
        return Button {
            expanded.toggle();
        } label: {
            HStack(spacing: 4) {
                Text("\(position) of \(total)")
                    .monospacedDigit()
                if posts.count > 1 {
                    // The pop-up button indicator: the control shows the
                    // current choice among several.
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                }
            }
        }
        .disabled(posts.count <= 1)
        .accessibilityLabel("Page \(position) of \(total)")
        .accessibilityHint("Opens the page picker")
        .popover(isPresented: $expanded) {
            PagePopover(details: details, hiddenCount: hiddenCount, posts: posts, currentId: currentId) { id in
                selectionCount += 1;
                expanded = false;
                onSelect(id);
            }
            .presentationCompactAdaptation(.popover)
        }
        .sensoryFeedback(.selection, trigger: selectionCount)
    }
}

private struct PagePopover: View {
    let details: String?;
    let hiddenCount: Int;
    let posts: [PostContent];
    let currentId: Int?;
    let onSelect: (Int) -> Void;

    @State private var detailsExpanded = false;
    @State private var detailsHeight: CGFloat = 0;

    private let collapsedDetailsHeight: CGFloat = 60;
    private let expandedDetailsHeight: CGFloat = 200;
    private let maxWidth: CGFloat = 340;

    // Fits the thumbnails when there are few (and no description to wrap),
    // up to maxWidth; past that the strip scrolls.
    private var width: CGFloat {
        details == nil ? min(maxWidth, PageStrip.contentWidth(count: posts.count)) : maxWidth;
    }

    private var detailsIsTruncated: Bool {
        detailsHeight > collapsedDetailsHeight;
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let details {
                detailsView(details)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }
            PageStrip(posts: posts, currentId: currentId, onSelect: onSelect)
            if hiddenCount > 0 {
                Label(hiddenCount == 1 ? "1 page hidden" : "\(hiddenCount) pages hidden", systemImage: "eye.slash")
                    .font(.caption)
                    // An explicit color, not `.secondary`: hierarchical styles are
                    // painted through the popover material's vibrancy, which
                    // settles ~0.35s after the presentation, so this row used to
                    // pop in on its own.
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: width)
    }

    // The description is clamped to a few lines; "More" reveals the rest in a
    // short scroll. The natural height is measured inside the scroll view.
    private func detailsView(_ text: String) -> some View {
        let limit = detailsExpanded ? expandedDetailsHeight : collapsedDetailsHeight;
        let height = detailsHeight > 0 ? min(detailsHeight, limit) : limit;
        return VStack(alignment: .leading, spacing: 2) {
            ScrollView(.vertical, showsIndicators: detailsExpanded) {
                DTextView(text: text)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailsHeight = $0; }
            }
            .scrollDisabled(!detailsExpanded)
            .frame(height: height)
            if detailsIsTruncated {
                Button(detailsExpanded ? "Less" : "More") {
                    withAnimation(.snappy) { detailsExpanded.toggle(); }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }
}

private struct PageStrip: View {
    let posts: [PostContent];
    let currentId: Int?;
    let onSelect: (Int) -> Void;

    private static let thumbnailWidth: CGFloat = 92;
    private static let thumbnailHeight: CGFloat = 124;
    private static let spacing: CGFloat = 10;
    private static let padding: CGFloat = 12;

    // The strip's natural width for `count` thumbnails.
    static func contentWidth(count: Int) -> CGFloat {
        CGFloat(count) * thumbnailWidth + CGFloat(max(0, count - 1)) * spacing + 2 * padding;
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Self.spacing) {
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
                .padding(Self.padding)
            }
            .onAppear {
                if let currentId { proxy.scrollTo(currentId, anchor: .center); }
            }
        }
        .frame(height: 160)
    }

    private func thumbnail(_ post: PostContent, number: Int, isCurrent: Bool) -> some View {
        KFImage(URL(string: post.preview.url ?? ""))
            .resizable()
            .scaledToFill()
            .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomTrailing) {
                Text("\(number)")
                    .font(.caption.weight(.bold))
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
