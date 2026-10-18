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

// One blacklist line, compiled once per fetch. Tokenizing and building wildcard
// regexes per post would repeat that work for every post on every page.
struct BlacklistRule {

    fileprivate enum Metric { case score, id, width, height, favCount, tagCount }

    fileprivate enum Matcher {
        case tag(String)
        case wildcard(NSRegularExpression?)
        case rating(String)
        case fileType(String)
        case metric(Metric, String)
        case status(String)
    }

    fileprivate struct Term {
        let negated: Bool;
        let matcher: Matcher;
    }

    let line: String;
    fileprivate let required: [Term];
    fileprivate let optional: [Term];

    // Returns nil for blank and comment-only lines, and for lines with nothing
    // left after stripping `~` / `-` (which would otherwise match every post).
    init?(_ rawLine: String) {
        // Strip inline comments (space then #)
        var text = rawLine;
        if let commentRange = rawLine.range(of: " #") {
            text = String(rawLine[rawLine.startIndex..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces);
        }
        if text.isEmpty || text.hasPrefix("#") { return nil; }

        var required: [Term] = [];
        var optional: [Term] = [];
        for raw in text.split(separator: " ") {
            var t = String(raw);
            let isOptional = t.hasPrefix("~");
            if isOptional { t = String(t.dropFirst()); }
            let isNegated = t.hasPrefix("-");
            if isNegated { t = String(t.dropFirst()); }
            if t.isEmpty { continue; }

            let term = Term(negated: isNegated, matcher: BlacklistRule.matcher(for: t));
            if isOptional { optional.append(term); } else { required.append(term); }
        }
        if required.isEmpty && optional.isEmpty { return nil; }
        self.line = text;
        self.required = required;
        self.optional = optional;
    }

    private static func matcher(for token: String) -> Matcher {
        if let colonIdx = token.firstIndex(of: ":") {
            let prefix = String(token[token.startIndex..<colonIdx]);
            let value = String(token[token.index(after: colonIdx)...]);
            switch prefix.lowercased() {
            case "rating":
                switch value {
                case "s", "safe": return .rating("s");
                case "q", "questionable": return .rating("q");
                case "e", "explicit": return .rating("e");
                default: return .rating(value);
                }
            case "type": return .fileType(value);
            case "score": return .metric(.score, value);
            case "id": return .metric(.id, value);
            case "width": return .metric(.width, value);
            case "height": return .metric(.height, value);
            case "favcount": return .metric(.favCount, value);
            case "tagcount": return .metric(.tagCount, value);
            case "status": return .status(value);
            default:
                // Unknown metatag prefix: treat the whole token as a tag
                return .tag(token);
            }
        }
        if token.contains("*") {
            let pattern = "^" + NSRegularExpression.escapedPattern(for: token)
                .replacingOccurrences(of: "\\*", with: ".*") + "$";
            return .wildcard(try? NSRegularExpression(pattern: pattern));
        }
        return .tag(token);
    }

    fileprivate func matches(_ post: PostContent, tagSet: Set<String>) -> Bool {
        // Every required term must hold (AND); with optional terms, at least one must too (OR)
        for term in required where !term.isSatisfied(by: post, tagSet: tagSet) { return false; }
        if optional.isEmpty { return true; }
        return optional.contains { $0.isSatisfied(by: post, tagSet: tagSet) };
    }
}

private extension BlacklistRule.Term {

    func isSatisfied(by post: PostContent, tagSet: Set<String>) -> Bool {
        matcher.matches(post, tagSet: tagSet) != negated;
    }
}

private extension BlacklistRule.Matcher {

    func matches(_ post: PostContent, tagSet: Set<String>) -> Bool {
        switch self {
        case .tag(let name):
            return tagSet.contains(name);
        case .wildcard(let regex):
            guard let regex else { return false; }
            return tagSet.contains { tag in
                regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) != nil;
            };
        case .rating(let rating):
            return post.rating == rating;
        case .fileType(let ext):
            return post.file.ext.lowercased() == ext;
        case .metric(let metric, let spec):
            let actual: Int;
            switch metric {
            case .score: actual = post.score.total;
            case .id: actual = post.id;
            case .width: actual = post.file.width;
            case .height: actual = post.file.height;
            case .favCount: actual = post.fav_count;
            case .tagCount: actual = tagSet.count;
            }
            return blacklistCompareValue(actual, against: spec);
        case .status(let value):
            switch value {
            case "pending": return post.flags.pending;
            case "flagged": return post.flags.flagged;
            case "deleted": return post.flags.deleted;
            default: return false;
            }
        }
    }
}

func compileBlacklist(_ lines: [String]) -> [BlacklistRule] {
    lines.compactMap { BlacklistRule($0) };
}

func isPostBlacklisted(_ post: PostContent, rules: [BlacklistRule]) -> Bool {
    if rules.isEmpty { return false; }
    let tagSet = Set(post.tags.all.map { $0.lowercased() });
    guard let hit = rules.first(where: { $0.matches(post, tagSet: tagSet) }) else { return false; }
    os_log("Post %{public}d blacklisted by: %{public}s", log: .default, post.id, hit.line);
    return true;
}

// "10..50", "..10", "10..", ">=5", "<0", "7"
private func blacklistCompareValue(_ actual: Int, against spec: String) -> Bool {
    if let dotRange = spec.range(of: "..") {
        let low = Int(spec[spec.startIndex..<dotRange.lowerBound]);
        let high = Int(spec[dotRange.upperBound...]);
        if low == nil && high == nil { return false; }
        return actual >= (low ?? Int.min) && actual <= (high ?? Int.max);
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

// `urlQueryAllowed` leaves `+`, `&`, `=`, `;` and `#` alone, and Rails reads a
// bare `+` as a space — so tags containing any of those need them escaped.
private let queryComponentAllowed: CharacterSet = {
    var set = CharacterSet.urlQueryAllowed;
    set.remove(charactersIn: "+&=;#");
    return set;
}();

// One path segment. `urlPathAllowed` leaves `/` alone, which would split a tag
// like `male/male` into two segments.
private let pathSegmentAllowed: CharacterSet = {
    var set = CharacterSet.urlPathAllowed;
    set.remove(charactersIn: "/");
    return set;
}();

func pathSegment(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? value;
}

// Builds `?a=b&c=d` with every key and value percent-encoded. Pass an ordered
// list so the query is stable for logging.
func queryString(_ items: KeyValuePairs<String, String>) -> String {
    let pairs = items.map { key, value in
        let k = key.addingPercentEncoding(withAllowedCharacters: queryComponentAllowed) ?? key;
        let v = value.addingPercentEncoding(withAllowedCharacters: queryComponentAllowed) ?? value;
        return "\(k)=\(v)";
    };
    return pairs.isEmpty ? "" : "?" + pairs.joined(separator: "&");
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
    let url = "/tags/autocomplete.json" + queryString(["search[name_matches]": text, "expiry": "7"]);
    let tags: [TagContent]? = await fetchJSON(url, logLabel: "tag autocomplete");
    return (tags ?? []).map { TagSuggestion(name: $0.name, category: $0.category, postCount: $0.post_count) };
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

private let kTagPoolWidth = 200;
private let kTagDisplayLimit = 10;

@MainActor
private struct TagSuggestionPool {
    let prefix: String;
    let pool: [CachedTag];
    let isExhaustive: Bool; // true when SQLite returned fewer rows than asked for
}

@MainActor private var tagSuggestionPool: TagSuggestionPool?;

@MainActor func debouncedTagSuggestion(
    query: String,
    task: inout Task<Void, Never>?,
    results: Binding<[TagSuggestion]>
) {
    task?.cancel();
    let lastWord = parseSearch(query).lowercased();
    guard lastWord.count >= 1 else {
        results.wrappedValue = [];
        return;
    }

    // Fast path: when the new query extends a previous query whose cached pool
    // captured every match (didn't hit kTagPoolWidth), narrowing in memory is
    // provably equivalent to re-querying. Skip SQLite entirely.
    if let cache = tagSuggestionPool,
       cache.isExhaustive,
       lastWord.hasPrefix(cache.prefix) {
        let filtered = cache.pool.filter { $0.name.hasPrefix(lastWord) };
        let top = Array(filtered.prefix(kTagDisplayLimit));
        results.wrappedValue = top.map {
            TagSuggestion(name: $0.name, category: $0.category, postCount: $0.postCount)
        };
        return;
    }

    // Slow path: hit SQLite for a wider pool than we display, off the main
    // thread, so future narrowing keystrokes can use the fast path.
    task = Task {
        let prefix = lastWord;
        let pool = await Task.detached(priority: .userInitiated) {
            searchLocalTags(prefix, limit: kTagPoolWidth)
        }.value;
        if Task.isCancelled { return; }
        tagSuggestionPool = TagSuggestionPool(
            prefix: prefix,
            pool: pool,
            isExhaustive: pool.count < kTagPoolWidth
        );
        let top = Array(pool.prefix(kTagDisplayLimit));
        results.wrappedValue = top.map {
            TagSuggestion(name: $0.name, category: $0.category, postCount: $0.postCount)
        };
    };
}

// Post endpoints are requested in the v2 response format; `extended` keeps tags
// grouped by category, which the tag lists and the artist bar rely on.
let postApiFormat = "v2=true&mode=extended";

func getPost(postId: Int) async -> PostContent? {
    return await fetchJSON("/posts/\(postId).json?\(postApiFormat)", logLabel: "post \(postId)");
}

func fetchPool(poolId: Int) async -> PoolContent? {
    return await fetchJSON("/pools/\(poolId).json", logLabel: "pool \(poolId)");
}

let commentPageSize = 75;

// One page of visible comments, oldest first. `hasMore` is true when the
// server returned a full page, so the caller can ask for `page + 1`.
func fetchComments(postId: Int, page: Int = 1) async -> (comments: [CommentContent], hasMore: Bool, failed: Bool) {
    let url = "/comments.json" + queryString([
        "group_by": "comment",
        "search[post_id]": String(postId),
        "search[order]": "id_asc",
        "limit": String(commentPageSize),
        "page": String(page),
    ]);
    guard let all: [CommentContent] = await fetchJSON(url, logLabel: "comments for post \(postId) page \(page)") else {
        return ([], false, true);
    }
    let visible = all.filter { !$0.is_hidden }.sorted { $0.created_at < $1.created_at };
    return (visible, all.count >= commentPageSize, false);
}

func getComment(commentId: Int) async -> CommentContent? {
    return await fetchJSON("/comments/\(commentId).json", logLabel: "comment \(commentId)");
}

struct PostFetchResult {
    var posts: [PostContent];
    // True when the server returned a full page, so `page + 1` may have more.
    var hasMore: Bool;
    // The last page actually fetched — can exceed the requested page when the
    // blacklist emptied intermediate pages. Callers should resume from here.
    var page: Int;
    // Network or decode failure, as opposed to a genuinely empty result.
    var failed: Bool;

    static func failure(page: Int) -> PostFetchResult {
        return PostFetchResult(posts: [], hasMore: false, page: page, failed: true);
    }
}

// The e621 favorites listing is a separate endpoint; `fav:<me>` is routed
// there so the grid gets favorite order rather than post-id order.
private func postListingPath(tags: String, page: Int, limit: Int) -> String {
    let username = UserDefaults.standard.string(forKey: UDKey.username) ?? "";
    let query: String;
    if tags == "fav:\(username)" {
        query = queryString(["limit": String(limit), "page": String(page)]);
        return "/favorites.json" + query + "&" + postApiFormat;
    }
    query = queryString(["tags": tags, "limit": String(limit), "page": String(page)]);
    return "/posts.json" + query + "&" + postApiFormat;
}

private func currentBlacklistRules() -> [BlacklistRule] {
    guard UserDefaults.standard.bool(forKey: UDKey.enableBlacklist) else { return []; }
    let raw = UserDefaults.standard.string(forKey: UDKey.userBlacklist) ?? "";
    let lines = raw.lowercased()
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty };
    return compileBlacklist(lines);
}

private func fetchPostPage(_ page: Int, _ limit: Int, _ tags: String, blacklist: [BlacklistRule]) async -> PostFetchResult {
    let url = postListingPath(tags: tags, page: page, limit: limit);
    guard let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json") else {
        return .failure(page: page);
    }
    do {
        let parsed = try JSONDecoder().decode([PostContent].self, from: data);
        var posts = parsed.filter { $0.preview.url != nil };
        if !blacklist.isEmpty {
            posts = posts.filter { !isPostBlacklisted($0, rules: blacklist) };
        }
        return PostFetchResult(posts: posts, hasMore: parsed.count >= limit, page: page, failed: false);
    } catch {
        os_log("Error decoding posts: %{public}@", log: .default, String(describing: error));
        return .failure(page: page);
    }
}

// Pages that the blacklist empties completely would leave the grid with no
// cell to trigger load-more, so keep walking forward (bounded) until a page
// yields something or the listing ends.
private let maxEmptyPagesToSkip = 4;

// Pass `skipEmptyPages: false` for one-shot lookups (a single thumbnail) where
// walking forward would be wasted requests. When the skip budget runs out the
// result is `posts: []` with `hasMore: true`; callers must offer a way to
// continue from `result.page + 1` rather than treat it as the end.
//
// `ignoringBlacklist` skips the client-side blacklist (collections keep every
// page; see showsBlacklistedInCollections()).
func fetchRecentPosts(_ page: Int, _ limit: Int, _ tags: String, skipEmptyPages: Bool = true, ignoringBlacklist: Bool = false) async -> PostFetchResult {
    let blacklist = ignoringBlacklist ? [] : currentBlacklistRules();
    var current = page;
    var skipped = 0;
    while true {
        let result = await fetchPostPage(current, limit, tags, blacklist: blacklist);
        if result.failed || !result.posts.isEmpty || !result.hasMore || !skipEmptyPages || skipped >= maxEmptyPagesToSkip {
            return result;
        }
        if Task.isCancelled { return result; }
        skipped += 1;
        current += 1;
        os_log("Page %{public}d fully blacklisted, trying page %{public}d", log: .default, current - 1, current);
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


// Returns the user's resulting vote (-1, 0, 1), or nil when the request
// failed so callers can leave their displayed vote untouched. The endpoint
// doesn't reliably echo the post's new total score, so callers that need the
// fresh total re-fetch the post via getPost rather than guess a delta.
func votePost(postId: Int, value: Int, no_unvote: Bool) async -> Int? {
    let url = "/posts/\(postId)/votes.json"
    guard let data = await makeRequest(destination: url, method: "POST", body: "score=\(value)&no_unvote=\(no_unvote)".data(using: .utf8), contentType: "application/x-www-form-urlencoded") else {
        return nil;
    }
    do {
        let json = try JSONDecoder().decode(VoteResponse.self, from: data);
        return json.our_score ?? 0;
    } catch {
        os_log("Error decoding vote response: %{public}@", log: .default, String(describing: error));
        return nil;
    }
}

func fetchWikiPage(tagName: String) async -> WikiPage? {
    return await fetchJSON("/wiki_pages/\(pathSegment(tagName)).json", logLabel: "wiki page for \(tagName)");
}

func fetchTagDetail(tagName: String) async -> TagDetail? {
    let url = "/tags.json" + queryString(["search[name_matches]": tagName]);
    let tags: [TagDetail]? = await fetchJSON(url, logLabel: "tag detail for \(tagName)");
    return tags?.first;
}

func fetchTagAliases(tagName: String) async -> [TagAlias] {
    let url = "/tag_aliases.json" + queryString(["search[consequent_name]": tagName, "search[status]": "active"]);
    let aliases: [TagAlias]? = await fetchJSON(url, logLabel: "tag aliases for \(tagName)");
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
    let url = "/tags.json" + queryString(["search[name]": names.joined(separator: ","), "limit": String(names.count)]);
    let tags: [TagDetail]? = await fetchJSON(url, logLabel: "tag categories");
    var map = [String: Int]();
    for tag in tags ?? [] { map[tag.name] = tag.category; }
    return map;
}

func prefetchThumbnails(for posts: [PostContent]) {
    let urls = posts.compactMap { URL(string: $0.preview.url ?? "") };
    ImagePrefetcher(urls: urls).start();
}

func makeRequest(destination: String, method: String, body: Data?, contentType: String) async -> Data? {
    let domain = apiDomain();
    let API_KEY = UserDefaults.standard.string(forKey: UDKey.apiKey) ?? "";
    let username = UserDefaults.standard.string(forKey: UDKey.username) ?? "";
    let AUTH_STRING: String = "\(username):\(API_KEY)".data(using: .utf8)?.base64EncodedString() ?? "";
    guard let url = URL(string: "https://\(domain)\(destination)") else {
        os_log("makeRequest: invalid URL for destination %{public}s", log: .default, destination);
        return nil;
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 30;
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
