import SwiftUI
import AVKit
 
struct VideoPlayerController: UIViewControllerRepresentable {
    @State private var ENABLE_AIRPLAY = UserDefaults.standard.bool(forKey: "ENABLE_AIRPLAY");
    var videoURL: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default);
        try? AVAudioSession.sharedInstance().setActive(true);

        let player = AVPlayer(url: videoURL)
        player.allowsExternalPlayback = ENABLE_AIRPLAY;
        let playerViewController = AVPlayerViewController();

        playerViewController.player = player;

        return playerViewController;
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player?.pause();
        uiViewController.player = nil;
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation);
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {

    }
}
 