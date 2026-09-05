import SwiftUI
import Kingfisher

struct PostGridCell: View, Equatable {
    let post: PostContent;
    @Environment(\.isPadRegular) private var isPadRegular;

    // PostContent's own == compares id only (needed for ForEach/Set identity),
    // so comparing lhs.post == rhs.post here would tell .equatable() nothing
    // changed even when a vote or favorite bumped the displayed stats. Compare
    // every field this cell actually renders instead.
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
                    .shadow(color: Color.primary.opacity(0.3), radius: 1)
            } else {
                Text("Deleted")
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: 150)
                    .background(Color.gray.opacity(0.90))
            }
            statsOverlay
        }
        .cornerRadius(10)
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
            .clipped()
            .overlay { statsOverlay }
            .shadow(color: Color.primary.opacity(0.3), radius: 1)
            .cornerRadius(10)
            .padding(0.1)
    }

    private var statsOverlay: some View {
        VStack {
            Spacer()
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
            .font(.system(size: 10))
            .fontWeight(.bold)
            .foregroundColor(Color.white)
            .compositingGroup()
            .shadow(color: .black, radius: 3, x: 0, y: 1)
            .shadow(color: .black.opacity(0.7), radius: 1, x: 0, y: 0)
            .frame(maxWidth: .infinity)
            .padding(5.0)
        }
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
