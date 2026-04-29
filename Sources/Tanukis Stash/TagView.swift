//
//  TagView.swift
//  Tanuki
//

import SwiftUI

struct TagView: View {
    let tagName: String;
    var searchEnabled: Bool = false;

    @State private var wiki: WikiPage?;
    @State private var tagDetail: TagDetail?;
    @State private var aliases = [TagAlias]();
    @State private var relatedTags = [String]();
    @State private var tagCategories = [String: Int]();
    @State private var posts = [PostContent]();
    @State private var page = 1;
    @State private var isLoading: Bool = false;
    @State private var allLoaded: Bool = false;
    @State private var initialLoadComplete: Bool = false;
    @State private var wikiExpanded: Bool = false;
    @State private var aliasesExpanded: Bool = false;
    @State private var relatedTagsExpanded: Bool = false;

    @State private var search: String = "";
    @State private var searchSuggestions = [TagSuggestion]();
    @State private var suggestionTask: Task<Void, Never>?;
    @State private var navigateToTagName: String?;
    @State private var navigateToSearch: String?;
    @State private var scrolledPostID: Int?;
    @Environment(\.dismissSearch) private var dismissSearch;

    var limit = 75;
    private var displayName: String {
        tagName.replacingOccurrences(of: "_", with: " ");
    }

    var tagContent: some View {
        ScrollView(.vertical) {
            if let wiki = wiki, !wiki.body.isEmpty {
                DisclosureGroup(isExpanded: $wikiExpanded.animation(.smooth)) {
                    DTextView(text: wiki.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Wiki")
                        .font(.title3)
                        .fontWeight(.heavy)
                        .foregroundColor(Color.primary)
                }
                .padding(10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !aliases.isEmpty {
                DisclosureGroup(isExpanded: $aliasesExpanded.animation(.smooth)) {
                    VStack(alignment: .leading) {
                        ForEach(aliases, id: \.id) { alias in
                            NavigationLink(destination: TagView(tagName: alias.antecedent_name)) {
                                Text(alias.antecedent_name.replacingOccurrences(of: "_", with: " "))
                                    .font(.body)
                                    .foregroundColor(tagCategoryColor(tagCategories[alias.antecedent_name] ?? 0))
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Aliases")
                        .font(.title3)
                        .fontWeight(.heavy)
                        .foregroundColor(Color.primary)
                }
                .padding(10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !relatedTags.isEmpty {
                DisclosureGroup(isExpanded: $relatedTagsExpanded.animation(.smooth)) {
                    VStack(alignment: .leading) {
                        ForEach(relatedTags, id: \.self) { tag in
                            NavigationLink(destination: TagView(tagName: tag)) {
                                Text(tag.replacingOccurrences(of: "_", with: " "))
                                    .font(.body)
                                    .foregroundColor(tagCategoryColor(tagCategories[tag] ?? 0))
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Related Tags")
                        .font(.title3)
                        .fontWeight(.heavy)
                        .foregroundColor(Color.primary)
                }
                .padding(10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !initialLoadComplete {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .transition(.opacity)
            }

            PaginatedPostGrid(posts: $posts, search: tagName, allLoaded: allLoaded) {
                await loadMorePosts();
            }
        }
        .scrollPosition(id: $scrolledPostID)
        .task {
            async let wikiFetch = fetchWikiPage(tagName: tagName);
            async let detailFetch = fetchTagDetail(tagName: tagName);
            async let aliasesFetch = fetchTagAliases(tagName: tagName);
            async let postsLoad: Void = loadInitialPostsIfNeeded();

            let fetchedWiki = await wikiFetch;
            withAnimation(.smooth) { wiki = fetchedWiki }

            let detail = await detailFetch;
            tagDetail = detail;
            withAnimation(.smooth) {
                relatedTags = parseRelatedTags(detail?.related_tags).filter { $0 != tagName };
            }

            let fetchedAliases = await aliasesFetch;
            withAnimation(.smooth) { aliases = fetchedAliases }

            let allNames = relatedTags + aliases.map { $0.antecedent_name };
            if !allNames.isEmpty {
                tagCategories = await fetchTagCategories(names: allNames);
            }

            await postsLoad;
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(displayName).font(.headline);
                    if let count = tagDetail?.post_count {
                        Text("\(count) posts").font(.caption).foregroundStyle(.secondary);
                    }
                }
            }
            if searchEnabled {
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
        }
        .refreshable {
            page = 1;
            allLoaded = false;
            async let wikiFetch = fetchWikiPage(tagName: tagName);
            async let postsFetch = fetchRecentPosts(1, limit, tagName);
            let fetchedWiki = await wikiFetch;
            withAnimation(.smooth) { wiki = fetchedWiki }
            let result = await postsFetch;
            allLoaded = !result.hasMore;
            withAnimation(.smooth) { posts = result.posts }
            prefetchThumbnails(for: posts);
        }
    }

    @ViewBuilder
    var body: some View {
        if searchEnabled {
            tagContent
                .searchable(text: $search, prompt: "Search for tags") {
                    ForEach(searchSuggestions, id: \.self) { tag in
                        Button(action: { handleSuggestionTap(tag.name); }) {
                            Text(tag.name)
                                .foregroundColor(tagCategoryColor(tag.category));
                        }
                    }
                }
                .onChange(of: search) {
                    debouncedTagSuggestion(query: search, task: &suggestionTask, results: $searchSuggestions);
                }
                .onSubmit(of: .search) {
                    let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines);
                    if isSingleTagQuery(trimmed) {
                        navigateToTagName = trimmed;
                    } else {
                        navigateToSearch = trimmed;
                    }
                    dismissSearch();
                }
                .navigationDestination(item: $navigateToTagName) { tag in
                    TagView(tagName: tag, searchEnabled: true)
                }
                .navigationDestination(item: $navigateToSearch) { query in
                    SearchView(search: query)
                }
        } else {
            tagContent
        }
    }

    func handleSuggestionTap(_ tag: String) {
        search = replaceLastSearchWord(in: search, with: tag);
    }

    func loadInitialPostsIfNeeded() async {
        if posts.isEmpty {
            await loadPosts();
        }
    }

    func loadPosts() async {
        page = 1;
        allLoaded = false;
        let result = await fetchRecentPosts(page, limit, tagName);
        allLoaded = !result.hasMore;
        withAnimation(.smooth) {
            posts = result.posts;
            initialLoadComplete = true;
        }
        prefetchThumbnails(for: posts);
    }

    func loadMorePosts() async {
        guard !isLoading, !allLoaded else { return; }
        isLoading = true;
        page += 1;
        let result = await fetchRecentPosts(page, limit, tagName);
        allLoaded = !result.hasMore;
        withAnimation(.smooth) { posts += result.posts }
        isLoading = false;
        prefetchThumbnails(for: posts);
    }

}
