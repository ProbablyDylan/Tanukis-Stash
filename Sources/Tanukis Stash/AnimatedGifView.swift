import SwiftUI
import Kingfisher

struct AnimatedGifView: View {
    var url: URL;

    var body: some View {
        KFAnimatedImage(url)
            .placeholder {
                ProgressView()
            }
            .fade(duration: 0.25)
            .scaledToFit()
    }
}
