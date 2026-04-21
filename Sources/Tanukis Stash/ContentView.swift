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
