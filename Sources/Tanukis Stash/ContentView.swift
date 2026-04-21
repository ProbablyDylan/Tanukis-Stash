//
//  ContentView.swift
//  Tanuki
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            SearchView(search: "")
                .task {
                    // One-time migration: move legacy UserDefaults API key into the Keychain.
                    if let legacy = UserDefaults.standard.string(forKey: UDKey.apiKey),
                       !legacy.isEmpty,
                       Keychain.load(account: UDKey.apiKey) == nil {
                        Keychain.save(legacy, account: UDKey.apiKey);
                        UserDefaults.standard.removeObject(forKey: UDKey.apiKey);
                    }

                    let loginStatus = await login();
                    UserDefaults.standard.set(loginStatus, forKey: UDKey.authenticated);
                    if loginStatus {
                        if let blacklist = await fetchBlacklist() {
                            UserDefaults.standard.set(blacklist.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UDKey.userBlacklist);
                        }
                    }
                    await tagCacheSyncIfNeeded();
                }
        }
    }
}
