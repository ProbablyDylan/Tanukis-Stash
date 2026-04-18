import SwiftUI
import AVKit

struct VideoPlayerController: UIViewControllerRepresentable {
    var videoURL: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let enableAirplay = UserDefaults.standard.bool(forKey: UDKey.enableAirplay);
        let player = AVPlayer(url: videoURL);
        player.allowsExternalPlayback = enableAirplay;
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
        let enableAirplay = UserDefaults.standard.bool(forKey: UDKey.enableAirplay);
        uiViewController.player?.allowsExternalPlayback = enableAirplay;
    }
}
