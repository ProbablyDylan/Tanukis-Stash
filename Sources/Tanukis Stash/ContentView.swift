//
//  ContentView.swift
//  Tanuki
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI

struct ContentView: View {
    @State private var navigateToPost: PostContent?
    @State private var navigateToPoolId: Int?
    @State private var navigateToSearch: String?
    @State private var navigateToTag: String?
    @State private var showPostView = false
    @State private var showPoolView = false
    @State private var showSearchView = false
    @State private var showTagView = false
    @State private var loadingPostId: Int?

    init() {
        Task.init {
            let loginStatus = await login();
            UserDefaults.standard.set(loginStatus, forKey: UDKey.authenticated);
            if (loginStatus) {
                UserDefaults.standard.set(await fetchBlacklist().trimmingCharacters(in: .whitespacesAndNewlines), forKey: UDKey.userBlacklist);
            }
            await tagCacheSyncIfNeeded();
        }
    }

    var body: some View {
        NavigationStack {
            SearchView(search: "")
                .navigationDestination(isPresented: $showPostView) {
                    if let post = navigateToPost {
                        PostView(post: post, search: "")
                    }
                }
                .navigationDestination(isPresented: $showPoolView) {
                    if let poolId = navigateToPoolId {
                        PoolView(poolId: poolId)
                    }
                }
                .navigationDestination(isPresented: $showSearchView) {
                    if let search = navigateToSearch {
                        SearchView(search: search)
                    }
                }
                .navigationDestination(isPresented: $showTagView) {
                    if let tag = navigateToTag {
                        TagView(tagName: tag)
                    }
                }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "tanuki" else { return .systemAction }

            switch url.host {
            case "post":
                if let idStr = url.pathComponents.last, let id = Int(idStr) {
                    loadingPostId = id
                    Task {
                        if let post = await getPost(postId: id) {
                            await MainActor.run {
                                navigateToPost = post
                                showPostView = true
                                loadingPostId = nil
                            }
                        } else {
                            await MainActor.run { loadingPostId = nil }
                        }
                    }
                }
                return .handled

            case "pool":
                if let idStr = url.pathComponents.last, let id = Int(idStr) {
                    navigateToPoolId = id
                    showPoolView = true
                }
                return .handled

            case "wiki":
                if let tag = url.pathComponents.last?.removingPercentEncoding {
                    navigateToTag = tag
                    showTagView = true
                }
                return .handled

            case "search":
                if let query = url.pathComponents.last?.removingPercentEncoding {
                    navigateToSearch = query
                    showSearchView = true
                }
                return .handled

            case "spoiler":
                // Spoiler handling is done at the DTextView level
                return .handled

            default:
                return .systemAction
            }
        })
    }
}
