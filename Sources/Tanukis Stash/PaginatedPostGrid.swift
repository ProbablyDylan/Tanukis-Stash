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
        .padding(10)
    }
}

extension PaginatedPostGrid where CellContent == PostPreviewFrame {
    init(
        posts: Binding<[PostContent]>,
        search: String,
        loadMore: @escaping () async -> Void
    ) {
        self.posts = posts.wrappedValue;
        self.loadMore = loadMore;
        self.cell = { i, _ in PostPreviewFrame(post: posts[i], search: search) };
    }
}
