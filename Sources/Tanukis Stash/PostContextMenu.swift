import SwiftUI
import os.log

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
                            guard success else { post.is_favorited = wasFavorited; return; }
                            await refreshStats();
                            if wasFavorited { onUnfavorite?(); }
                        }
                    } label: {
                        Label(
                            post.is_favorited ? "Unfavorite" : "Favorite",
                            systemImage: post.is_favorited ? "heart.slash" : "heart"
                        )
                    }
                    // Voting the same direction again removes the vote, so the
                    // label says which it will do. The result is written back so
                    // PostView opens with the vote the user just cast.
                    Button {
                        Task {
                            guard let ourScore = await votePost(postId: post.id, value: 1, no_unvote: false) else { return; }
                            post.vote = ourScore;
                            await refreshStats();
                        }
                    } label: {
                        Label(
                            post.vote == 1 ? "Remove Upvote" : "Upvote",
                            systemImage: post.vote == 1 ? "arrowshape.up.fill" : "arrowshape.up"
                        )
                    }
                    Button {
                        Task {
                            guard let ourScore = await votePost(postId: post.id, value: -1, no_unvote: false) else { return; }
                            post.vote = ourScore;
                            await refreshStats();
                        }
                    } label: {
                        Label(
                            post.vote == -1 ? "Remove Downvote" : "Downvote",
                            systemImage: post.vote == -1 ? "arrowshape.down.fill" : "arrowshape.down"
                        )
                    }
                    Divider()
                }
                Button {
                    saveFile(post: post, showToast: $displayToastType);
                } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }
                Button {
                    prepareAndShareContent(post: post, preparingShare: $preparingShare, shareItems: $shareItems, showShareSheet: $showShareSheet, displayToastType: $displayToastType, includeLink: true);
                } label: {
                    Label("Share Link", systemImage: "link")
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

    // The vote/favorite endpoints don't reliably echo the post's new totals,
    // so after a successful action ask the server for the real numbers.
    private func refreshStats() async {
        guard let current = await getPost(postId: post.id) else {
            os_log("PostContextMenu.refreshStats: getPost returned nil for post %{public}d", log: .default, post.id);
            return;
        }
        post.score = current.score;
        post.fav_count = current.fav_count;
    }
}

extension View {
    func postContextMenu(post: Binding<PostContent>, onUnfavorite: (() -> Void)? = nil) -> some View {
        self.modifier(PostContextMenu(post: post, onUnfavorite: onUnfavorite))
    }
}
