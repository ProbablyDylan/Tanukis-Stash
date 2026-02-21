//
//  ContentView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI
import Kingfisher

struct SearchView: View {
    @State var posts = [PostContent]();
    @State var searchSuggestions = [String]();
    @State var search: String;
    @State var page = 1;
    @State var showSettings = false;
    @State private var AUTHENTICATED: Bool = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
    @Environment(\.dismissSearch) private var dismissSearch;
    
    @State var infoText: String = ""

    var limit = 75;
    var vGridLayout = [
        GridItem(.flexible(minimum: 75)),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var loadingText = "Loading posts...";
    var noPostsFoundText = "No posts found";

    init(search: String) {
        self.search = search;
    }
    
    var body: some View {
        ScrollView(.vertical) {
            if(posts.count == 0) {
                ProgressView(infoText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LazyVGrid(columns: vGridLayout) {
                ForEach(Array(posts.enumerated()), id: \.element.id) { i, post in
                    PostPreviewFrame(post: post, search: search)
                    .onAppear {
                        if (i == posts.count - 18) {
                            Task.init {
                                await getPosts(append: true);
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .task({
            if (posts.count == 0) {
                await getPosts(append: false);
            }
        })
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Posts")
        .searchable(text: $search, prompt: "Search for tags") {
            ForEach(searchSuggestions, id: \.self) { tag in
                Button(action: {
                    updateSearch(tag);
                }) {
                    Text(tag);
                }
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Settings", systemImage: "person.crop.circle") {
                    showSettings = true;
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            if (AUTHENTICATED) {
                ToolbarItem(placement: .bottomBar) {
                    NavigationLink(destination: SearchView(search: "fav:\(UserDefaults.standard.string(forKey: "username") ?? "")")) {
                        Label("Favorites", systemImage: "heart")
                    }
                }
            }
        }
        #endif
        .sheet(isPresented: $showSettings, onDismiss: {
            AUTHENTICATED = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
        }) {
            SettingsView()
        }
        .onChange(of: search) {
            if(search.count >= 3) {
                Task.init {
                    searchSuggestions = await createTagList(search);
                }
            }
        }
        .onSubmit(of: .search) {
            posts = [];
            Task.init {
                await getPosts(append: false);
                searchSuggestions.removeAll();
                dismissSearch()
            }
        }
        .refreshable {
            page = 1;
            posts = await fetchRecentPosts(page, limit, search)
        }
    }
    
    func getPosts(append: Bool) async {
        infoText = loadingText;
        let newPosts: [PostContent];
        if(append) {
            page += 1;
            newPosts = await fetchRecentPosts(page, limit, search);
            posts += newPosts;
        } else {
            page = 1;
            newPosts = await fetchRecentPosts(page, limit, search);
            posts = newPosts;
        }

        if (posts.count == 0) {
            infoText = noPostsFoundText
        }

        let prefetchURLs = newPosts.compactMap { URL(string: $0.preview.url ?? "") };
        ImagePrefetcher(urls: prefetchURLs).start();
    }
    
    func updateSearch(_ tag: String) {
        if(search.contains(" ")) {
            let index = search.lastIndex(of: " ");
            if(index != nil) {
                search = String(search[...index!].trimmingCharacters(in: .whitespaces) + " " + tag);
            }
        }
        else { search = tag; }
    }
    
}

class SearchableViewModel: ObservableObject {
    var dismissClosure: () -> Void = { print("Not Set") }
}

struct SearchableViewPassthrough: ViewModifier {
    @Environment(\.isSearching) var isSearching
    @Environment(\.dismissSearch) var dismissSearch
    let viewModel: SearchableViewModel

    func body(content: Content) -> some View {
        content
        .onAppear {
            viewModel.dismissClosure = { dismissSearch() }
        }
    }
}

struct PostPreviewFrame: View {
    let post: PostContent;
    let search: String;
    
    var body: some View {
        
        NavigationLink(destination: PostView(post: post, search: search)) {
            ZStack {
                if(post.preview.url != nil) {
                    KFImage(URL(string: post.preview.url!))
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
                }
                else {
                    Text("Deleted")
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: 150)
                        .background(Color.gray.opacity(0.90))
                }
                VStack() {
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
            }.cornerRadius(10)
            .padding(0.1)
        }
    }
}
