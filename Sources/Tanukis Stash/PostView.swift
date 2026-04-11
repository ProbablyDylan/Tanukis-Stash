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
    let post: PostContent;
    let search: String;
    @State var url: String = "";

    @State private var displayToastType = 0;
    @State private var favorited: Bool = false;
    @State private var our_score: Int = 2;
    @State private var score_valid: Bool = false;
    @State private var AUTHENTICATED: Bool = UserDefaults.standard.bool(forKey: UDKey.authenticated);
    @State private var descExpanded: Bool = true;
    @State private var shareItems: [Any] = [];
    @State private var showShareSheet = false;
    @State private var preparingShare = false;
    @State private var selectedArtist: String?;

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
                .padding(EdgeInsets(top: 0, leading: -10, bottom: 0, trailing: -10))
                    PostMetadataBar(post: post, selectedArtist: $selectedArtist)
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
                        CommentsView(post: post)
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    InfoView(post: post, search: search)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
                                if !success { favorited = wasFavorited; }
                            }
                        } label: {
                            Image(systemName: favorited ? "heart.fill" : "heart")
                                .imageScale(.large)
                                .symbolEffect(.bounce, value: favorited)
                        }
                    }
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            Task { our_score = await votePost(postId: post.id, value: 1, no_unvote: false) }
                        } label: {
                            Image(systemName: our_score == 1 ? "arrowshape.up.fill" : "arrowshape.up")
                                .imageScale(.large)
                                .symbolEffect(.bounce, value: our_score)
                        }
                        .disabled(!score_valid)
                        Button {
                            Task { our_score = await votePost(postId: post.id, value: -1, no_unvote: false) }
                        } label: {
                            Image(systemName: our_score == -1 ? "arrowshape.down.fill" : "arrowshape.down")
                                .imageScale(.large)
                                .symbolEffect(.bounce, value: our_score)
                        }
                        .disabled(!score_valid)
                    }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItemGroup(placement: .bottomBar) {
                    Menu {
                        Button {
                            Task { displayToastType = -1; saveFile(post: post, showToast: $displayToastType) }
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
                            prepareAndShareContent(post: post, preparingShare: $preparingShare, shareItems: $shareItems, showShareSheet: $showShareSheet, displayToastType: $displayToastType)
                        } label: {
                            Label("Share Content", systemImage: "photo")
                        }
                    } label: {
                        Image(systemName: displayToastType == 2 ? "checkmark.circle.fill" : "square.and.arrow.up")
                            .imageScale(.large)
                            .foregroundStyle(displayToastType == 2 ? Color.green : Color.primary)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.pulse, isActive: displayToastType == -1 || preparingShare)
                    }
                    .disabled(displayToastType == -1 || preparingShare)
                }
            }
            .postToast(displayToastType: $displayToastType)
            .onAppear { favorited = post.is_favorited }
            .task {
                await fetchCurrentPostLiked()
                await fetchCurrentPostVote()
            }
            .navigationDestination(item: $selectedArtist) { artist in
                TagView(tagName: artist)
            }
    }

    func calculateImageHeight(geometry: GeometryProxy) -> CGFloat {
        return CGFloat(CGFloat(post.file.height) * (CGFloat(geometry.size.width) / CGFloat(post.file.width)))
    }

    func fetchCurrentPostLiked() async {
        do {
            let url = "/posts/\(post.id).json"
            let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");
            if (data) == nil { return; }
            let parsedData = try JSONDecoder().decode(Post.self, from: data!)
            favorited = parsedData.post.is_favorited;
        } catch {
            os_log("Error fetching post liked state: %{public}s", log: .default, error.localizedDescription);
        }
    }

    func fetchCurrentPostVote() async {
        our_score = await getVote(postId: post.id);
        score_valid = [-1,0,1].contains(our_score);
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
                                NavigationLink(destination: PostView(post: child, search: search)) {
                                    RelatedPostCardContent(post: child, label: "Child")
                                }
                            }
                            if children.count > maxVisibleChildren {
                                NavigationLink(destination: SearchView(search: "parent:\(post.id)")) {
                                    overflowCard(count: children.count)
                                }
                            }
                        } else if !post.relationships.children.isEmpty || post.relationships.has_active_children {
                            NavigationLink(destination: SearchView(search: "parent:\(post.id)")) {
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
                NavigationLink(destination: PostView(post: post, search: search)) {
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
        NavigationLink(destination: PoolView(poolId: poolId, pool: pool)) {
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
            async let postFetch = fetchRecentPosts(1, 1, "pool:\(poolId) order:id");
            pool = await poolFetch;
            firstPost = await postFetch.first;
        }
    }
}

struct InfoView: View {
    let post: PostContent;
    let search: String;
    @State private var selectedTag: String?;
    @State private var selectedSearch: String?;

    var body: some View {
        VStack(alignment: .leading) {
            TagGroup(label: "Character", tags: post.tags.character, search: search, textColor: Color.green, onViewTag: { selectedTag = $0 }, onSearchTag: { selectedSearch = $0 })
            TagGroup(label: "Copyright", tags: post.tags.copyright, search: search, textColor: Color.purple, onViewTag: { selectedTag = $0 }, onSearchTag: { selectedSearch = $0 })
            TagGroup(label: "Species", tags: post.tags.species, search: search, textColor: Color.red, onViewTag: { selectedTag = $0 }, onSearchTag: { selectedSearch = $0 })
            TagGroup(label: "General", tags: post.tags.general, search: search, textColor: Color.blue, onViewTag: { selectedTag = $0 }, onSearchTag: { selectedSearch = $0 })
            TagGroup(label: "Lore", tags: post.tags.lore, search: search, textColor: Color.green, onViewTag: { selectedTag = $0 }, onSearchTag: { selectedSearch = $0 })
            TagGroup(label: "Meta", tags: post.tags.meta, search: search, textColor: Color.gray, onViewTag: { selectedTag = $0 }, onSearchTag: { selectedSearch = $0 })
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
        .navigationDestination(item: $selectedTag) { tag in
            TagView(tagName: tag)
        }
        .navigationDestination(item: $selectedSearch) { query in
            SearchView(search: query)
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
    }
}

struct CommentsView: View {
    let post: PostContent;
    @State private var comments: [CommentContent] = [];
    @State private var isLoading: Bool = false;
    @State private var isExpanded: Bool = false;
    @State private var hasFetched: Bool = false;

    var body: some View {
        VStack(alignment: .leading) {
            DisclosureGroup(isExpanded: $isExpanded) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8);
                } else if comments.isEmpty {
                    Text(hasFetched ? "No comments" : "")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading);
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(comments) { comment in
                            CommentRow(comment: comment);
                            if comment.id != comments.last?.id {
                                Divider();
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading);
                }
            } label: {
                Text("Comments (\(post.comment_count))")
                    .font(.title3)
                    .fontWeight(.heavy)
                    .foregroundColor(Color.primary);
            }
            .onChange(of: isExpanded) {
                if isExpanded && !hasFetched {
                    Task {
                        isLoading = true;
                        let result = await fetchComments(postId: post.id);
                        comments = result;
                        isLoading = false;
                        hasFetched = true;
                    }
                }
            }
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any];
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil);
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

