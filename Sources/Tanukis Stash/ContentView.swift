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
    @State private var loadingPostId: Int?
    @State private var loadingCommentId: Int?
    @State private var highlightCommentId: Int?

    var body: some View {
        NavigationStack {
            SearchView(search: "")
                .task {
                    let loginStatus = await login();
                    UserDefaults.standard.set(loginStatus, forKey: UDKey.authenticated);
                    if loginStatus {
                        if let blacklist = await fetchBlacklist() {
                            UserDefaults.standard.set(blacklist.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UDKey.userBlacklist);
                        }
                    }
                    await tagCacheSyncIfNeeded();
                }
                .navigationDestination(item: $navigateToPost) { post in
                    PostView(post: post, search: "", highlightCommentId: highlightCommentId)
                        .onDisappear { highlightCommentId = nil; }
                }
                .navigationDestination(item: $navigateToPoolId) { poolId in
                    PoolView(poolId: poolId)
                }
                .navigationDestination(item: $navigateToSearch) { search in
                    SearchView(search: search)
                }
                .navigationDestination(item: $navigateToTag) { tag in
                    TagView(tagName: tag)
                }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "tanuki" else { return .systemAction }

            switch url.host {
            case "post":
                if let idStr = url.pathComponents.last, let id = Int(idStr) {
                    loadingPostId = id;
                    Task {
                        if let post = await getPost(postId: id) {
                            await MainActor.run {
                                navigateToPost = post;
                                loadingPostId = nil;
                            }
                        } else {
                            await MainActor.run { loadingPostId = nil; }
                        }
                    }
                }
                return .handled

            case "pool":
                if let idStr = url.pathComponents.last, let id = Int(idStr) {
                    navigateToPoolId = id;
                }
                return .handled

            case "wiki":
                if let tag = url.pathComponents.last?.removingPercentEncoding {
                    navigateToTag = tag;
                }
                return .handled

            case "search":
                if let query = url.pathComponents.last?.removingPercentEncoding {
                    navigateToSearch = query;
                }
                return .handled

            case "comment":
                if let idStr = url.pathComponents.last, let id = Int(idStr) {
                    loadingCommentId = id;
                    Task {
                        if let comment = await getComment(commentId: id) {
                            if let post = await getPost(postId: comment.post_id) {
                                await MainActor.run {
                                    highlightCommentId = id;
                                    navigateToPost = post;
                                    loadingCommentId = nil;
                                }
                            } else {
                                await MainActor.run { loadingCommentId = nil; }
                            }
                        } else {
                            await MainActor.run { loadingCommentId = nil; }
                        }
                    }
                }
                return .handled

            case "spoiler":
                return .handled

            default:
                return .systemAction
            }
        })
    }
}
