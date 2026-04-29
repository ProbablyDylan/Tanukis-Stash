//
//  TanukisStashApp.swift
//  Tanuki
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI

@main
struct TanukisStashApp: App {
    init() {
        ImageCacheConfig.apply();
        ImageCacheConfig.cleanExpired();
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
