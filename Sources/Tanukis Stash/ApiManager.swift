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
    let API_KEY = Keychain.load(account: UDKey.apiKey) ?? "";
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

func isPostBlacklisted(_ post: PostContent, blacklistedArray: [String]) -> Bool {
    let tagSet = Set(
        (post.tags.general + post.tags.species + post.tags.character +
         post.tags.copyright + post.tags.artist + post.tags.invalid +
         post.tags.lore + post.tags.meta).map { $0.lowercased() }
    );

    for rawLine in blacklistedArray {
        // Strip inline comments (space then #)
        let line: String;
        if let commentRange = rawLine.range(of: " #") {
            line = String(rawLine[rawLine.startIndex..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces);
        } else {
            line = rawLine;
        }
        // Skip comment-only lines
        if line.isEmpty || line.hasPrefix("#") { continue; }

        let rawTokens = line.split(separator: " ").map { String($0) }.filter { !$0.isEmpty };
        if rawTokens.isEmpty { continue; }

        // Parse tokens into required and optional groups
        var required: [(value: String, negated: Bool)] = [];
        var optional: [(value: String, negated: Bool)] = [];

        for raw in rawTokens {
            var t = raw;
            let isOptional = t.hasPrefix("~");
            if isOptional { t = String(t.dropFirst()); }
            let isNegated = t.hasPrefix("-");
            if isNegated { t = String(t.dropFirst()); }
            if t.isEmpty { continue; }

            if isOptional {
                optional.append((t, isNegated));
            } else {
                required.append((t, isNegated));
            }
        }

        // All required tokens must match (AND logic)
        var allMatch = true;
        for req in required {
            let matches = blacklistTokenMatchesPost(req.value, post: post, tagSet: tagSet);
            if req.negated ? matches : !matches {
                allMatch = false;
                break;
            }
        }
        if !allMatch { continue; }

        // At least one optional token must match (OR logic), if any exist
        if !optional.isEmpty {
            var anyMatch = false;
            for opt in optional {
                let matches = blacklistTokenMatchesPost(opt.value, post: post, tagSet: tagSet);
                if opt.negated ? !matches : matches {
                    anyMatch = true;
                    break;
                }
            }
            if !anyMatch { continue; }
        }

        os_log("Post %{public}d blacklisted by: %{public}s", log: .default, post.id, line);
        return true;
    }
    return false;
}

private func blacklistTokenMatchesPost(_ token: String, post: PostContent, tagSet: Set<String>) -> Bool {
    // Metatag handling
    if let colonIdx = token.firstIndex(of: ":") {
        let prefix = String(token[token.startIndex..<colonIdx]);
        let value = String(token[token.index(after: colonIdx)...]);

        switch prefix.lowercased() {
        case "rating":
            let normalized: String;
            switch value {
            case "s", "safe": normalized = "s";
            case "q", "questionable": normalized = "q";
            case "e", "explicit": normalized = "e";
            default: normalized = value;
            }
            return post.rating == normalized;
        case "type":
            return post.file.ext.lowercased() == value;
        case "score":
            return blacklistCompareValue(post.score.total, against: value);
        case "id":
            return blacklistCompareValue(post.id, against: value);
        case "width":
            return blacklistCompareValue(post.file.width, against: value);
        case "height":
            return blacklistCompareValue(post.file.height, against: value);
        case "favcount":
            return blacklistCompareValue(post.fav_count, against: value);
        case "tagcount":
            let total = post.tags.general.count + post.tags.species.count +
                post.tags.character.count + post.tags.copyright.count +
                post.tags.artist.count + post.tags.invalid.count +
                post.tags.lore.count + post.tags.meta.count;
            return blacklistCompareValue(total, against: value);
        case "status":
            switch value {
            case "pending": return post.flags.pending;
            case "flagged": return post.flags.flagged;
            case "deleted": return post.flags.deleted;
            default: return false;
            }
        default:
            // Unknown metatag prefix — fall through to tag matching
            return tagSet.contains(token);
        }
    }

    // Wildcard matching
    if token.contains("*") {
        let pattern = "^" + NSRegularExpression.escapedPattern(for: token)
            .replacingOccurrences(of: "\\*", with: ".*") + "$";
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false; }
        for tag in tagSet {
            if regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) != nil {
                return true;
            }
        }
        return false;
    }

    // Plain tag
    return tagSet.contains(token);
}

private func blacklistCompareValue(_ actual: Int, against spec: String) -> Bool {
    // Range: "10..50"
    if let dotRange = spec.range(of: "..") {
        let low = Int(spec[spec.startIndex..<dotRange.lowerBound]);
        let high = Int(spec[dotRange.upperBound...]);
        if let lo = low, let hi = high { return actual >= lo && actual <= hi; }
        return false;
    }
    if spec.hasPrefix(">=") || spec.hasPrefix("=>") {
        if let v = Int(spec.dropFirst(2)) { return actual >= v; }
    } else if spec.hasPrefix("<=") || spec.hasPrefix("=<") {
        if let v = Int(spec.dropFirst(2)) { return actual <= v; }
    } else if spec.hasPrefix(">") {
        if let v = Int(spec.dropFirst(1)) { return actual > v; }
    } else if spec.hasPrefix("<") {
        if let v = Int(spec.dropFirst(1)) { return actual < v; }
    } else if let v = Int(spec) {
        return actual == v;
    }
    return false;
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
    // Normalize newlines to CRLF to match HTML form submission behavior
    let normalized = tags
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .replacingOccurrences(of: "\n", with: "\r\n");
    // Strict form-encoding charset per HTML5 spec
    var formChars = CharacterSet.alphanumerics;
    formChars.insert(charactersIn: "*-._");
    let encoded = normalized.addingPercentEncoding(withAllowedCharacters: formChars) ?? "";
    let body = "user[blacklisted_tags]=\(encoded)".data(using: .utf8);
    let data = await makeRequest(destination: url, method: "PATCH", body: body, contentType: "application/x-www-form-urlencoded");
    if data == nil { return false; }
    return true;
}

func fetchTags(_ text: String) async -> [TagSuggestion] {
    do {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? text;
        let url: String = "/tags/autocomplete.json?search%5Bname_matches%5D=\(encoded)&expiry=7";

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
    guard let index = searchText.lastIndex(of: " ") else { return searchText; }
    return String(searchText[index...]).trimmingCharacters(in: .whitespacesAndNewlines);
}

@MainActor func debouncedTagSuggestion(
    query: String,
    task: inout Task<Void, Never>?,
    results: Binding<[TagSuggestion]>
) {
    task?.cancel();
    let lastWord = parseSearch(query);
    guard lastWord.count >= 3 else {
        // Keep existing suggestions while typing a new word in a multi-tag query
        if !query.contains(" ") {
            results.wrappedValue = [];
        }
        return;
    }
    task = Task {
        try? await Task.sleep(for: .milliseconds(150));
        guard !Task.isCancelled else { return; }
        let suggestions = await createTagList(query);
        guard !Task.isCancelled else { return; }
        results.wrappedValue = suggestions;
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

func getComment(commentId: Int) async -> CommentContent? {
    return await fetchJSON("/comments/\(commentId).json", logLabel: "comment \(commentId)");
}

func fetchRecentPosts(_ page: Int, _ limit: Int, _ tags: String) async -> (posts: [PostContent], hasMore: Bool) {
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
            return ([], false);
        }

        let parsedData: Posts = try JSONDecoder().decode(Posts.self, from: data!)
        let hasMore = parsedData.posts.count >= limit;

        var filteredPosts = parsedData.posts.filter { $0.preview.url != nil };

        // If the blacklist is enabled, filter out blacklisted posts
        if (UserDefaults.standard.bool(forKey: UDKey.enableBlacklist)) {
            let blacklistedTags = UserDefaults.standard.string(forKey: UDKey.userBlacklist) ?? "";
            let blacklistedArray = blacklistedTags.lowercased().split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty };
            filteredPosts = filteredPosts.filter { !isPostBlacklisted($0, blacklistedArray: blacklistedArray) };
        }

        return (filteredPosts, hasMore);
    } catch {
        os_log("Error! %{public}@", log: .default, String(describing: error));
        return ([], false);
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
    let domain = UserDefaults.standard.string(forKey: UDKey.apiSource) ?? "e926.net";
    let API_KEY = Keychain.load(account: UDKey.apiKey) ?? "";
    let username = UserDefaults.standard.string(forKey: UDKey.username) ?? "";
    guard let url = URL(string: "https://\(domain)/posts/\(postId)") else { return 0; }
    var request = URLRequest(url: url);
    request.addValue(userAgent, forHTTPHeaderField: "User-Agent");
    if !API_KEY.isEmpty && !username.isEmpty {
        let AUTH_STRING = "\(username):\(API_KEY)".data(using: .utf8)?.base64EncodedString() ?? "";
        request.addValue("Basic \(AUTH_STRING)", forHTTPHeaderField: "Authorization");
    }
    do {
        let (data, _) = try await URLSession.shared.data(for: request);
        let html = String(data: data, encoding: .utf8) ?? "";
        if html.contains("post-vote-up-\(postId) score-positive") { return 1; }
        if html.contains("post-vote-down-\(postId) score-negative") { return -1; }
        return 0;
    } catch {
        os_log("getVote failed: %{public}s", log: .default, error.localizedDescription);
        return 0;
    }
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
    case 8: return .green;
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
    let API_KEY = Keychain.load(account: UDKey.apiKey) ?? "";
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
