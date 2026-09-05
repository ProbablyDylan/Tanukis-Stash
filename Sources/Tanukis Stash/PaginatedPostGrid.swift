import SwiftUI

struct PaginatedPostGrid<CellContent: View>: View {
    let posts: [PostContent];
    let allLoaded: Bool;
    let loadMore: () async -> Void;
    let cell: (Int, PostContent) -> CellContent;

    @State private var loadingMore: Bool = false;
    @State private var gridWidth: CGFloat = 0;
    @Environment(\.isPadRegular) private var isPadRegular;

    private static var endMessages: [String] {
        [
            "OwO no more posts!",
            "UwU you reached the end~",
            "That's all, furend!",
            ">w< nothing more to sniff out!",
            "End of the trail~ OwO",
            "No more treasures in this stash~",
        ]
    }

    init(
        posts: [PostContent],
        allLoaded: Bool,
        loadMore: @escaping () async -> Void,
        @ViewBuilder cell: @escaping (Int, PostContent) -> CellContent
    ) {
        self.posts = posts;
        self.allLoaded = allLoaded;
        self.loadMore = loadMore;
        self.cell = cell;
    }

    var body: some View {
        LazyVGrid(columns: postGridColumns(forWidth: gridWidth, isPadRegular: isPadRegular)) {
            ForEach(Array(posts.enumerated()), id: \.element.id) { i, post in
                cell(i, post)
                    .transition(.opacity)
                    .onAppear {
                        if i >= posts.count - 36, !loadingMore, !allLoaded {
                            loadingMore = true;
                            Task {
                                await loadMore();
                                loadingMore = false;
                            }
                        }
                    }
            }
        }
        .padding(10)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0; }

        if posts.count > 0 {
            if loadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if allLoaded {
                Text(Self.endMessages[posts.count % Self.endMessages.count])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                // Normally auto-load fires before this is reached. It's the
                // manual fallback when a page fetch failed and the user is
                // already parked at the bottom with nothing left to scroll.
                Button("Load More") {
                    loadingMore = true;
                    Task {
                        await loadMore();
                        loadingMore = false;
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            }
        }
    }
}

// Shown when the fetch succeeded but the blacklist emptied every page in the
// skip budget: the grid has no cells to trigger load-more, so offer it here.
struct BlacklistSkippedView: View {
    let loadMore: () async -> Void;

    var body: some View {
        ContentUnavailableView {
            Label("Nothing to Show Yet", systemImage: "eye.slash")
        } description: {
            Text("Every post on the pages loaded so far is blacklisted.")
        } actions: {
            Button("Load More") { Task { await loadMore(); } }
                .buttonStyle(.borderedProminent)
        }
    }
}

// Full-screen state for a first-page fetch that failed outright, as opposed
// to an empty result.
struct PostLoadFailedView: View {
    let retry: () async -> Void;

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Load Posts", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Check your connection and try again.")
        } actions: {
            Button("Retry") { Task { await retry(); } }
                .buttonStyle(.borderedProminent)
        }
    }
}

extension PaginatedPostGrid where CellContent == PostPreviewFrame {
    init(
        posts: Binding<[PostContent]>,
        search: String,
        allLoaded: Bool,
        loadMore: @escaping () async -> Void
    ) {
        self.posts = posts.wrappedValue;
        self.allLoaded = allLoaded;
        self.loadMore = loadMore;
        // Anchor the cell binding to the post id, not the index — the array can
        // shrink (refresh, cleared search) while stale cells are still live.
        self.cell = { i, post in
            PostPreviewFrame(post: Binding(
                get: {
                    if posts.wrappedValue.indices.contains(i), posts.wrappedValue[i].id == post.id {
                        return posts.wrappedValue[i];
                    }
                    return posts.wrappedValue.first(where: { $0.id == post.id }) ?? post;
                },
                set: { newValue in
                    if posts.wrappedValue.indices.contains(i), posts.wrappedValue[i].id == post.id {
                        posts.wrappedValue[i] = newValue;
                    } else if let idx = posts.wrappedValue.firstIndex(where: { $0.id == post.id }) {
                        posts.wrappedValue[idx] = newValue;
                    }
                }
            ), search: search);
        };
    }
}
