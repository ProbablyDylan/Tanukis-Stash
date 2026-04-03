//
//  TagManager.swift
//  Tanuki
//
//  Created by Jemma Poffinbarger on 7/15/22.
//

import Foundation
import SwiftUI
import Kingfisher
import os.log

let userAgent: String = "Tanukis Stash/1.0.0 (by ProbablyOllie on e621)";
let log = OSLog.init(subsystem: "dev.jemsoftware.tanukistash", category: "main")

// Thanks Stackoverflow: https://stackoverflow.com/a/45624666
extension URLResponse {

    func getStatusCode() -> Int? {
        if let httpResponse = self as? HTTPURLResponse {
            return httpResponse.statusCode
        }
        return nil
    }
}

func login() async -> Bool {
    let username = UserDefaults.standard.string(forKey: UDKey.username) ?? "";
    let API_KEY = UserDefaults.standard.string(forKey: UDKey.apiKey) ?? "";
    if username.isEmpty || API_KEY.isEmpty {
        return false;
    }
    let userData = await fetchUserData();
    if userData == nil {
        os_log("Login failed for %{public}s", log: .default, username);
        return false;
    }
    os_log("Login successful for %{public}s", log: .default, username);
    return true;
}

func areTagsBlacklisted(blacklistedArray: [String], postTags: [String]) -> Bool {
    let postTagsSet = Set(postTags.map { $0.lowercased() });
    for tag in blacklistedArray {
         // Each line in the blacklist can contain multiple tags separated by spaces, if post contains all of them, it is blacklisted
        let blacklistLineTags = tag.split(separator: " ").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let blacklistLineTagsSet = Set(blacklistLineTags)
        // Check if the post tags contain all the blacklisted tags in this line
        if blacklistLineTagsSet.isSubset(of: postTagsSet) {
            os_log("Post is blacklisted due to tags: %{public}s", log: .default, tag);
            return true;
        }
    }
    return false

}

func isPostBlacklisted(_ post: PostContent, blacklistedArray: [String]) -> Bool {
    var allPostTags = post.tags.general

    allPostTags.append(contentsOf: post.tags.species)
    allPostTags.append(contentsOf: post.tags.character)
    allPostTags.append(contentsOf: post.tags.copyright)
    allPostTags.append(contentsOf: post.tags.artist)
    allPostTags.append(contentsOf: post.tags.invalid)
    allPostTags.append(contentsOf: post.tags.lore)
    allPostTags.append(contentsOf: post.tags.meta)

    // Get post rating and convert it to a tag
    switch post.rating {
        case "s":
            allPostTags.append("rating:safe")
        case "q":
            allPostTags.append("rating:questionable")
        case "e":
            allPostTags.append("rating:explicit")
        default:
            os_log("Unknown rating %{public}s for post %{public}d", log: .default, post.rating, post.id);
    }

    return areTagsBlacklisted(blacklistedArray: blacklistedArray, postTags: allPostTags)
}

func fetchJSON<T: Decodable>(_ endpoint: String, logLabel: String) async -> T? {
    do {
        guard let data = await makeRequest(destination: endpoint, method: "GET", body: nil, contentType: "application/json") else { return nil; }
        return try JSONDecoder().decode(T.self, from: data);
    } catch {
        os_log("Error fetching %{public}s: %{public}s", log: .default, logLabel, error.localizedDescription);
        return nil;
    }
}

func fetchUserData() async -> UserData? {
    let username = UserDefaults.standard.string(forKey: UDKey.username) ?? "";
    return await fetchJSON("/users/\(username).json", logLabel: "user data");
}

func fetchBlacklist() async -> String? {
    let authenticated = UserDefaults.standard.bool(forKey: UDKey.authenticated);
    if !authenticated {
        os_log("Not authenticated, skipping blacklist update", log: .default);
        return nil;
    }
    let userdata = await fetchUserData();
    guard let userdata = userdata else {
        os_log("Failed to fetch user data", log: .default);
        return nil;
    }
    return userdata.blacklisted_tags ?? "";
}

func updateBlacklist(tags: String) async -> Bool {
    guard let userData = await fetchUserData() else { return false; }
    let url = "/users/\(userData.id).json";
    var formSafeChars = CharacterSet.urlQueryAllowed;
    formSafeChars.remove(charactersIn: "&+=");
    let encoded = tags.addingPercentEncoding(withAllowedCharacters: formSafeChars) ?? "";
    let body = "user[blacklisted_tags]=\(encoded)".data(using: .utf8);
    let data = await makeRequest(destination: url, method: "PATCH", body: body, contentType: "application/x-www-form-urlencoded");
    if data == nil { return false; }
    return true;
}

func fetchTags(_ text: String) async -> [TagSuggestion] {
    do {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? text;
        let url: String = "/tags/autocomplete.json?search%5Bname_matches%5D=\(encoded)&expiry=7&_client=\(userAgent)";

        let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");
        if (data) == nil { return []; }
        let tags: [TagContent] = try JSONDecoder().decode([TagContent].self, from: data!)
        return tags.map { TagSuggestion(name: $0.name, category: $0.category) };
    } catch {
        return [];
    }
}

func isSingleTagQuery(_ query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines);
    if trimmed.isEmpty { return false; }
    if trimmed.contains(" ") { return false; }
    if trimmed.hasPrefix("-") || trimmed.hasPrefix("~") { return false; }
    if trimmed.contains(":") { return false; }
    if trimmed.contains("*") { return false; }
    return true;
}

func replaceLastSearchWord(in search: String, with tag: String) -> String {
    if search.contains(" "), let index = search.lastIndex(of: " ") {
        return search[...index].trimmingCharacters(in: .whitespaces) + " " + tag;
    }
    return tag;
}

func parseSearch(_ searchText: String) -> String {
    if(searchText.contains(" ")) {
        let index = searchText.lastIndex(of: " ");
        if(index != nil) {
            return String(searchText[index!...]).trimmingCharacters(in: .whitespacesAndNewlines);
        }
        else {return "";}
    }
    else { return searchText; }
}

@MainActor func debouncedTagSuggestion(
    query: String,
    task: inout Task<Void, Never>?,
    results: Binding<[TagSuggestion]>
) {
    task?.cancel();
    guard query.count >= 3 else {
        results.wrappedValue = [];
        return;
    }
    task = Task {
        try? await Task.sleep(for: .milliseconds(150));
        if !Task.isCancelled {
            results.wrappedValue = await createTagList(query);
        }
    };
}

func createTagList(_ search: String) async -> [TagSuggestion] {
    let newSearchText = parseSearch(search);
    if(newSearchText.count >= 3) {
        let cached = searchLocalTags(newSearchText);
        if !cached.isEmpty {
            return cached.map { TagSuggestion(name: $0.name, category: $0.category) };
        }
        return await fetchTags(newSearchText);
    }
    return []
}

func getPost(postId: Int) async -> PostContent? {
    let post: Post? = await fetchJSON("/posts/\(postId).json", logLabel: "post \(postId)");
    return post?.post;
}

func fetchPool(poolId: Int) async -> PoolContent? {
    return await fetchJSON("/pools/\(poolId).json", logLabel: "pool \(poolId)");
}

func fetchComments(postId: Int) async -> [CommentContent] {
    let comments: [CommentContent]? = await fetchJSON(
        "/comments.json?group_by=comment&search%5Bpost_id%5D=\(postId)&limit=75",
        logLabel: "comments for post \(postId)"
    );
    return (comments ?? []).filter { !$0.is_hidden }.sorted { $0.created_at < $1.created_at };
}

func fetchRecentPosts(_ page: Int, _ limit: Int, _ tags: String) async -> [PostContent] {
    do {
        let username = UserDefaults.standard.string(forKey: UDKey.username) ?? "";
        let encoded = tags.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        let url: String;

        if (tags == "fav:\(username)") {
            url = "/favorites.json?limit=\(limit)&page=\(page)"
        } else {
            url = "/posts.json?tags=\(encoded ?? "")&limit=\(limit)&page=\(page)"
        }

        let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");

        if (data) == nil { 
            os_log("Failed to fetch posts", log: .default);
            return []; 
        }

        let parsedData: Posts = try JSONDecoder().decode(Posts.self, from: data!)

        var filteredPosts = parsedData.posts.filter { $0.preview.url != nil };

        // If the blacklist is enabled, filter out blacklisted posts
        if (UserDefaults.standard.bool(forKey: UDKey.enableBlacklist)) {
            let blacklistedTags = UserDefaults.standard.string(forKey: UDKey.userBlacklist) ?? "";
            guard blacklistedTags != "No Auth" && blacklistedTags != "Bad usrdata" else {
                return filteredPosts;
            }
            let blacklistedArray = blacklistedTags.lowercased().split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) };
            filteredPosts = filteredPosts.filter { !isPostBlacklisted($0, blacklistedArray: blacklistedArray) };
        }

        return filteredPosts;
    } catch {
        os_log("Error! %{public}@", log: .default, String(describing: error));
        return [];
    }
}

func favoritePost(postId: Int) async -> Bool {
    let url = "/favorites.json";
    let body = "post_id=\(postId)".data(using: .utf8);
    let data = await makeRequest(destination: url, method: "POST", body: body, contentType: "application/x-www-form-urlencoded");
    if data == nil { return false; }
    return true;
}

func unFavoritePost(postId: Int) async -> Bool {
    let url = "/favorites/\(postId).json"
    let data = await makeRequest(destination: url, method: "DELETE", body: nil, contentType: "application/json");
    if data == nil { return false; }
    return true;
}

func getVote(postId: Int) async -> Int {
    let url = "/posts/\(postId)";
    let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");
    if data == nil { return 0; }
    let textContent = String(data: data!, encoding: .utf8) ?? "";
    if textContent.contains("post-vote-up-\(postId) score-positive") {
        return 1;
    } else if textContent.contains("post-vote-down-\(postId) score-negative") {
        return -1;
    }
    return 0;
}

func votePost(postId: Int, value: Int, no_unvote: Bool) async -> Int {
    let url = "/posts/\(postId)/votes.json"
    let data = await makeRequest(destination: url, method: "POST", body: "score=\(value)&no_unvote=\(no_unvote)".data(using: .utf8), contentType: "application/x-www-form-urlencoded");
    if (data == nil) { return 0; }
    do {
        let json = try JSONDecoder().decode(VoteResponse.self, from: data!);
        return json.our_score ?? 0
    }
    catch {
        return 0
    }
}

func fetchWikiPage(tagName: String) async -> WikiPage? {
    let encoded = tagName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tagName;
    return await fetchJSON("/wiki_pages/\(encoded).json", logLabel: "wiki page for \(tagName)");
}

func fetchTagDetail(tagName: String) async -> TagDetail? {
    let encoded = tagName.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? tagName;
    let tags: [TagDetail]? = await fetchJSON("/tags.json?search%5Bname_matches%5D=\(encoded)", logLabel: "tag detail for \(tagName)");
    return tags?.first;
}

func fetchTagAliases(tagName: String) async -> [TagAlias] {
    let encoded = tagName.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? tagName;
    let aliases: [TagAlias]? = await fetchJSON(
        "/tag_aliases.json?search%5Bconsequent_name%5D=\(encoded)&search%5Bstatus%5D=active",
        logLabel: "tag aliases for \(tagName)"
    );
    return aliases ?? [];
}

func parseRelatedTags(_ relatedTags: String?) -> [String] {
    guard let raw = relatedTags, !raw.isEmpty else { return []; }
    let parts = raw.split(separator: " ");
    var names = [String]();
    for (i, part) in parts.enumerated() {
        if i % 2 == 0 {
            names.append(String(part));
        }
    }
    return names;
}

func tagCategoryColor(_ category: Int) -> Color {
    switch category {
    case 1: return .orange;
    case 3: return .purple;
    case 4: return .green;
    case 5: return .red;
    default: return .blue;
    }
}

func fetchTagCategories(names: [String]) async -> [String: Int] {
    guard !names.isEmpty else { return [:]; }
    let joined = names.joined(separator: ",");
    let encoded = joined.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? joined;
    let tags: [TagDetail]? = await fetchJSON("/tags.json?search%5Bname%5D=\(encoded)&limit=\(names.count)", logLabel: "tag categories");
    var map = [String: Int]();
    for tag in tags ?? [] { map[tag.name] = tag.category; }
    return map;
}

func prefetchThumbnails(for posts: [PostContent]) {
    let urls = posts.compactMap { URL(string: $0.preview.url ?? "") };
    ImagePrefetcher(urls: urls).start();
}

func makeRequest(destination: String, method: String, body: Data?, contentType: String) async -> Data? {
    let domain = UserDefaults.standard.string(forKey: UDKey.apiSource) ?? "e926.net";
    let API_KEY = UserDefaults.standard.string(forKey: UDKey.apiKey) ?? "";
    let username = UserDefaults.standard.string(forKey: UDKey.username) ?? "";
    let AUTH_STRING: String = "\(username):\(API_KEY)".data(using: .utf8)?.base64EncodedString() ?? "";
    guard let url = URL(string: "https://\(domain)\(destination)") else {
        os_log("makeRequest: invalid URL for destination %{public}s", log: .default, destination);
        return nil;
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.addValue(contentType, forHTTPHeaderField: "Content-Type")
    request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

    if ![API_KEY, username].contains("") {
        request.addValue("Basic \(AUTH_STRING)", forHTTPHeaderField: "Authorization")
    }

    do {
        if (body != nil && method != "GET") {
            request.httpBody = body!
        }
        let (data, response) = try await URLSession.shared.data(for: request);

        let statusCode = response.getStatusCode() ?? -1;
        os_log("HTTP %{public}s %{public}d https://%{public}s%{public}s", log: .default, method, statusCode, domain, destination);
        guard (200..<300).contains(statusCode) else {
            os_log("HTTP error %{public}d for %{public}s", log: .default, statusCode, destination);
            return nil;
        }
        return data;
    } catch {
        os_log("Failed to make request: %{public}s", log: .default, error.localizedDescription);
        return nil;
    }
}
