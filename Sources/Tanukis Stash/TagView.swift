//
//  TagView.swift
//  Tanuki
//

import SwiftUI
import Kingfisher

struct TagView: View {
    let tagName: String;

    @State private var wiki: WikiPage?;
    @State private var tagDetail: TagDetail?;
    @State private var aliases = [TagAlias]();
    @State private var relatedTags = [String]();
    @State private var posts = [PostContent]();
    @State private var page = 1;
    @State private var isLoading: Bool = false;
    @State private var initialLoadComplete: Bool = false;
    @State private var wikiExpanded: Bool = true;

    var limit = 75;
    var vGridLayout = [
        GridItem(.flexible(minimum: 75)),
        GridItem(.flexible()),
        GridItem(.flexible())
    ];

    private var displayName: String {
        tagName.replacingOccurrences(of: "_", with: " ");
    }

    var body: some View {
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
                                    .foregroundColor(.blue)
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
                                    .foregroundColor(.blue)
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

            LazyVGrid(columns: vGridLayout) {
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
            relatedTags = parseRelatedTags(detail?.related_tags);
            aliases = await aliasesFetch;

            if posts.count == 0 {
                await loadPosts();
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(displayName)
        .refreshable {
            page = 1;
            async let wikiFetch = fetchWikiPage(tagName: tagName);
            async let postsFetch = fetchRecentPosts(1, limit, tagName);
            wiki = await wikiFetch;
            posts = await postsFetch;
            prefetchThumbnails();
        }
    }

    func loadPosts() async {
        page = 1;
        posts = await fetchRecentPosts(page, limit, tagName);
        initialLoadComplete = true;
        prefetchThumbnails();
    }

    func loadMorePosts() async {
        guard !isLoading else { return; }
        isLoading = true;
        page += 1;
        posts += await fetchRecentPosts(page, limit, tagName);
        isLoading = false;
        prefetchThumbnails();
    }

    func prefetchThumbnails() {
        let prefetchURLs = posts.compactMap { URL(string: $0.preview.url ?? "") };
        ImagePrefetcher(urls: prefetchURLs).start();
    }
}
