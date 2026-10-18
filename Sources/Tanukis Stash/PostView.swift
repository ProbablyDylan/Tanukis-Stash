//
//  PostView.swift
//  Tanuki
//
//  Created by Jemma Poffinbarger on 1/4/22.
//

import SwiftUI
import Kingfisher
import os.log

@MainActor
struct PostView: View {
    // @State (not `let`) so a vote or favorite writes straight back into the
    // score/fav_count PostMetadataBar reads.
    @State private var post: PostContent;
    let search: String;
    var highlightCommentId: Int? = nil;
    // The toolbar's vote buttons stay disabled until the post's current vote
    // has been re-fetched (the post handed to us may be stale).
    @State private var score_valid: Bool = false;

    init(post: PostContent, search: String, highlightCommentId: Int? = nil) {
        _post = State(initialValue: post);
        self.search = search;
        self.highlightCommentId = highlightCommentId;
    }

    // Overlays any stats a vote/favorite already recorded for this post. This
    // matters beyond the current @State: if this PostView was itself reached
    // from another PostView (e.g. a related/child post), its own copy has no
    // path back to that other view's array — see PostStatsSync.swift.
    private var displayPost: PostContent {
        pendingPostStatsUpdate(for: post.id) ?? post;
    }

    var body: some View {
        ScrollView(.vertical) {
            PostDetailContent(post: displayPost, search: search, highlightCommentId: highlightCommentId)
        }
        .navigationBarTitle("Post", displayMode: .inline)
        // `post`, not `displayPost`: the toolbar icons must reflect an action
        // the instant it lands, before its stats are recorded.
        .postActionsToolbar(post: post, votingEnabled: score_valid, mutate: mutatePost)
        .task {
            await fetchCurrentPostState();
        }
    }

    private func mutatePost(_ postId: Int, _ change: (inout PostContent) -> Void) {
        guard post.id == postId else { return; }
        change(&post);
    }

    // The post handed to this view may have been fetched a while ago, so the
    // favorite and vote state are refreshed from a single request.
    func fetchCurrentPostState() async {
        guard let current = await getPost(postId: post.id) else { return; }
        post = current;
        score_valid = true;
    }

}

struct InfoView: View {
    let post: PostContent;
    let search: String;
    @Environment(\.navigateToTag) private var navigateToTag;
    @Environment(\.navigateToSearch) private var navigateToSearch;
    @Environment(\.pushDestination) private var pushDestination;

    private func handleViewTag(_ tag: String) {
        if let navigateToTag {
            navigateToTag(tag);
        } else {
            pushDestination?(TagDestination(name: tag));
        }
    }

    private func handleSearchTag(_ query: String) {
        if let navigateToSearch {
            navigateToSearch(query);
        } else {
            pushDestination?(SearchDestination(query: query));
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            TagGroup(label: "Character", tags: post.tags.character, search: search, textColor: Color.green, onViewTag: handleViewTag, onSearchTag: handleSearchTag)
            TagGroup(label: "Copyright", tags: post.tags.copyright, search: search, textColor: Color.purple, onViewTag: handleViewTag, onSearchTag: handleSearchTag)
            TagGroup(label: "Species", tags: post.tags.species, search: search, textColor: Color.red, onViewTag: handleViewTag, onSearchTag: handleSearchTag)
            TagGroup(label: "General", tags: post.tags.general, search: search, textColor: Color.blue, onViewTag: handleViewTag, onSearchTag: handleSearchTag)
            TagGroup(label: "Lore", tags: post.tags.lore, search: search, textColor: Color.green, onViewTag: handleViewTag, onSearchTag: handleSearchTag)
            TagGroup(label: "Meta", tags: post.tags.meta, search: search, textColor: Color.gray, onViewTag: handleViewTag, onSearchTag: handleSearchTag)
            if (!post.sources.isEmpty) {
                DisclosureGroup {
                    VStack(alignment: .leading) {
                        ForEach(post.sources, id: \.self) { tag in
                            Text(.init(tag))
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } label: {
                    Text("Sources")
                        .font(.title3)
                        .fontWeight(.heavy)
                        .foregroundColor(Color.primary)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer()
        }
    }
}


struct TagGroup: View {
    let label: String;
    let tags: [String];
    let search: String;
    let textColor: Color;
    let onViewTag: (String) -> Void;
    let onSearchTag: (String) -> Void;

    var body: some View {
        if tags.isEmpty {

        } else {
            DisclosureGroup {
                VStack(alignment: .leading) {
                    ForEach(tags, id: \.self) { tag in
                        Tag(tag: tag, search: search, textColor: textColor, onViewTag: onViewTag, onSearchTag: onSearchTag)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } label: {
                Text(label)
                    .font(.title3)
                    .fontWeight(.heavy)
                    .foregroundColor(Color.primary)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

struct Tag: View {
    let tag: String
    let search: String
    let textColor: Color;
    let onViewTag: (String) -> Void;
    let onSearchTag: (String) -> Void;

    var body: some View {
        Menu {
            Button {
                onViewTag(tag);
            } label: {
                Text("View Tag")
            }
            Button {
                onSearchTag(search + " " + tag);
            } label: {
                Text("Add to Current Search")
            }
        } label: {
            Text(tag)
                .font(.body)
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
        } primaryAction: {
            onViewTag(tag);
        }
    }
}


struct CommentRow: View {
    let comment: CommentContent;
    var isHighlighted: Bool = false;
    @State private var highlightOpacity: Double = 0;

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.creator_name)
                    .font(.subheadline)
                    .fontWeight(.semibold);
                Spacer();
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up");
                    Text("\(comment.score)");
                }
                .font(.caption)
                .foregroundStyle(.secondary);
            }
            Text(comment.created_at.prefix(10))
                .font(.caption)
                .foregroundStyle(.secondary);
            DTextView(text: comment.body)
        }
        .padding(isHighlighted ? 8 : 0)
        .background(Color.accentColor.opacity(highlightOpacity))
        .clipShape(RoundedRectangle(cornerRadius: isHighlighted ? 8 : 0))
        .onAppear {
            if isHighlighted {
                highlightOpacity = 0.2;
                withAnimation(.easeOut(duration: 2.0).delay(1.0)) {
                    highlightOpacity = 0;
                }
            }
        }
    }
}

struct CommentsView: View {
    let post: PostContent;
    var highlightCommentId: Int? = nil;
    @State private var comments: [CommentContent] = [];
    @State private var isLoading: Bool = false;
    @State private var isExpanded: Bool = false;
    @State private var hasFetched: Bool = false;
    @State private var page: Int = 1;
    @State private var hasMore: Bool = false;
    @State private var loadFailed: Bool = false;

    var body: some View {
        VStack(alignment: .leading) {
            DisclosureGroup(isExpanded: $isExpanded) {
                if isLoading && comments.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8);
                } else if comments.isEmpty {
                    if loadFailed {
                        HStack {
                            Text("Couldn't load comments")
                                .foregroundStyle(.secondary);
                            Spacer();
                            Button("Retry") { Task { await loadPage(1); } }
                                .buttonStyle(.bordered);
                        }
                    } else {
                        Text(hasFetched ? "No comments" : "")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading);
                    }
                } else {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(comments) { comment in
                                CommentRow(
                                    comment: comment,
                                    isHighlighted: comment.id == highlightCommentId
                                )
                                .id(comment.id);
                                if comment.id != comments.last?.id {
                                    Divider();
                                }
                            }
                            if hasMore {
                                Divider();
                                if isLoading {
                                    ProgressView()
                                        .frame(maxWidth: .infinity, alignment: .center);
                                } else {
                                    Button(loadFailed ? "Retry" : "Load More Comments") {
                                        Task { await loadPage(page + 1); }
                                    }
                                    .buttonStyle(.bordered)
                                    .frame(maxWidth: .infinity, alignment: .center);
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .onChange(of: hasFetched) {
                            if let targetId = highlightCommentId, comments.contains(where: { $0.id == targetId }) {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(300));
                                    withAnimation {
                                        proxy.scrollTo(targetId, anchor: .center);
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                Text("Comments (\(post.comment_count))")
                    .font(.title3)
                    .fontWeight(.heavy)
                    .foregroundColor(Color.primary);
            }
            .onChange(of: isExpanded) {
                if isExpanded && !hasFetched {
                    Task { await loadPage(1); }
                }
            }
            .onAppear {
                if highlightCommentId != nil && !isExpanded {
                    isExpanded = true;
                }
            }
        }
    }

    private func loadPage(_ target: Int) async {
        guard !isLoading else { return; }
        isLoading = true;
        defer { isLoading = false; }
        let result = await fetchComments(postId: post.id, page: target);
        loadFailed = result.failed;
        // A failed page leaves `page`/`hasMore` alone so the button retries it.
        guard !result.failed else { return; }
        if target == 1 {
            comments = result.comments;
        } else {
            comments += result.comments;
        }
        page = target;
        hasMore = result.hasMore;
        hasFetched = true;
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any];
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil);
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

