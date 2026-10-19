import SwiftUI
import Kingfisher

struct PostGridCell: View, Equatable {
    let post: PostContent;
    @Environment(\.isPadRegular) private var isPadRegular;

    // PostContent's == now compares every field (see Model_Post.swift), so
    // this could just delegate to it — kept explicit and narrower since it's
    // cheaper to compare four fields than the whole struct on every cell in
    // a scrolling grid.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.post.id == rhs.post.id &&
        lhs.post.score.total == rhs.post.score.total &&
        lhs.post.fav_count == rhs.post.fav_count &&
        lhs.post.comment_count == rhs.post.comment_count;
    }

    @ViewBuilder
    var body: some View {
        if isPadRegular {
            iPadBody
        } else {
            iPhoneBody
        }
    }

    private var iPhoneBody: some View {
        ZStack {
            Group {
                if let urlStr = post.preview.url {
                    KFImage(URL(string: urlStr))
                        .placeholder {
                            DelayedSpinner()
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .frame(width: 100, height: 150)
                        }
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: 150)
                } else {
                    Text("Deleted")
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: 150)
                        .background(Color.gray.opacity(0.90))
                }
            }
            // Clip only the single image layer; clipping the whole ZStack forces an
            // offscreen mask pass per cell.
            .clipShape(Self.cellShape)
            statsOverlay
            cellEdge
        }
        .padding(0.1)
    }

    private var iPadBody: some View {
        Color.clear
            .aspectRatio(0.8, contentMode: .fit)
            .overlay {
                if let urlStr = post.preview.url {
                    KFImage(URL(string: urlStr))
                        .placeholder { DelayedSpinner() }
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.90)
                        .overlay(Text("Deleted").foregroundColor(.white))
                }
            }
            .clipShape(Self.cellShape)
            .overlay { statsOverlay }
            .overlay { cellEdge }
            .padding(0.1)
    }

    // The corner shape is shared by the clip, the scrim and the edge hairline so
    // they line up.
    private static let cornerRadius: CGFloat = 10;
    private static var cellShape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius) }

    // Hairline edge. Replaces a 1pt `.shadow`, which needs an offscreen pass per
    // cell to derive the shadow shape from the layer's alpha.
    private var cellEdge: some View {
        Self.cellShape
            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            .allowsHitTesting(false)
    }

    private var hasOverlayContent: Bool {
        post.score.total != 0 || post.fav_count != 0 || post.comment_count != 0
            || post.isInPool || post.hasFamily
    }

    private var statsOverlay: some View {
        VStack {
            Spacer()
            if hasOverlayContent {
                // Stats stay centered like every other cell; the collection marker
                // is pinned to the trailing edge of the same row.
                ZStack(alignment: .trailing) {
                    HStack(spacing: 2) {
                        if post.score.total != 0 {
                            Image(systemName: "arrowshape.up.fill")
                            Text(post.score.total.formatted(.number.notation(.compactName)))
                        }
                        if post.fav_count != 0 {
                            Image(systemName: "heart.fill")
                                .padding(.leading, 1)
                            Text(post.fav_count.formatted(.number.notation(.compactName)))
                        }
                        if post.comment_count != 0 {
                            Image(systemName: "bubble.fill")
                                .padding(.leading, 1)
                            Text(post.comment_count.formatted(.number.notation(.compactName)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    // One icon for "part of a collection" (pool or parent/children);
                    // the viewer's page selector has the details.
                    if post.isInPool || post.hasFamily {
                        Image(systemName: "rectangle.stack.fill")
                    }
                }
                .cellOverlayStyle()
                .padding(5.0)
            }
        }
        // Scrim for legibility instead of a text halo (compositingGroup + shadows
        // are several offscreen passes per cell). Filled as a shape so the bottom
        // corners follow the cell without a mask.
        .background(alignment: .bottom) {
            if hasOverlayContent {
                UnevenRoundedRectangle(bottomLeadingRadius: Self.cornerRadius, bottomTrailingRadius: Self.cornerRadius)
                    .fill(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 32)
                    .allowsHitTesting(false)
            }
        }
    }
}

private extension View {
    // White bold 10pt text; legibility comes from the scrim / capsule behind it.
    func cellOverlayStyle() -> some View {
        self
            .font(.system(size: 10))
            .fontWeight(.bold)
            .foregroundColor(Color.white)
    }
}

private struct DelayedSpinner: View {
    @State private var visible: Bool = false;

    var body: some View {
        Group {
            if visible {
                ProgressView();
            } else {
                Color.clear;
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300));
            if !Task.isCancelled { visible = true; }
        }
    }
}

struct PostContextPreview: UIViewRepresentable {

    let post: PostContent;

    private var isVideo: Bool {
        ["webm", "mp4"].contains(post.file.ext);
    }

    private var previewSize: CGSize {
        let maxW: CGFloat = 300;
        let maxH: CGFloat = 400;
        guard post.file.width > 0, post.file.height > 0 else { return CGSize(width: maxW, height: maxW); }
        let aspect = CGFloat(post.file.width) / CGFloat(post.file.height);
        let w = min(maxW, maxH * aspect);
        let h = w / aspect;
        return CGSize(width: w, height: h);
    }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView();
        imageView.contentMode = .scaleAspectFill;
        imageView.clipsToBounds = true;
        imageView.frame = CGRect(origin: .zero, size: previewSize);

        if let previewURL = post.preview.url, let url = URL(string: previewURL) {
            imageView.kf.setImage(with: url) { _ in
                let fullURLStr = isVideo ? post.sample.url : post.file.url;
                if let fullURLStr, let fullURL = URL(string: fullURLStr) {
                    KingfisherManager.shared.retrieveImage(with: fullURL) { result in
                        if case .success(let value) = result {
                            DispatchQueue.main.async {
                                imageView.image = value.image;
                            };
                        }
                    };
                }
            };
        }

        return imageView;
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        return previewSize;
    }
}
