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
    @State private var username: String = UserDefaults.standard.string(forKey: "username") ?? "";
    @State private var selection: String = UserDefaults.standard.string(forKey: "api_source") ?? "e926.net";
    @State private var API_KEY: String = UserDefaults.standard.string(forKey: "API_KEY") ?? "";
    @State private var ENABLE_AIRPLAY: Bool = UserDefaults.standard.bool(forKey: "ENABLE_AIRPLAY");
    @State private var ENABLE_BLACKLIST: Bool = UserDefaults.standard.bool(forKey: "ENABLE_BLACKLIST");
    @State private var AUTHENTICATED: Bool = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
    @State private var BLACKLIST: String = UserDefaults.standard.string(forKey: "USER_BLACKLIST") ?? "";
    @State private var USER_ICON: String = UserDefaults.standard.string(forKey: "USER_ICON") ?? "";
    @State private var blacklistEntries: [String] = [];
    @State private var newBlacklistTag: String = "";
    @State private var tagSuggestions: [TagSuggestion] = [];
    @State private var suggestionTask: Task<Void, Never>?;
    @State private var isSavingBlacklist: Bool = false;
    @State private var blacklistSaveSuccess: Bool? = nil;

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
                        TextField("Username", text: $username).onDisappear() {
                            UserDefaults.standard.set(username.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "username");
                        }.disabled(AUTHENTICATED).foregroundColor(AUTHENTICATED ? .gray : .primary);
                        
                        TextField("API Key", text: $API_KEY).onDisappear() {
                            UserDefaults.standard.set(API_KEY.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "API_KEY");
                        }.disabled(AUTHENTICATED).foregroundColor(AUTHENTICATED ? .gray : .primary);
                    }
                    LoginButton(AUTHENTICATED: $AUTHENTICATED, username: $username, API_KEY: $API_KEY)
                }

                if (AUTHENTICATED) {
                    Section(header: Text("Blacklist")) {
                        ForEach(Array(blacklistEntries.enumerated()), id: \.offset) { index, entry in
                            Text(entry)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        blacklistEntries.remove(at: index);
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        HStack {
                            TextField("Add tag...", text: $newBlacklistTag)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: newBlacklistTag) {
                                    suggestionTask?.cancel();
                                    if newBlacklistTag.count >= 3 {
                                        suggestionTask = Task {
                                            try? await Task.sleep(for: .milliseconds(150));
                                            if !Task.isCancelled {
                                                tagSuggestions = await createTagList(newBlacklistTag);
                                            }
                                        };
                                    } else {
                                        tagSuggestions = [];
                                    }
                                }
                                .onSubmit {
                                    addBlacklistEntry();
                                }
                            Button(action: {
                                addBlacklistEntry();
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                            .disabled(newBlacklistTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if !tagSuggestions.isEmpty {
                            ForEach(tagSuggestions, id: \.self) { tag in
                                Button(action: {
                                    newBlacklistTag = tag.name;
                                    tagSuggestions = [];
                                }) {
                                    Text(tag.name)
                                        .foregroundColor(tagCategoryColor(tag.category))
                                }
                            }
                        }
                        Button(action: {
                            isSavingBlacklist = true;
                            blacklistSaveSuccess = nil;
                            Task {
                                let tags = blacklistEntries.joined(separator: "\n");
                                let success = await updateBlacklist(tags: tags);
                                if success {
                                    BLACKLIST = tags;
                                    UserDefaults.standard.set(BLACKLIST, forKey: "USER_BLACKLIST");
                                }
                                isSavingBlacklist = false;
                                blacklistSaveSuccess = success;
                                try? await Task.sleep(nanoseconds: 2_000_000_000);
                                blacklistSaveSuccess = nil;
                            }
                        }) {
                            HStack {
                                Text("Save Blacklist")
                                Spacer()
                                if isSavingBlacklist || blacklistSaveSuccess != nil {
                                    Image(systemName: isSavingBlacklist ? "ellipsis.circle.fill" : (blacklistSaveSuccess == true ? "checkmark.circle.fill" : "xmark.circle.fill"))
                                        .symbolEffect(.pulse, isActive: isSavingBlacklist)
                                        .contentTransition(.symbolEffect(.replace))
                                        .foregroundColor(isSavingBlacklist ? .secondary : (blacklistSaveSuccess == true ? .green : .red))
                                }
                            }
                        }
                        .disabled(isSavingBlacklist)
                    }
                    .onAppear {
                        Task {
                            BLACKLIST = await fetchBlacklist();
                            UserDefaults.standard.set(BLACKLIST, forKey: "USER_BLACKLIST");
                            blacklistEntries = BLACKLIST.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty };
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
                        UserDefaults.standard.set(selection, forKey: "api_source");
                    }
                    Toggle("Enable AirPlay", isOn: $ENABLE_AIRPLAY)
                        .toggleStyle(.switch)
                        .onChange(of: ENABLE_AIRPLAY) {
                            UserDefaults.standard.set(ENABLE_AIRPLAY, forKey: "ENABLE_AIRPLAY");
                        }
                    if (AUTHENTICATED) {
                        Toggle("Enable Blacklist", isOn: $ENABLE_BLACKLIST)
                            .toggleStyle(.switch)
                            .onChange(of: ENABLE_BLACKLIST) {
                                UserDefaults.standard.set(ENABLE_BLACKLIST, forKey: "ENABLE_BLACKLIST");
                            }
                    }
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
            }
            .refreshable {
                BLACKLIST = await fetchBlacklist();
                UserDefaults.standard.set(BLACKLIST, forKey: "USER_BLACKLIST");
                blacklistEntries = BLACKLIST.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty };
            }
        }
    }

    func addBlacklistEntry() {
        let tag = newBlacklistTag.trimmingCharacters(in: .whitespacesAndNewlines);
        if !tag.isEmpty {
            blacklistEntries.append(tag);
            newBlacklistTag = "";
            tagSuggestions = [];
        }
    }

    func getUserIcon() async {
        guard let userData = await fetchUserData() else { return }
        guard let avatarPostId = userData.avatar_id else { return }
        guard let post = await getPost(postId: avatarPostId) else { return }
        if ["gif", "webm", "mp4"].contains(post.file.ext) {
            // If the avatar is a video or gif, use the preview image instead
            USER_ICON = post.preview.url!
        } else if post.file.url == nil {
            // If the file URL is nil, use the preview URL
            USER_ICON = post.preview.url!
        } else {
            // Otherwise, use the file URL
            USER_ICON = post.file.url!
        }
        UserDefaults.standard.set(USER_ICON, forKey: "USER_ICON");
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
    @State private var BLACKLIST: String = UserDefaults.standard.string(forKey: "USER_BLACKLIST") ?? "";
    
    var body: some View {
        if (AUTHENTICATED) {
            Button("Logout") {
                AUTHENTICATED = false;
                UserDefaults.standard.set(AUTHENTICATED, forKey: "AUTHENTICATED");
            }.foregroundColor(.red)
        } else {
            Button("Login") {
                Task {
                    UserDefaults.standard.set(username.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "username");
                    UserDefaults.standard.set(API_KEY.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "API_KEY");
                    AUTHENTICATED = await login();
                    UserDefaults.standard.set(AUTHENTICATED, forKey: "AUTHENTICATED");
                    if (!AUTHENTICATED) {
                        ShowAlert.toggle()
                    }
                    if (AUTHENTICATED) {
                        // Fetch user data and blacklist if login is successful
                        BLACKLIST = await fetchBlacklist();
                        UserDefaults.standard.set(BLACKLIST, forKey: "USER_BLACKLIST");
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
