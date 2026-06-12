//
//  DTextView.swift
//  Tanuki
//

import SwiftUI

struct DTextView: View {
    let text: String;
    @State private var revealedSpoilers: Set<Int> = [];
    @State private var blocks: [DTextBlock] = [];

    @Environment(\.openURL) private var parentOpenURL;
    @Environment(\.pushDestination) private var pushDestination;

    private let domain = UserDefaults.standard.string(forKey: UDKey.apiSource) ?? "e926.net";

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                DTextBlockView(block: block, revealedSpoilers: $revealedSpoilers, domain: domain)
            }
        }
        .onAppear { parseIfNeeded(); }
        .onChange(of: text) { parseIfNeeded(); }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "tanuki" else {
                parentOpenURL(url);
                return .handled;
            }

            switch url.host {
            case "wiki":
                if let tag = url.pathComponents.last?.removingPercentEncoding {
                    pushDestination?(TagDestination(name: tag));
                }
                return .handled;

            case "search":
                if let query = url.pathComponents.last?.removingPercentEncoding {
                    pushDestination?(SearchDestination(query: query));
                }
                return .handled;

            case "post":
                if let idStr = url.pathComponents.last, let id = Int(idStr) {
                    Task {
                        if let post = await getPost(postId: id) {
                            await MainActor.run { pushDestination?(PostDestination(post: post, search: "")); }
                        }
                    }
                }
                return .handled;

            case "pool":
                if let idStr = url.pathComponents.last, let id = Int(idStr) {
                    pushDestination?(PoolDestination(poolId: id));
                }
                return .handled;

            case "comment":
                if let idStr = url.pathComponents.last, let id = Int(idStr) {
                    Task {
                        if let comment = await getComment(commentId: id) {
                            if let post = await getPost(postId: comment.post_id) {
                                await MainActor.run {
                                    pushDestination?(PostDestination(post: post, search: "", highlightCommentId: id));
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
