import SwiftUI

// Shares one matched-geometry id per post between the pager page and the grid
// cell so the media zooms between the two layers. `isSource` is true for the
// layer currently on screen.
struct MediaMatchedGeometry {
    let namespace: Namespace.ID;
    let isSource: Bool;
}

private struct PostMediaMatchedGeometry: ViewModifier {
    let postId: Int;
    let geometry: MediaMatchedGeometry?;

    @ViewBuilder
    func body(content: Content) -> some View {
        if let geometry {
            content.matchedGeometryEffect(id: "post_\(postId)", in: geometry.namespace, isSource: geometry.isSource);
        } else {
            content;
        }
    }
}

// The post-detail stack shared by PostView and the CollectionViewer's pages.
// It does not include a ScrollView: the caller owns scrolling so a screen can
// keep its ScrollView outermost (transparent scroll-edge nav bar).
struct PostDetailContent: View {
    let post: PostContent;
    let search: String;
    var highlightCommentId: Int? = nil;
    // PostView shows parent/child/pool cards; the viewer replaces them with
    // its pager and collection switcher.
    var showsRelated: Bool = true;
    var matchedGeometry: MediaMatchedGeometry? = nil;
    // Room for an overlay (the viewer's position capsule) below the content.
    var bottomInset: CGFloat = 0;

    @State private var showImageViewer: Bool = false;
    @State private var descExpanded: Bool = true;
    @Environment(\.isPadRegular) private var isPadRegular;

    private var tapGesture: some Gesture {
        !["webm", "mp4"].contains(String(post.file.ext)) ? (TapGesture().onEnded { showImageViewer = true }) : nil
    }

    var body: some View {
        VStack {
            GeometryReader { geometry in
                MediaView(post: post)
                    .modifier(PostMediaMatchedGeometry(postId: post.id, geometry: matchedGeometry))
                    .gesture(tapGesture)
                    .frame(
                        width: geometry.size.width,
                        height: CGFloat(post.file.height) * (geometry.size.width / CGFloat(post.file.width))
                    )
            }
            .aspectRatio(CGFloat(post.file.width) / CGFloat(post.file.height), contentMode: .fit)
            PostMetadataBar(post: post)
            if showsRelated {
                RelatedPostsView(post: post, search: search)
                    .padding(10)
            }
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
            if bottomInset > 0 {
                Spacer().frame(height: bottomInset)
            }
        }
        .frame(maxWidth: isPadRegular ? 760 : .infinity)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showImageViewer) {
            FullscreenImageViewer(post: post)
        }
    }
}
