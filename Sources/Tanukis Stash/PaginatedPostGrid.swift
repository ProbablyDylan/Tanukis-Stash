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
            }
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
