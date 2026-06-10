//
//  ContentView.swift
//  Tanuki
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI

// Routes a tapped post to the detail column (sets ContentView.selectedPost).
typealias SelectPostAction = @MainActor @Sendable (PostContent) -> Void;

// Routes tag / artist taps to the master column's NavigationStack — even when
// the tap originated inside PostView in the detail column.
typealias NavigateToTagAction = @MainActor @Sendable (String) -> Void;

// Routes "Add to Current Search" style multi-term queries to master.
typealias NavigateToSearchAction = @MainActor @Sendable (String) -> Void;

private struct SelectPostKey: EnvironmentKey {
    static let defaultValue: SelectPostAction? = nil;
}

private struct NavigateToTagKey: EnvironmentKey {
    static let defaultValue: NavigateToTagAction? = nil;
}

private struct NavigateToSearchKey: EnvironmentKey {
    static let defaultValue: NavigateToSearchAction? = nil;
}

// App-level signal that the split layout is active. True only inside
// ContentView's iPad branch — independent of any column's local
// horizontalSizeClass (which can be .compact even on iPad).
private struct IsPadRegularKey: EnvironmentKey {
    static let defaultValue: Bool = false;
}

extension EnvironmentValues {
    var selectPost: SelectPostAction? {
        get { self[SelectPostKey.self] }
        set { self[SelectPostKey.self] = newValue }
    }

    var navigateToTag: NavigateToTagAction? {
        get { self[NavigateToTagKey.self] }
        set { self[NavigateToTagKey.self] = newValue }
    }

    var navigateToSearch: NavigateToSearchAction? {
        get { self[NavigateToSearchKey.self] }
        set { self[NavigateToSearchKey.self] = newValue }
    }

    var isPadRegular: Bool {
        get { self[IsPadRegularKey.self] }
        set { self[IsPadRegularKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass;
    @State private var selectedPost: PostContent? = nil;
    @State private var masterPath = NavigationPath();
    @State private var didLogin = false;

    var body: some View {
        rootView
            .task {
                guard !didLogin else { return; }
                didLogin = true;
                let loginStatus = await login();
                UserDefaults.standard.set(loginStatus, forKey: UDKey.authenticated);
                if loginStatus {
                    if let blacklist = await fetchBlacklist() {
                        UserDefaults.standard.set(blacklist.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UDKey.userBlacklist);
                    }
                }
                await tagCacheSync();
            }
    }

    @ViewBuilder
    private var rootView: some View {
        if hSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad {
            iPadRoot
                .environment(\.isPadRegular, true)
        } else {
            NavigationStack {
                SearchView(search: "")
                    .appNavigationDestinations()
            }
        }
    }

    private var iPadRoot: some View {
        NavigationSplitView {
            NavigationStack(path: $masterPath) {
                SearchView(search: "")
                    .appNavigationDestinations()
            }
        } detail: {
            NavigationStack {
                Group {
                    if let post = selectedPost {
                        PostView(post: post, search: "")
                            .id(post.id)
                    } else {
                        ContentUnavailableView(
                            "Select a post",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("Tap any post on the left to view it here.")
                        )
                    }
                }
                .appNavigationDestinations()
            }
        }
        .environment(\.selectPost) { post in
            selectedPost = post;
        }
        .environment(\.navigateToTag) { name in
            masterPath.append(TagDestination(name: name));
        }
        .environment(\.navigateToSearch) { query in
            masterPath.append(SearchDestination(query: query));
        }
    }
}
