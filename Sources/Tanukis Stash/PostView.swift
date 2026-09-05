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
    @State private var showImageViewer: Bool = false;
    // @State (not `let`) so a vote or favorite writes straight back into the
    // score/fav_count PostMetadataBar reads, instead of only the local
    // favorited/our_score toggles used for the toolbar icons.
    @State private var post: PostContent;
    let search: String;
    var highlightCommentId: Int? = nil;
    @State var url: String = "";

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

    @State private var displayToastType: MediaActionState = .idle;
    @State private var favorited: Bool = false;
    @State private var our_score: Int = 2;
    @State private var score_valid: Bool = false;
    // Not @AppStorage: on iOS 27 (beta 1), @AppStorage inside a view that grid cells
    // eagerly create as a NavigationLink destination re-dirties the view graph every
    // update pass, hanging the main thread at 100% CPU on push. Plain @State seeded
    // from UserDefaults (refreshed in onAppear) avoids the loop.
    @State private var AUTHENTICATED: Bool = UserDefaults.standard.bool(forKey: UDKey.authenticated);
    @State private var descExpanded: Bool = true;
    @State private var shareItems: [Any] = [];
    @State private var showShareSheet = false;
    @State private var preparingShare = false;
    @Environment(\.isPadRegular) private var isPadRegular;

    private var tapGesture: some Gesture {
        !["webm", "mp4"].contains(String(post.file.ext)) ? (TapGesture().onEnded { showImageViewer = true }) : nil
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack {
                GeometryReader { geometry in
                    MediaView(post: post).gesture(tapGesture)
                        .frame(
                            width: geometry.size.width,
                            height: calculateImageHeight(geometry: geometry)
                        )
                }
                .aspectRatio(CGFloat(post.file.width) / CGFloat(post.file.height), contentMode: .fit)
                    PostMetadataBar(post: displayPost)
                    RelatedPostsView(post: post, search: search)
                        .padding(10)
                    if !post.description.isEmpty {
                        DisclosureGroup(isExpanded: $descExpanded) {
                            DTextView(text: post.description)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Text("Description")
                                .font(.title3)
                                .fontWeight(.heavy)
                                .foregroundColor(Color.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if post.comment_count > 0 {
                        CommentsView(post: post, highlightCommentId: highlightCommentId)
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    InfoView(post: post, search: search)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: isPadRegular ? 760 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitle("Post", displayMode: .inline)
            .sheet(isPresented: $showImageViewer) {
                FullscreenImageViewer(post: post)
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(activityItems: shareItems)
            }
            .toolbar {
                if AUTHENTICATED {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            let wasFavorited = favorited;
                            favorited = !wasFavorited;
                            Task {
                                let success = wasFavorited
                                    ? await unFavoritePost(postId: post.id)
                                    : await favoritePost(postId: post.id);
                                guard success else { favorited = wasFavorited; return; }
                                post.is_favorited = !wasFavorited;
                                await refreshPostStats();
                                recordPostStatsUpdate(post);
                            }
                        } label: {
                            Image(systemName: favorited ? "heart.fill" : "heart")
                                .imageScale(.large)
                                .contentTransition(.symbolEffect(.replace))
                                .symbolEffect(.bounce, value: favorited)
                        }
                    }
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            Task {
                                guard let ourScore = await votePost(postId: post.id, value: 1, no_unvote: false) else { return; }
                                our_score = ourScore;
                                post.vote = ourScore;
                                await refreshPostStats();
                                recordPostStatsUpdate(post);
                            }
                        } label: {
                            Image(systemName: our_score == 1 ? "arrowshape.up.fill" : "arrowshape.up")
                                .imageScale(.large)
                                .contentTransition(.symbolEffect(.replace))
                                .symbolEffect(.bounce, value: our_score)
                        }
                        .disabled(!score_valid)
                        Button {
                            Task {
                                guard let ourScore = await votePost(postId: post.id, value: -1, no_unvote: false) else { return; }
                                our_score = ourScore;
                                post.vote = ourScore;
                                await refreshPostStats();
                                recordPostStatsUpdate(post);
                            }
                        } label: {
                            Image(systemName: our_score == -1 ? "arrowshape.down.fill" : "arrowshape.down")
                                .imageScale(.large)
                                .contentTransition(.symbolEffect(.replace))
                                .symbolEffect(.bounce, value: our_score)
                        }
                        .disabled(!score_valid)
                    }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItemGroup(placement: .bottomBar) {
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
            }
            .postToast(displayToastType: $displayToastType)
            .onAppear {
                favorited = post.is_favorited;
                AUTHENTICATED = UserDefaults.standard.bool(forKey: UDKey.authenticated);
            }
            .task {
                await fetchCurrentPostState();
            }
    }

    func calculateImageHeight(geometry: GeometryProxy) -> CGFloat {
        return CGFloat(CGFloat(post.file.height) * (CGFloat(geometry.size.width) / CGFloat(post.file.width)))
    }

    // The post handed to this view may have been fetched a while ago, so the
    // favorite and vote state are refreshed from a single request.
    func fetchCurrentPostState() async {
        guard let current = await getPost(postId: post.id) else { return; }
        post = current;
        favorited = current.is_favorited;
        our_score = current.vote;
        score_valid = true;
    }

    // The vote/favorite endpoints don't reliably echo the post's new totals,
    // so after a successful action we ask the server for the real numbers
    // instead of guessing a delta client-side.
    func refreshPostStats() async {
        guard let current = await getPost(postId: post.id) else {
            os_log("refreshPostStats: getPost returned nil for post %{public}d", log: .default, post.id);
            return;
        }
        post.score = current.score;
        post.fav_count = current.fav_count;
    }

}

struct RelatedPostsView: View {
    let post: PostContent;
    let search: String;

    private let maxVisibleChildren = 10;
    @State private var activeChildren: [PostContent]?;

    private var hasRelated: Bool {
        post.relationships.parent_id != nil ||
        !post.relationships.children.isEmpty ||
        post.relationships.has_active_children ||
        !post.pools.isEmpty
    }

    var body: some View {
        if hasRelated {
            VStack(alignment: .leading, spacing: 8) {
                Text("Related")
                    .font(.title3)
                    .fontWeight(.heavy)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if let parentId = post.relationships.parent_id {
                            RelatedPostCard(postId: parentId, label: "Parent", search: search)
                        }

                        if let children = activeChildren {
                            ForEach(children.prefix(maxVisibleChildren), id: \.id) { child in
                                NavigationLink(value: PostDestination(post: child, search: search)) {
                                    RelatedPostCardContent(post: child, label: "Child")
                                }
                            }
                            if children.count > maxVisibleChildren {
                                NavigationLink(value: SearchDestination(query: "parent:\(post.id)")) {
                                    overflowCard(count: children.count)
                                }
                            }
                        } else if !post.relationships.children.isEmpty || post.relationships.has_active_children {
                            NavigationLink(value: SearchDestination(query: "parent:\(post.id)")) {
                                overflowCard(count: post.relationships.children.isEmpty ? nil : post.relationships.children.count)
                            }
                        }

                        ForEach(post.pools, id: \.self) { poolId in
                            PoolCard(poolId: poolId)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .task(id: post.id) {
                let childIds = post.relationships.children;
                guard !childIds.isEmpty else { return };
                let fetched = await withTaskGroup(of: PostContent?.self) { group in
                    for id in childIds { group.addTask { await getPost(postId: id) } }
                    var results: [PostContent] = [];
                    for await post in group { if let post, !post.flags.deleted { results.append(post) } }
                    return results;
                };
                activeChildren = fetched.sorted { childIds.firstIndex(of: $0.id) ?? 0 < childIds.firstIndex(of: $1.id) ?? 0 };
            }
        }
    }

    private func overflowCard(count: Int?) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "ellipsis")
                .font(.title2)
                .frame(width: 80, height: 80)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(count.map { "View all \($0)" } ?? "Children")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

}

struct RelatedPostCardContent: View {
    let post: PostContent;
    let label: String;

    var body: some View {
        KFImage(URL(string: post.preview.url ?? ""))
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 80, height: 80)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
    }
}

struct RelatedPostCard: View {
    let postId: Int;
    let label: String;
    let search: String;
    @State private var fetchedPost: PostContent?;

    var body: some View {
        Group {
            if let post = fetchedPost {
                NavigationLink(value: PostDestination(post: post, search: search)) {
                    RelatedPostCardContent(post: post, label: label)
                }
            } else {
                ProgressView()
                    .frame(width: 80, height: 80)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
            }
        }
        .task { fetchedPost = await getPost(postId: postId); }
    }
}

struct PoolCard: View {
    let poolId: Int;
    @State private var pool: PoolContent?;
    @State private var firstPost: PostContent?;

    private var displayName: String {
        pool?.name.replacingOccurrences(of: "_", with: " ") ?? "Pool";
    }

    var body: some View {
        NavigationLink(value: PoolDestination(poolId: poolId, pool: pool)) {
            Group {
                if let post = firstPost {
                    KFImage(URL(string: post.preview.url ?? ""))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipped()
                } else {
                    ProgressView()
                        .frame(width: 80, height: 80)
                        .background(Color.secondary.opacity(0.1))
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(displayName)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
        }
        .task {
            guard pool == nil && firstPost == nil else { return };
            async let poolFetch = fetchPool(poolId: poolId);
            async let postFetch = fetchRecentPosts(1, 1, "pool:\(poolId) order:id", skipEmptyPages: false);
            pool = await poolFetch;
            firstPost = await postFetch.posts.first;
        }
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

