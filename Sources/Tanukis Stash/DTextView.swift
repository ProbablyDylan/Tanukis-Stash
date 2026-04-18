//
//  DTextView.swift
//  Tanuki
//

import SwiftUI

struct DTextView: View {
    let text: String;
    @State private var revealedSpoilers: Set<Int> = [];
    @State private var blocks: [DTextBlock] = [];

    @State private var navigateToTag: String?;
    @State private var navigateToPost: PostContent?;
    @State private var navigateToPoolId: Int?;
    @State private var navigateToSearch: String?;
    @State private var highlightCommentId: Int?;

    @Environment(\.openURL) private var parentOpenURL;

    private let domain = UserDefaults.standard.string(forKey: UDKey.apiSource) ?? "e926.net";

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                DTextBlockView(block: block, revealedSpoilers: $revealedSpoilers, domain: domain)
            }
        }
        .onAppear { parseIfNeeded(); }
        .onChange(of: text) { parseIfNeeded(); }
        .navigationDestination(item: $navigateToTag) { tag in
            TagView(tagName: tag)
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
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "tanuki" else {
                parentOpenURL(url);
                return .handled;
            }

            switch url.host {
            case "wiki":
                if let tag = url.pathComponents.last?.removingPercentEncoding {
                    navigateToTag = tag;
                }
                return .handled;

            case "search":
                if let query = url.pathComponents.last?.removingPercentEncoding {
                    navigateToSearch = query;
                }
                return .handled;

            case "post":
                if let idStr = url.pathComponents.last, let id = Int(idStr) {
                    Task {
                        if let post = await getPost(postId: id) {
                            await MainActor.run { navigateToPost = post; }
                        }
                    }
                }
                return .handled;

            case "pool":
                if let idStr = url.pathComponents.last, let id = Int(idStr) {
                    navigateToPoolId = id;
                }
                return .handled;

            case "comment":
                if let idStr = url.pathComponents.last, let id = Int(idStr) {
                    Task {
                        if let comment = await getComment(commentId: id) {
                            if let post = await getPost(postId: comment.post_id) {
                                await MainActor.run {
                                    highlightCommentId = id;
                                    navigateToPost = post;
                                }
                            }
                        }
                    }
                }
                return .handled;

            case "spoiler":
                return .handled;

            default:
                parentOpenURL(url);
                return .handled;
            }
        })
    }

    private func parseIfNeeded() {
        var parser = DTextParser();
        revealedSpoilers = [];
        blocks = parser.parse(text);
    }
}
