import SwiftUI
import os.log

// Applies a change to the post with `postId` wherever the host keeps it.
// Actions are asynchronous, so they address posts by id: by the time a vote
// returns the pager may be on a different page.
typealias PostMutator = @MainActor (_ postId: Int, _ change: (inout PostContent) -> Void) -> Void;

// Bottom-bar actions (favorite, vote, save/share) for one post. Shared by
// PostView and the CollectionViewer; icon state reads straight from `post`.
// `center` is an optional item between the actions and the share menu (the
// viewer's page selector); PostView passes none.
@MainActor
struct PostActionsToolbar<Center: View>: ViewModifier {
    let post: PostContent?;
    // PostView disables voting until it has re-fetched the post's current vote.
    var votingEnabled: Bool = true;
    let mutate: PostMutator;
    let hasCenter: Bool;
    let center: Center;

    // Not @AppStorage: on iOS 27 an @AppStorage inside a view reachable from a
    // grid cell's NavigationLink destination hangs the render loop. Seeded from
    // UserDefaults and refreshed in onAppear.
    @State private var authenticated: Bool = UserDefaults.standard.bool(forKey: UDKey.authenticated);
    @State private var displayToastType: MediaActionState = .idle;
    @State private var shareItems: [Any] = [];
    @State private var showShareSheet = false;
    @State private var preparingShare = false;
    // Haptics fire off an explicit tick, not the post's favorite/vote state:
    // that state also changes when the pager swipes to another page.
    @State private var hapticTick = 0;
    @State private var haptic: SensoryFeedback = .selection;

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let post {
                    toolbarItems(for: post);
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(activityItems: shareItems)
            }
            .postToast(displayToastType: $displayToastType)
            .sensoryFeedback(haptic, trigger: hapticTick)
            .onAppear {
                authenticated = UserDefaults.standard.bool(forKey: UDKey.authenticated);
            }
    }

    @ToolbarContentBuilder
    private func toolbarItems(for post: PostContent) -> some ToolbarContent {
        if authenticated {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    toggleFavorite(post);
                } label: {
                    Image(systemName: post.is_favorited ? "heart.fill" : "heart")
                        .imageScale(.large)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: post.is_favorited)
                }
            }
            ToolbarSpacer(.fixed, placement: .bottomBar)
            ToolbarItemGroup(placement: .bottomBar) {
                voteButton(post, value: 1)
                voteButton(post, value: -1)
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        if hasCenter {
            ToolbarItem(placement: .bottomBar) {
                center
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
        }
        ToolbarItemGroup(placement: .bottomBar) {
            shareMenu(post)
        }
    }

    private func voteButton(_ post: PostContent, value: Int) -> some View {
        let symbol = value > 0 ? "arrowshape.up" : "arrowshape.down";
        return Button {
            castVote(post, value: value);
        } label: {
            Image(systemName: post.vote == value ? "\(symbol).fill" : symbol)
                .imageScale(.large)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: post.vote)
        }
        .disabled(!votingEnabled)
    }

    private func shareMenu(_ post: PostContent) -> some View {
        Menu {
            Button {
                saveFile(post: post, showToast: $displayToastType);
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }
            Button {
                prepareAndShareContent(post: post, preparingShare: $preparingShare, shareItems: $shareItems, showShareSheet: $showShareSheet, displayToastType: $displayToastType, includeLink: true)
            } label: {
                Label("Share Link", systemImage: "link")
            }
            Button {
                prepareAndShareContent(post: post, preparingShare: $preparingShare, shareItems: $shareItems, showShareSheet: $showShareSheet, displayToastType: $displayToastType)
            } label: {
                Label("Share Content", systemImage: "photo")
            }
        } label: {
            MediaActionMenuLabel(state: displayToastType, preparingShare: preparingShare)
        }
        .disabled(displayToastType == .inProgress || preparingShare)
    }

    private func fireHaptic(_ feedback: SensoryFeedback) {
        haptic = feedback;
        hapticTick += 1;
    }

    private func toggleFavorite(_ post: PostContent) {
        let id = post.id;
        let wasFavorited = post.is_favorited;
        mutate(id) { $0.is_favorited = !wasFavorited; };
        fireHaptic(wasFavorited ? .impact(weight: .light) : .success);
        Task {
            let success = wasFavorited
                ? await unFavoritePost(postId: id)
                : await favoritePost(postId: id);
            guard success else {
                mutate(id) { $0.is_favorited = wasFavorited; };
                fireHaptic(.error);
                return;
            }
            await refreshStats(postId: id);
        }
    }

    private func castVote(_ post: PostContent, value: Int) {
        let id = post.id;
        Task {
            guard let ourScore = await votePost(postId: id, value: value, no_unvote: false) else {
                fireHaptic(.error);
                return;
            }
            mutate(id) { $0.vote = ourScore; };
            fireHaptic(ourScore == 0 ? .impact(weight: .light) : .impact(weight: .medium));
            await refreshStats(postId: id);
        }
    }

    // The vote/favorite endpoints don't reliably echo the post's new totals,
    // so ask the server for the real numbers instead of guessing a delta, then
    // record them for the grid behind us (see PostStatsSync.swift).
    private func refreshStats(postId: Int) async {
        guard let current = await getPost(postId: postId) else {
            os_log("PostActionsToolbar.refreshStats: getPost returned nil for post %{public}d", log: .default, postId);
            return;
        }
        var updated: PostContent?;
        mutate(postId) {
            $0.score = current.score;
            $0.fav_count = current.fav_count;
            updated = $0;
        };
        if let updated {
            recordPostStatsUpdate(updated);
        }
    }
}

extension View {
    func postActionsToolbar(post: PostContent?, votingEnabled: Bool = true, mutate: @escaping PostMutator) -> some View {
        modifier(PostActionsToolbar(post: post, votingEnabled: votingEnabled, mutate: mutate, hasCenter: false, center: EmptyView()))
    }

    func postActionsToolbar<Center: View>(post: PostContent?, votingEnabled: Bool = true, mutate: @escaping PostMutator, @ViewBuilder center: () -> Center) -> some View {
        modifier(PostActionsToolbar(post: post, votingEnabled: votingEnabled, mutate: mutate, hasCenter: true, center: center()))
    }
}
