//
//  PostView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/4/22.
//

import SwiftUI
import AlertToast
import AttributedText
import Kingfisher
import os.log

@MainActor
struct PostView: View {
    @State private var showImageViewer: Bool = false;
    @State var post: PostContent;
    @State var search: String;
    @State var url: String = "";

    @State private var displayToastType = 0;
    @State private var favorited: Bool = false;
    @State private var our_score: Int = 2;
    @State private var score_valid: Bool = false;
    @State private var AUTHENTICATED: Bool = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
    @State private var descExpanded: Bool = true;
    @State private var shareItems: [Any] = [];
    @State private var showShareSheet = false;
    @State private var preparingShare = false;

    private var tapGesture: some Gesture {
        !["webm", "mp4"].contains(String(post.file.ext)) ? (TapGesture().onEnded { showImageViewer = true }) : nil
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack {
                    MediaView(post: post, geometry: geometry).gesture(tapGesture)
                        .frame(
                            width: geometry.size.width,
                            height: calculateImageHeight(geometry: geometry)
                        )
                        .padding(EdgeInsets(top: 0, leading: -10, bottom: 0, trailing: -10))
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(post.rating.uppercased()) · #\(post.id)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up")
                                    Text("\(post.score.total)")
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "heart.fill")
                                    Text("\(post.fav_count)")
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "bubble.right")
                                    Text("\(post.comment_count)")
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if post.tags.artist.count == 1 {
                            NavigationLink(destination: SearchView(search: post.tags.artist[0])) {
                                HStack(spacing: 4) {
                                    Image(systemName: "paintpalette.fill")
                                    Text(post.tags.artist[0])
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        } else if post.tags.artist.count > 1 {
                            Menu {
                                ForEach(post.tags.artist, id: \.self) { artist in
                                    NavigationLink(destination: SearchView(search: artist)) {
                                        Text(artist)
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "paintpalette.fill")
                                    Text(post.tags.artist.joined(separator: ", "))
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    RelatedPostsView(post: post, search: search)
                        .padding(10)
                    if !post.description.isEmpty {
                        DisclosureGroup(isExpanded: $descExpanded) {
                            AttributedText(descParser(text: .init(post.description)))
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
                            Task { favorited = favorited ? await unFavoritePost(postId: post.id) : await favoritePost(postId: post.id) }
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
                        ShareLink(
                            item: URL(string: "https://\(UserDefaults.standard.string(forKey: "api_source") ?? "e926.net")/posts/\(post.id)")!,
                            label: { Label("Share Link", systemImage: "link") }
                        )
                        Button {
                            prepareAndShareContent()
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
            .toast(isPresenting: Binding<Bool>(get: { [1, 3, 4, 5].contains(displayToastType) }, set: { _ in })) {
                getToast()
            }
            .onChange(of: displayToastType) { _, newValue in
                if newValue == 2 { clearToast() }
            }
            .onAppear { favorited = post.is_favorited }
            .task {
                await fetchCurrentPostLiked()
                await fetchCurrentPostVote()
            }
        }
    }

    func calculateImageHeight(geometry: GeometryProxy) -> CGFloat {
        return CGFloat(CGFloat(post.file.height) * (CGFloat(geometry.size.width) / CGFloat(post.file.width)))
    }

    func clearToast() {
        // Reset the displayToastType after showing the toast
        let CurrentToastType = displayToastType
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if CurrentToastType == displayToastType {
                // Only clear the toast if the type hasn't changed
                $displayToastType.wrappedValue = 0
            }
        }
    }

    func getToast() -> AlertToast {
        switch displayToastType {
        case 1:
            clearToast()
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Failed to save")
        case 3:
            clearToast()
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Photos permission required")
        case 4:
            clearToast()
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Failed to move file")
        case 5:
            clearToast()
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "No video available")
        default:
            clearToast()
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Unknown error")
        }
    }

    func fetchCurrentPostLiked() async {
        do {
            let url = "/posts/\(post.id).json"
            let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");
            if (data) == nil { return; }
            let parsedData = try JSONDecoder().decode(Post.self, from: data!)
            favorited = parsedData.post.is_favorited;
        } catch {
            print(error);
        }
    }

    func fetchCurrentPostVote() async {
        our_score = await getVote(postId: post.id);
        score_valid = [-1,0,1].contains(our_score);
    }

    func prepareAndShareContent() {
        preparingShare = true;
        Task {
            do {
                let tempURL = try await downloadToTemp(post: post);
                await MainActor.run {
                    shareItems = [tempURL];
                    showShareSheet = true;
                    preparingShare = false;
                }
            } catch {
                os_log("%{public}s", log: .default, "prepareAndShareContent error: \(String(describing: error))");
                await MainActor.run { preparingShare = false; displayToastType = 1; }
            }
        }
    }

    func downloadToTemp(post: PostContent) async throws -> URL {
        let ext = post.file.ext;
        let downloadURL: URL;

        if ext == "webm" || ext == "mp4" {
            guard let url = getVideoLink(post: post) else { throw URLError(.fileDoesNotExist); }
            downloadURL = url;
        } else {
            guard let urlString = post.file.url, let url = URL(string: urlString) else {
                throw URLError(.badURL);
            }
            downloadURL = url;
        }

        let destExt = ext == "webm" ? "mp4" : ext;
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(post.id).\(destExt)");

        if !FileManager.default.fileExists(atPath: destURL.path) {
            let (downloadedURL, _) = try await URLSession.shared.download(from: downloadURL);
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL);
            }
            try FileManager.default.moveItem(at: downloadedURL, to: destURL);
        }
        return destURL;
    }
}

struct RelatedPostsView: View {
    @State var post: PostContent;
    @State var search: String;

    private let maxVisibleChildren = 10;

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

                        let children = post.relationships.children;
                        if !children.isEmpty {
                            ForEach(children.prefix(maxVisibleChildren), id: \.self) { childId in
                                RelatedPostCard(postId: childId, label: "Child", search: search)
                            }
                            if children.count > maxVisibleChildren {
                                NavigationLink(destination: SearchView(search: "parent:\(post.id)")) {
                                    overflowCard(count: children.count)
                                }
                            }
                        } else if post.relationships.has_active_children {
                            NavigationLink(destination: SearchView(search: "parent:\(post.id)")) {
                                overflowCard(count: nil)
                            }
                        }

                        if let poolId = post.pools.first {
                            PoolCard(poolId: poolId)
                        }
                    }
                    .padding(.horizontal, 2)
                }
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

struct RelatedPostCard: View {
    let postId: Int;
    let label: String;
    let search: String;
    @State private var fetchedPost: PostContent?;

    var body: some View {
        Group {
            if let post = fetchedPost {
                NavigationLink(destination: PostView(post: post, search: search)) {
                    cardContent(for: post)
                }
            } else {
                cardPlaceholder()
            }
        }
        .task { fetchedPost = await getPost(postId: postId); }
    }

    private func cardContent(for post: PostContent) -> some View {
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

    private func cardPlaceholder() -> some View {
        ProgressView()
            .frame(width: 80, height: 80)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
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
        NavigationLink(destination: PoolView(poolId: poolId)) {
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
            async let poolFetch = fetchPool(poolId: poolId);
            async let postFetch = fetchRecentPosts(1, 1, "pool:\(poolId) order:id");
            pool = await poolFetch;
            firstPost = await postFetch.first;
        }
    }
}

struct InfoView: View {
    @State var post: PostContent;
    @State var search: String;

    var body: some View {
        VStack(alignment: .leading) {
            TagGroup(label: "Character", tags: post.tags.character, search: search, textColor: Color.green)
            TagGroup(label: "Copyright", tags: post.tags.copyright, search: search, textColor: Color.purple)
            TagGroup(label: "Species", tags: post.tags.species, search: search, textColor: Color.red)
            TagGroup(label: "General", tags: post.tags.general, search: search, textColor: Color.blue)
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
    @State var label: String;
    @State var tags: [String];
    @State var search: String;
    @State var textColor: Color;
    
    var body: some View {
        if tags.isEmpty {
            
        } else {
            DisclosureGroup {
                VStack(alignment: .leading) {
                    ForEach(tags, id: \.self) { tag in
                        Tag(tag: tag, search: search, textColor: textColor)
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
    @State var tag: String
    @State var search: String
    @State var textColor: Color;
    @State var isActive: Bool = false
    
    var body: some View {
        Menu {
            NavigationLink(destination: SearchView(search: String(tag))) {
                Text("New Search")
            }
            NavigationLink(destination: SearchView(search: String(search + " " + tag))) {
                Text("Add to Current Search")
            }
        } label: {
            Text(tag)
                .font(.body)
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
        } primaryAction: {
            isActive.toggle()
        }
        //.background(
        //    NavigationLink(destination: SearchView(search: String(tag)), isActive: $isActive) {}
        //)
        .navigationDestination(isPresented: $isActive) {
            SearchView(search: String(tag))
        }
    }
}

struct CommentBody: View {
    let text: String;

    private struct Segment: Identifiable {
        let id: Int;
        let isQuote: Bool;
        let content: String;
    }

    private var segments: [Segment] {
        var result: [Segment] = [];
        var remaining = text;
        var idx = 0;
        while !remaining.isEmpty {
            if let openRange = remaining.range(of: "[quote]") {
                let before = String(remaining[remaining.startIndex..<openRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines);
                if !before.isEmpty {
                    result.append(Segment(id: idx, isQuote: false, content: before));
                    idx += 1;
                }
                remaining = String(remaining[openRange.upperBound...]);
                if let closeRange = remaining.range(of: "[/quote]") {
                    let quoted = String(remaining[remaining.startIndex..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines);
                    result.append(Segment(id: idx, isQuote: true, content: quoted));
                    idx += 1;
                    remaining = String(remaining[closeRange.upperBound...]);
                } else {
                    result.append(Segment(id: idx, isQuote: true, content: remaining.trimmingCharacters(in: .whitespacesAndNewlines)));
                    remaining = "";
                }
            } else {
                let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines);
                if !trimmed.isEmpty {
                    result.append(Segment(id: idx, isQuote: false, content: trimmed));
                }
                remaining = "";
            }
        }
        return result;
    }

    private func parseAttribution(_ content: String) -> (attributor: String?, body: String) {
        if let match = content.firstMatch(of: /^"([^"]+)":[^\s]+ said:\n?/) {
            return (String(match.1), String(content[match.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines));
        }
        return (nil, content);
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(segments) { segment in
                if segment.isQuote {
                    let (attributor, quoteBody) = parseAttribution(segment.content);
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 3);
                        VStack(alignment: .leading, spacing: 2) {
                            if let name = attributor {
                                Text("\(name) said:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary);
                            }
                            AttributedText(descParser(text: quoteBody))
                                .italic()
                                .foregroundStyle(.secondary)
                                .font(.body);
                        }
                    }
                    .padding(.leading, 4);
                } else {
                    AttributedText(descParser(text: segment.content))
                        .font(.body);
                }
            }
        }
    }
}

struct CommentRow: View {
    @State var comment: CommentContent;

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
            CommentBody(text: comment.body);
        }
    }
}

struct CommentsView: View {
    @State var post: PostContent;
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
                    hasFetched = true;
                    Task {
                        isLoading = true;
                        comments = await fetchComments(postId: post.id);
                        isLoading = false;
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

func descParser(text: String)-> String {
    var newText = text.replacingOccurrences(of: "[b]", with: "<b>");
    newText = newText.replacingOccurrences(of: "[/b]", with: "</b>");
    newText = newText.replacingOccurrences(of: "[u]", with: "<u>");
    newText = newText.replacingOccurrences(of: "[/u]", with: "</u>");
    newText = newText.replacingOccurrences(of: "[quote]", with: "\"");
    newText = newText.replacingOccurrences(of: "[/quote]", with: "\"");
    return newText;
}
