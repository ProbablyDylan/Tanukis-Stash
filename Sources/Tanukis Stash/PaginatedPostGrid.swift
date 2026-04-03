import SwiftUI

struct PaginatedPostGrid<CellContent: View>: View {
    let posts: [PostContent];
    let loadMore: () async -> Void;
    let cell: (Int, PostContent) -> CellContent;

    init(
        posts: [PostContent],
        loadMore: @escaping () async -> Void,
        @ViewBuilder cell: @escaping (Int, PostContent) -> CellContent
    ) {
        self.posts = posts;
        self.loadMore = loadMore;
        self.cell = cell;
    }

    var body: some View {
        LazyVGrid(columns: postGridColumns) {
            ForEach(Array(posts.enumerated()), id: \.element.id) { i, post in
                cell(i, post)
                    .onAppear {
                        if i >= posts.count - 18 {
                            Task { await loadMore(); }
                        }
                    }
            }
        }
        .scrollTargetLayout()
        .padding(10)
    }
}

extension PaginatedPostGrid where CellContent == PostPreviewFrame {
    init(
        posts: [PostContent],
        search: String,
        loadMore: @escaping () async -> Void
    ) {
        self.posts = posts;
        self.loadMore = loadMore;
        self.cell = { _, post in PostPreviewFrame(post: post, search: search) };
    }
}
