//
//  PostView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/4/22.
//

import SwiftUI
import AlertToast
import AttributedText

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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(post.tags.artist.joined(separator: ", "))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        HStack(spacing: 10) {
                            Text("\(post.rating.uppercased()) · #\(post.id)")
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                Text("\(post.score.total)")
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                Text("\(post.fav_count)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    RelatedPostsView(post: post, search: search)
                    InfoView(post: post, search: search)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if post.comment_count > 0 {
                        CommentsView(post: post)
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationBarTitle("Post", displayMode: .inline)
            .sheet(isPresented: $showImageViewer) {
                FullscreenImageViewer(post: post)
            }
            .toolbar {
                if AUTHENTICATED {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            Task { favorited = favorited ? await unFavoritePost(postId: post.id) : await favoritePost(postId: post.id) }
                        } label: {
                            Image(systemName: favorited ? "heart.fill" : "heart")
                                .imageScale(.large)
                        }
                    }
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            Task { our_score = await votePost(postId: post.id, value: 1, no_unvote: false) }
                        } label: {
                            Image(systemName: our_score == 1 ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                                .imageScale(.large)
                        }
                        .disabled(!score_valid)
                        Button {
                            Task { our_score = await votePost(postId: post.id, value: -1, no_unvote: false) }
                        } label: {
                            Image(systemName: our_score == -1 ? "arrowtriangle.down.fill" : "arrowtriangle.down")
                                .imageScale(.large)
                        }
                        .disabled(!score_valid)
                    }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        Task { displayToastType = -1; saveFile(post: post, showToast: $displayToastType) }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .imageScale(.large)
                    }
                    ShareLink(item: URL(string: "https://\(UserDefaults.standard.string(forKey: "api_source") ?? "e926.net")/posts/\(post.id)")!) {
                        Image(systemName: "square.and.arrow.up")
                            .imageScale(.large)
                    }
                }
            }
            .toast(isPresenting: Binding<Bool>(get: { displayToastType != 0 }, set: { _ in })) {
                getToast()
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
        case 2:
            clearToast()
            return AlertToast(type: .complete(Color.green), title: "Saved!")
        case -1:
            return AlertToast(type: .loading, title: "Saving media...")
        case 1:
            clearToast()
            return AlertToast(type: .error(Color.red), title: "Failed to save")
        default:
            clearToast()
            return AlertToast(type: .regular, title: "FUck")
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
}

struct RelatedPostsView: View {
    @State var post: PostContent;
    @State var search: String;
    @State private var parentPost: PostContent?;

    var body: some View {
        HStack {
            if((post.relationships.parent_id) != nil) {
                NavigationLink(destination: PostView(post: parentPost ?? post, search: search)) {
                    Text("Parent")
                        .foregroundColor(Color.red)
                        .font(.headline)
                }
                .task {
                    await fetchParentPostData(postID: post.relationships.parent_id!);
                }
                //Spacer()
            }
            if(post.relationships.has_active_children) {
                NavigationLink(destination: SearchView(search: "parent:" + String(post.id))) {
                    Text("Children")
                        .foregroundColor(Color.red)
                        .font(.headline)
                }
            }
            if(post.pools.count > 0) {
                //Spacer()
                NavigationLink(destination: SearchView(search: "pool:" + String(post.pools[0]))) {
                    Text("Pool")
                        .foregroundColor(Color.green)
                        .font(.headline)
                }
            }
        }
    }

    func fetchParentPostData(postID: Int) async {
        do {
            let url = "/posts/\(postID).json"
            let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");
            if (data) == nil { return; }
            let parsedData = try JSONDecoder().decode(Post.self, from: data!)
            parentPost = parsedData.post;
        } catch {
            print(error);
        }
    }
}

struct InfoView: View {
    @State var post: PostContent;
    @State var search: String;

    var body: some View {
        if (!post.description.isEmpty) {
            AttributedText(descParser(text: .init(post.description)))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        VStack(alignment: .leading) {
            TagGroup(label: "Artist", tags: post.tags.artist, search: search, textColor: Color.yellow)
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
                    .fontWeight(.heavy);
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

func descParser(text: String)-> String {
    var newText = text.replacingOccurrences(of: "[b]", with: "<b>");
    newText = newText.replacingOccurrences(of: "[/b]", with: "</b>");
    newText = newText.replacingOccurrences(of: "[u]", with: "<u>");
    newText = newText.replacingOccurrences(of: "[/u]", with: "</u>");
    newText = newText.replacingOccurrences(of: "[quote]", with: "\"");
    newText = newText.replacingOccurrences(of: "[/quote]", with: "\"");
    return newText;
}
