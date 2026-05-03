import SwiftUI
import AVFoundation
import Combine
import Kingfisher
import os.log

struct MediaView: View {

    let post: PostContent;

    var fileType: String {
        return String(post.file.ext)
    }

    var body: some View {
        if(post.preview.url == nil || post.file.url == nil) {
            Text("Failed to load image data!")
        }
        else if(fileType == "gif") {
            GIFView(post: post)
            .aspectRatio(contentMode: .fit)
            .background(Color.black.opacity(0.5))
        }
        else if(["webm", "mp4"].contains(fileType)) {
            VideoView(post: post)
        }
        else {
            ImageView(post: post)
            .aspectRatio(contentMode: .fit)
        }
    }

}

struct ImageView: View {

    let post: PostContent;
    @State private var fullImageLoaded = false;

    var body: some View {
        ZStack {
            if !fullImageLoaded {
                KFImage(URL(string: post.preview.url!))
                    .resizable()
                    .scaledToFit()
            }
            KFImage(URL(string: post.file.url!))
                .onSuccess { _ in fullImageLoaded = true; }
                .resizable()
                .scaledToFit()
        }
    }
}

struct GIFView: View {

    let post: PostContent;

    var body: some View {
        if let urlString = post.file.url, let url = URL(string: urlString) {
            AnimatedGifView(url: url)
        } else {
            Text("Failed to load GIF")
                .foregroundStyle(.secondary)
        }
    }
}

struct VideoView: View {

    let post: PostContent;

    @State private var player: AVPlayer?;
    @State private var status: Status = .loading;
    @State private var statusCancellable: AnyCancellable?;
    @State private var loopCancellable: AnyCancellable?;

    enum Status { case loading, ready, failed, noVariant }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)

            if let player, status == .ready {
                VideoPlayerController(player: player)
            }

            switch status {
            case .loading:
                ProgressView().tint(.white)
            case .failed:
                Text("Video failed to load").foregroundStyle(.secondary)
            case .noVariant:
                noVariantFallback
            case .ready:
                EmptyView()
            }
        }
        .onAppear { setupIfNeeded(); }
        .onDisappear { player?.pause(); }
        .onScrollVisibilityChange(threshold: 0.4) { visible in
            if !visible { player?.pause(); }
        }
    }

    private var browserURL: URL? {
        let host = UserDefaults.standard.string(forKey: UDKey.apiSource) ?? "e926.net";
        return URL(string: "https://\(host)/posts/\(post.id)");
    }

    @ViewBuilder
    private var noVariantFallback: some View {
        ZStack(alignment: .bottom) {
            if let thumb = post.sample.url ?? post.preview.url, let url = URL(string: thumb) {
                KFImage(url)
                    .resizable()
                    .scaledToFit()
            }

            VStack(spacing: 6) {
                Image(systemName: "play.slash.fill")
                    .font(.title2)
                Text("Tap to view in browser")
                    .font(.headline)
                Text("WebM is evil and not supported")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = browserURL { UIApplication.shared.open(url); }
        }
    }

    private func setupIfNeeded() {
        guard player == nil else { return; }
        guard let url = getVideoLink(post: post) else {
            status = String(post.file.ext) == "webm" ? .noVariant : .failed;
            return;
        }
        let item = AVPlayerItem(url: url);
        statusCancellable = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { itemStatus in
                switch itemStatus {
                case .readyToPlay:
                    status = .ready;
                case .failed:
                    status = .failed;
                    os_log("%{public}s", log: .default, "AVPlayerItem failed for post \(post.id): \(String(describing: item.error))");
                default:
                    break;
                }
            };
        let newPlayer = AVPlayer(playerItem: item);
        loopCancellable = NotificationCenter.default
            .publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak newPlayer] _ in
                newPlayer?.seek(to: .zero);
                newPlayer?.play();
            };
        player = newPlayer;
    }
}
