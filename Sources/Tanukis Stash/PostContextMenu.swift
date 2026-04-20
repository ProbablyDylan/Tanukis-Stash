import SwiftUI

struct PostContextMenu: ViewModifier {

    @Binding var post: PostContent;
    var onUnfavorite: (() -> Void)? = nil;
    @State private var preparingShare = false;
    @State private var shareItems: [Any] = [];
    @State private var showShareSheet = false;
    @State private var displayToastType: MediaActionState = .idle;
    @AppStorage(UDKey.authenticated) private var AUTHENTICATED: Bool = false;

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if AUTHENTICATED {
                    Button {
                        let wasFavorited = post.is_favorited;
                        post.is_favorited = !wasFavorited;
                        Task {
                            let success = wasFavorited
                                ? await unFavoritePost(postId: post.id)
                                : await favoritePost(postId: post.id);
                            if !success { post.is_favorited = wasFavorited; return; }
                            if wasFavorited { onUnfavorite?(); }
                        }
                    } label: {
                        Label(
                            post.is_favorited ? "Unfavorite" : "Favorite",
                            systemImage: post.is_favorited ? "heart.slash" : "heart"
                        )
                    }
                    Button {
                        Task { _ = await votePost(postId: post.id, value: 1, no_unvote: false); }
                    } label: {
                        Label("Upvote", systemImage: "arrowshape.up")
                    }
                    Button {
                        Task { _ = await votePost(postId: post.id, value: -1, no_unvote: false); }
                    } label: {
                        Label("Downvote", systemImage: "arrowshape.down")
                    }
                    Divider()
                }
                Button {
                    displayToastType = .inProgress;
                    saveFile(post: post, showToast: $displayToastType);
                } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }
                if let shareURL = URL(string: "https://\(UserDefaults.standard.string(forKey: UDKey.apiSource) ?? "e926.net")/posts/\(post.id)") {
                    ShareLink(
                        item: shareURL,
                        label: { Label("Share Link", systemImage: "link") }
                    )
                }
                Button {
                    prepareAndShareContent(post: post, preparingShare: $preparingShare, shareItems: $shareItems, showShareSheet: $showShareSheet, displayToastType: $displayToastType);
                } label: {
                    Label("Share Content", systemImage: "photo")
                }
            } preview: {
                PostContextPreview(post: post)
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(activityItems: shareItems)
            }
            .postToast(displayToastType: $displayToastType)
    }
}

extension View {
    func postContextMenu(post: Binding<PostContent>, onUnfavorite: (() -> Void)? = nil) -> some View {
        self.modifier(PostContextMenu(post: post, onUnfavorite: onUnfavorite))
    }
}
