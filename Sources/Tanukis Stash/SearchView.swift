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
    @State private var activeSearch: String;

    @State private var navigateToTagName: String?;
    @State var infoText: String = ""
    @State private var scrolledPostID: Int?;
    @State private var isLoading: Bool = false;
    @State private var allLoaded: Bool = false;

    var limit = 75;
    var loadingText = "Loading posts...";
    var noPostsFoundText = "No posts found";

    init(search: String) {
        self.search = search;
        self.activeSearch = search;
    }
    
    var postGrid: some View {
        ScrollView(.vertical) {
            if(posts.count == 0) {
                ProgressView(infoText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            PaginatedPostGrid(posts: $posts, search: activeSearch, allLoaded: allLoaded) {
                await getPosts(append: true);
            }
        }
        .scrollPosition(id: $scrolledPostID)
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(activeSearch.isEmpty ? "Recent" : "Results")
        .searchable(text: $search, prompt: "Search for tags") {
            ForEach(searchSuggestions, id: \.self) { tag in
                Button(action: {
                    updateSearch(tag.name);
                }) {
                    Text(tag.name)
                        .foregroundColor(tagCategoryColor(tag.category));
                }
            }
        }
        .navigationDestination(item: $navigateToTagName) { tagName in
            TagView(tagName: tagName, searchEnabled: true)
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") {
                    showSettings = true;
                }
            }
            if (AUTHENTICATED) {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: FavoritesView()) {
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
                searchSuggestions = [];
                activeSearch = "";
                posts = [];
                Task {
                    await getPosts(append: false);
                }
            } else {
                debouncedTagSuggestion(query: search, task: &suggestionTask, results: $searchSuggestions);
            }
        }
        .onSubmit(of: .search) {
            let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines);
            if isSingleTagQuery(trimmedSearch) {
                navigateToTagName = trimmedSearch;
                dismissSearch();
            } else {
                activeSearch = search;
                posts = [];
                Task.init {
                    await getPosts(append: false);
                    searchSuggestions.removeAll();
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
            infoText = loadingText;
            let newPosts: [PostContent];
            if append {
                page += 1;
                let result = await fetchRecentPosts(page, limit, activeSearch);
                guard !Task.isCancelled else { return; }
                allLoaded = !result.hasMore;
                newPosts = result.posts;
                posts += newPosts;
            } else {
                page = 1;
                allLoaded = false;
                let result = await fetchRecentPosts(page, limit, activeSearch);
                guard !Task.isCancelled else { return; }
                allLoaded = !result.hasMore;
                newPosts = result.posts;
                posts = newPosts;
            }

            if posts.count == 0 {
                infoText = noPostsFoundText;
            }

            prefetchThumbnails(for: newPosts);
        };
        loadTask = task;
        await task.value;
    }
    
    func updateSearch(_ tag: String) {
        search = replaceLastSearchWord(in: search, with: tag);
    }
    
}

struct PostPreviewFrame: View {
    @Binding var post: PostContent;
    let search: String;

    var body: some View {
        NavigationLink(destination: PostView(post: post, search: search)) {
            PostGridCell(post: post)
        }
        .postContextMenu(post: $post)
    }
}
