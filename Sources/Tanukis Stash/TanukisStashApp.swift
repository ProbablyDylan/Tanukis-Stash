//
//  TanukisStashApp.swift
//  Tanuki
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI
import AVFoundation
import os.log

@main
struct TanukisStashApp: App {
    init() {
        ImageCacheConfig.apply();
        ImageCacheConfig.cleanExpired();
        configureAudioSession();
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback);
        } catch {
            os_log("%{public}s", log: .default, "Failed to configure audio session: \(String(describing: error))");
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
