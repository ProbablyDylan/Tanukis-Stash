import SwiftUI
import Kingfisher

struct PostGridCell: View {
    let post: PostContent;

    var body: some View {
        ZStack {
            if let urlStr = post.preview.url {
                KFImage(URL(string: urlStr))
                    .placeholder {
                        ProgressView()
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
            VStack {
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "arrowshape.up.fill")
                    Text(post.score.total.formatted(.number.notation(.compactName)))
                    Image(systemName: "heart.fill")
                        .padding(.leading, 1)
                    Text(post.fav_count.formatted(.number.notation(.compactName)))
                    Image(systemName: "bubble.fill")
                        .padding(.leading, 1)
                    Text(post.comment_count.formatted(.number.notation(.compactName)))
                }
                .font(.system(size: 10))
                .fontWeight(.bold)
                .foregroundColor(Color.white)
                .frame(maxWidth: .infinity)
                .padding(5.0)
                .background(Color.gray.opacity(0.50))
            }
        }
        .cornerRadius(10)
        .padding(0.1)
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
