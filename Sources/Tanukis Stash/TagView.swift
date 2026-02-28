//
//  TagView.swift
//  Tanuki
//

import SwiftUI
import Kingfisher

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
    @State private var initialLoadComplete: Bool = false;
    @State private var wikiExpanded: Bool = true;

    @State private var search: String = "";
    @State private var searchSuggestions = [TagSuggestion]();
    @State private var suggestionTask: Task<Void, Never>?;
    @State private var navigateToTagName: String?;
    @State private var navigateToSearch: String?;
    @Environment(\.dismissSearch) private var dismissSearch;

    var limit = 75;
    private var displayName: String {
        tagName.replacingOccurrences(of: "_", with: " ");
    }

    var tagContent: some View {
        ScrollView(.vertical) {
            if let wiki = wiki, !wiki.body.isEmpty {
                DisclosureGroup(isExpanded: $wikiExpanded) {
                    DTextView(text: wiki.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Wiki")
                        .font(.title3)
                        .fontWeight(.heavy)
                        .foregroundColor(Color.primary)
                }
                .padding(10)
            }

            if !aliases.isEmpty {
                DisclosureGroup {
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
            }

            if !relatedTags.isEmpty {
                DisclosureGroup {
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
            }

            if !initialLoadComplete {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }

            LazyVGrid(columns: postGridColumns) {
                ForEach(Array(posts.enumerated()), id: \.element) { i, post in
                    PostPreviewFrame(post: post, search: tagName)
                    .onAppear {
                        if i == posts.count - 18 {
                            Task {
                                await loadMorePosts();
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .task {
            async let wikiFetch = fetchWikiPage(tagName: tagName);
            async let detailFetch = fetchTagDetail(tagName: tagName);
            async let aliasesFetch = fetchTagAliases(tagName: tagName);

            wiki = await wikiFetch;
            let detail = await detailFetch;
            tagDetail = detail;
            relatedTags = parseRelatedTags(detail?.related_tags).filter { $0 != tagName };
            aliases = await aliasesFetch;

            let allNames = relatedTags + aliases.map { $0.antecedent_name };
            if !allNames.isEmpty {
                tagCategories = await fetchTagCategories(names: allNames);
            }

            if posts.count == 0 {
                await loadPosts();
            }
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
            async let wikiFetch = fetchWikiPage(tagName: tagName);
            async let postsFetch = fetchRecentPosts(1, limit, tagName);
            wiki = await wikiFetch;
            posts = await postsFetch;
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
                    if search.count >= 3 {
                        suggestionTask?.cancel();
                        suggestionTask = Task {
                            try? await Task.sleep(for: .milliseconds(150));
                            if !Task.isCancelled {
                                searchSuggestions = await createTagList(search);
                            }
                        };
                    }
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

    func loadPosts() async {
        page = 1;
        posts = await fetchRecentPosts(page, limit, tagName);
        initialLoadComplete = true;
        prefetchThumbnails(for: posts);
    }

    func loadMorePosts() async {
        guard !isLoading else { return; }
        isLoading = true;
        page += 1;
        posts += await fetchRecentPosts(page, limit, tagName);
        isLoading = false;
        prefetchThumbnails(for: posts);
    }

}
