//
//  SettingsView.swift
//  Tanuki
//
//  Created by Jemma Poffinbarger on 1/7/22.
//

import SwiftUI
import Kingfisher

struct SettingsView: View {
    
    @Environment(\.dismiss) private var dismiss
    @State private var username: String = UserDefaults.standard.string(forKey: UDKey.username) ?? "";
    @State private var selection: String = UserDefaults.standard.string(forKey: UDKey.apiSource) ?? "e926.net";
    @State private var API_KEY: String = UserDefaults.standard.string(forKey: UDKey.apiKey) ?? "";
    @State private var ENABLE_AIRPLAY: Bool = UserDefaults.standard.bool(forKey: UDKey.enableAirplay);
    @State private var ENABLE_BLACKLIST: Bool = UserDefaults.standard.bool(forKey: UDKey.enableBlacklist);
    @AppStorage(UDKey.authenticated) private var AUTHENTICATED: Bool = false;
    @State private var USER_ICON: String = UserDefaults.standard.string(forKey: UDKey.userIcon) ?? "";
    @State private var showingBlacklistEditor: Bool = false;
    @State private var showClearCacheConfirm: Bool = false;
    @State private var isClearingCache: Bool = false;
    @State private var clearCacheSuccess: Bool? = nil;
    @State private var cacheSizeBytes: UInt = 0;
    @State private var cacheSizeLoading: Bool = true;
    @State private var sizeLimitSelection: ImageCacheSizeLimit = ImageCacheConfig.sizeLimit;
    @State private var expirationSelection: ImageCacheExpiration = ImageCacheConfig.expiration;

    let sources = ["e926.net", "e621.net"];
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Account")) {
                    if (AUTHENTICATED) {
                        HStack {
                            KFImage(URL(string: USER_ICON))
                                .placeholder {
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                }
                                .resizable()
                                .scaledToFill()
                                .clipped()
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                            Text(username.isEmpty ? "Username" : username)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                                
                        }
                    } else {
                        TextField("Username", text: $username)
                            .onChange(of: username) {
                                UserDefaults.standard.set(username.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UDKey.username);
                            }
                            .disabled(AUTHENTICATED)
                            .foregroundColor(AUTHENTICATED ? .gray : .primary);

                        TextField("API Key", text: $API_KEY)
                            .onChange(of: API_KEY) {
                                UserDefaults.standard.set(API_KEY.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UDKey.apiKey);
                            }
                            .disabled(AUTHENTICATED)
                            .foregroundColor(AUTHENTICATED ? .gray : .primary);
                    }
                    LoginButton(AUTHENTICATED: $AUTHENTICATED, username: $username, API_KEY: $API_KEY)
                }

                if (AUTHENTICATED) {
                    Section(header: Text("Blacklist")) {
                        Toggle("Enable Blacklist", isOn: $ENABLE_BLACKLIST)
                            .toggleStyle(.switch)
                            .onChange(of: ENABLE_BLACKLIST) {
                                UserDefaults.standard.set(ENABLE_BLACKLIST, forKey: UDKey.enableBlacklist);
                            }
                        if ENABLE_BLACKLIST {
                            Button(action: { showingBlacklistEditor = true; }) {
                                HStack {
                                    Text("Manage Blacklist…")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("App Settings")) {
                    Picker("API Source", selection: $selection) {
                        ForEach(sources, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selection) {
                        UserDefaults.standard.set(selection, forKey: UDKey.apiSource);
                    }
                    Toggle("Enable AirPlay", isOn: $ENABLE_AIRPLAY)
                        .toggleStyle(.switch)
                        .onChange(of: ENABLE_AIRPLAY) {
                            UserDefaults.standard.set(ENABLE_AIRPLAY, forKey: UDKey.enableAirplay);
                        }
                }

                Section(header: Text("Storage"), footer: Text("Cached images speed up browsing. Lower the cap or expiration to save space; clear to free it immediately.")) {
                    HStack {
                        Text("Cache Size")
                        Spacer()
                        if cacheSizeLoading {
                            ProgressView()
                        } else {
                            Text(ImageCacheConfig.formatBytes(cacheSizeBytes))
                                .foregroundColor(.secondary)
                        }
                    }
                    Picker("Disk Cap", selection: $sizeLimitSelection) {
                        ForEach(ImageCacheSizeLimit.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .onChange(of: sizeLimitSelection) {
                        UserDefaults.standard.set(sizeLimitSelection.rawValue, forKey: UDKey.imageCacheSizeLimit);
                        ImageCacheConfig.apply();
                    }
                    Picker("Expiration", selection: $expirationSelection) {
                        ForEach(ImageCacheExpiration.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .onChange(of: expirationSelection) {
                        UserDefaults.standard.set(expirationSelection.rawValue, forKey: UDKey.imageCacheExpirationDays);
                        ImageCacheConfig.apply();
                    }
                    Button(role: .destructive, action: {
                        showClearCacheConfirm = true;
                    }) {
                        HStack {
                            Text("Clear Image Cache")
                            Spacer()
                            if isClearingCache {
                                ProgressView()
                            } else if let success = clearCacheSuccess {
                                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(success ? .green : .red)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                    }
                    .disabled(isClearingCache || (cacheSizeBytes == 0 && !cacheSizeLoading))
                }

                Section(header: Text("App Information")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                            .foregroundColor(.secondary)
                    }
                    Link("Development Telegram", destination: URL(string: "https://t.me/+RCLG75mgaG80YWI5")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear {
                Task {
                    await getUserIcon()
                }
                Task {
                    await refreshCacheSize();
                }
            }
            .refreshable {
                if let bl = await fetchBlacklist() {
                    UserDefaults.standard.set(bl, forKey: UDKey.userBlacklist);
                }
            }
            .sheet(isPresented: $showingBlacklistEditor) {
                BlacklistEditorView()
            }
            .alert("Clear Image Cache?", isPresented: $showClearCacheConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    clearImageCache();
                }
            } message: {
                Text("This removes all cached thumbnails and images. They'll re-download as you browse.")
            }
        }
    }

    func clearImageCache() {
        withAnimation { isClearingCache = true; }
        clearCacheSuccess = nil;
        let cache = KingfisherManager.shared.cache;
        cache.clearMemoryCache();
        cache.clearDiskCache {
            Task { @MainActor in
                withAnimation {
                    isClearingCache = false;
                    clearCacheSuccess = true;
                }
                await refreshCacheSize();
                try? await Task.sleep(nanoseconds: 2_000_000_000);
                withAnimation { clearCacheSuccess = nil; }
            }
        }
    }

    func refreshCacheSize() async {
        cacheSizeLoading = true;
        let bytes = await ImageCacheConfig.currentDiskSize();
        cacheSizeBytes = bytes;
        cacheSizeLoading = false;
    }

    func getUserIcon() async {
        guard let userData = await fetchUserData() else { return; }
        guard let avatarPostId = userData.avatar_id else { return; }
        guard let post = await getPost(postId: avatarPostId) else { return; }
        let url: String;
        if let fileUrl = post.file.url, !["gif", "webm", "mp4"].contains(post.file.ext) {
            url = fileUrl;
        } else if let previewUrl = post.preview.url {
            url = previewUrl;
        } else {
            return;
        }
        USER_ICON = url;
        UserDefaults.standard.set(USER_ICON, forKey: UDKey.userIcon);
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}

struct LoginButton: View {
    @Binding var AUTHENTICATED: Bool
    @Binding var username: String
    @Binding var API_KEY: String
    @State private var ShowAlert: Bool = false;
    var body: some View {
        if (AUTHENTICATED) {
            Button("Logout") {
                AUTHENTICATED = false;
            }.foregroundColor(.red)
        } else {
            Button("Login") {
                Task {
                    UserDefaults.standard.set(username.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UDKey.username);
                    UserDefaults.standard.set(API_KEY.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UDKey.apiKey);
                    AUTHENTICATED = await login();
                    if (!AUTHENTICATED) {
                        ShowAlert.toggle()
                    }
                    if AUTHENTICATED {
                        if let bl = await fetchBlacklist() {
                            UserDefaults.standard.set(bl.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UDKey.userBlacklist);
                        }
                    }
                }
            }
            .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || API_KEY.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .alert(isPresented: $ShowAlert) {
                Alert(
                    title: Text("Login Failed"),
                    message: Text("Check your credentials and try again")
                )
            }
        }
    }
}
