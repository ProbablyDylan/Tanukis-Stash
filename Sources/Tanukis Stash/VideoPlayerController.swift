import SwiftUI
import AVKit

struct VideoPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController();
        vc.player = player;
        vc.allowsPictureInPicturePlayback = true;
        vc.canStartPictureInPictureAutomaticallyFromInline = true;
        player.allowsExternalPlayback = UserDefaults.standard.bool(forKey: UDKey.enableAirplay);
        return vc;
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        player.allowsExternalPlayback = UserDefaults.standard.bool(forKey: UDKey.enableAirplay);
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player?.pause();
        uiViewController.player = nil;
    }
}
