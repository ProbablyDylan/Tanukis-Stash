import SwiftUI
import Kingfisher

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

    var videoLink: URL? {
        return getVideoLink(post: post)
    }

    var body: some View {
        if (videoLink != nil) {
            VideoPlayerController(videoURL: videoLink!)
        }
        else {
            Text("Video failed to load")
        }
        
    }
}
