//
//  ContentView.swift
//  Tanuki
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI

struct SearchView: View {
    @State var posts = [PostContent]();
    @State var searchSuggestions = [TagSuggestion]();
    @State private var suggestionTask: Task<Void, Never>?;
    @State private var loadTask: Task<Void, Never>?;
    @State var search: String;
    @State var page = 1;
    @State var showSettings = false;
    @AppStorage(UDKey.authenticated) private var AUTHENTICATED: Bool = false;
    @Environment(\.dismissSearch) private var dismissSearch;
    @Environment(\.isPadRegular) private var isPadRegular;
    @Environment(\.pushDestination) private var pushDestination;
    @State private var activeSearch: String;

    @State private var scrolledPostID: Int?;
    @State private var isLoading: Bool = false;
    @State private var hasLoaded: Bool = false;
    @State private var loadFailed: Bool = false;
    @State private var allLoaded: Bool = false;
    @State private var isSearchActive: Bool = false;

    var limit = 75;

    init(search: String) {
        self.search = search;
        self.activeSearch = search;
    }

    @ViewBuilder
    private var emptyState: some View {
        if isLoading || !hasLoaded {
            ProgressView("Loading posts...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed {
            PostLoadFailedView { await getPosts(append: false); }
        } else if !allLoaded {
            BlacklistSkippedView { await getPosts(append: true); }
        } else {
            ContentUnavailableView("No posts found", systemImage: "magnifyingglass")
        }
    }

    // A new query starts from a clean slate so the previous query's terminal
    // state can't flash before the spinner.
    private func resetForNewQuery() {
        posts = [];
        hasLoaded = false;
        loadFailed = false;
    }

    var postGrid: some View {
        ScrollView(.vertical) {
            // Must remain an eager child of the .searchable hierarchy — LazyVStack/LazyVGrid would suppress \.isSearching.
            SearchActiveReader(isActive: $isSearchActive)
            if posts.isEmpty {
                emptyState
            }
            PaginatedPostGrid(posts: $posts, search: activeSearch, allLoaded: allLoaded) {
                await getPosts(append: true);
            }
        }
        .scrollPosition(id: $scrolledPostID)
        // Picks up vote/favorite totals cast in PostView, which can't write
        // back into this array directly — see PostStatsSync.swift.
        .onAppear { applyPendingPostStatsUpdates(to: &posts); }
        .task({
            if (posts.count == 0) {
                await getPosts(append: false);
            }
        })
        .refreshable {
            await getPosts(append: false);
        }
    }

    var body: some View {
        postGrid
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isPadRegular && isSearchActive && !searchSuggestions.isEmpty {
                ChipBar(suggestions: searchSuggestions, onTap: applyChip)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isPadRegular && isSearchActive && !searchSuggestions.isEmpty {
                ChipBar(suggestions: searchSuggestions, onTap: applyChip)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(activeSearch.isEmpty ? "Recent" : "Results")
        .searchable(text: $search, prompt: "Search for tags")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") {
                    showSettings = true;
                }
            }
            if (AUTHENTICATED) {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: FavoritesDestination()) {
                        Label("Favorites", systemImage: "heart")
                    }
                }
            }
        }
        #endif
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: search) {
            if search.isEmpty && !activeSearch.isEmpty {
                suggestionTask?.cancel();
                withAnimation(.snappy) { searchSuggestions = []; }
                activeSearch = "";
                resetForNewQuery();
                Task {
                    await getPosts(append: false);
                }
            } else {
                debouncedTagSuggestion(query: search, task: &suggestionTask, results: $searchSuggestions);
            }
        }
        .onChange(of: isSearchActive) { _, active in
            if !active {
                suggestionTask?.cancel();
                withAnimation(.snappy) { searchSuggestions = []; }
            }
        }
        .onSubmit(of: .search) {
            let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines);
            if isSingleTagQuery(trimmedSearch) {
                pushDestination?(TagDestination(name: trimmedSearch));
                dismissSearch();
            } else {
                activeSearch = search;
                resetForNewQuery();
                Task.init {
                    await getPosts(append: false);
                    withAnimation(.snappy) { searchSuggestions.removeAll(); }
                    dismissSearch();
                }
            }
        }
    }
    
    func getPosts(append: Bool) async {
        if append { guard !allLoaded else { return; } }
        loadTask?.cancel();
        let task = Task {
            isLoading = true;
            defer { isLoading = false; }
            // Commit page/allLoaded only after the cancellation guard — a cancelled
            // append that already bumped `page` silently skips a page of results.
            let result = await fetchRecentPosts(append ? page + 1 : 1, limit, activeSearch);
            guard !Task.isCancelled else { return; }
            if append {
                // A failed append leaves the page counter alone; the grid's
                // load-more fallback retries the same page.
                guard !result.failed else { return; }
                posts += result.posts;
            } else {
                hasLoaded = true;
                loadFailed = result.failed;
                guard !result.failed else { return; }
                posts = result.posts;
            }
            page = result.page;
            allLoaded = !result.hasMore;
            prefetchThumbnails(for: result.posts);
        };
        loadTask = task;
        await task.value;
    }
    
    func applyChip(_ tag: TagSuggestion) {
        search = replaceLastSearchWord(in: search, with: tag.name) + " ";
        searchSuggestions.removeAll { $0 == tag };
    }

}

struct PostPreviewFrame: View {
    @Binding var post: PostContent;
    let search: String;
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
        .postContextMenu(post: $post)
    }
}

struct SearchActiveReader: View {
    @Environment(\.isSearching) private var isSearching;
    @Binding var isActive: Bool;

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: isSearching) { _, new in
                withAnimation(.snappy) { isActive = new; }
            }
    }
}
