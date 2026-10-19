//
//  SearchHistory.swift
//  Tanuki
//

import SwiftUI

// Recent and saved searches are plain string arrays in UserDefaults, newest
// first. Views hold them in @State (seeded onAppear) rather than @AppStorage:
// on iOS 27 an @AppStorage inside a view reachable from a grid cell's
// NavigationLink destination hangs the render loop.
private let searchHistoryLimit = 20;

private func normalizedSearch(_ query: String) -> String {
    query.split(whereSeparator: \.isWhitespace).joined(separator: " ");
}

private func sameSearch(_ a: String, _ b: String) -> Bool {
    a.caseInsensitiveCompare(b) == .orderedSame;
}

func loadSearchHistory() -> [String] {
    UserDefaults.standard.stringArray(forKey: UDKey.searchHistory) ?? [];
}

func loadSavedSearches() -> [String] {
    UserDefaults.standard.stringArray(forKey: UDKey.savedSearches) ?? [];
}

func isSavedSearch(_ query: String, in saved: [String]) -> Bool {
    let normalized = normalizedSearch(query);
    return saved.contains { sameSearch($0, normalized) };
}

// Moves a re-run query to the front instead of duplicating it. Returns the
// stored list.
@discardableResult
func recordSearch(_ query: String) -> [String] {
    let normalized = normalizedSearch(query);
    guard savesSearchHistory(), !normalized.isEmpty else { return loadSearchHistory(); }
    var history = loadSearchHistory().filter { !sameSearch($0, normalized) };
    history.insert(normalized, at: 0);
    history = Array(history.prefix(searchHistoryLimit));
    UserDefaults.standard.set(history, forKey: UDKey.searchHistory);
    return history;
}

func removeSearchHistory(_ query: String) -> [String] {
    let history = loadSearchHistory().filter { !sameSearch($0, query) };
    UserDefaults.standard.set(history, forKey: UDKey.searchHistory);
    return history;
}

func clearSearchHistory() -> [String] {
    UserDefaults.standard.removeObject(forKey: UDKey.searchHistory);
    return [];
}

func toggleSavedSearch(_ query: String) -> [String] {
    let normalized = normalizedSearch(query);
    guard !normalized.isEmpty else { return loadSavedSearches(); }
    var saved = loadSavedSearches();
    if saved.contains(where: { sameSearch($0, normalized) }) {
        saved.removeAll { sameSearch($0, normalized) };
    } else {
        saved.insert(normalized, at: 0);
    }
    UserDefaults.standard.set(saved, forKey: UDKey.savedSearches);
    return saved;
}

// A search term without its `-`/`~` prefix, or nil when it isn't a plain tag
// (metatags like `rating:safe`, wildcards).
func plainTagName(of term: Substring) -> String? {
    let name = term.drop { $0 == "-" || $0 == "~" };
    guard !name.isEmpty, !name.contains(":"), !name.contains("*") else { return nil; }
    return String(name).lowercased();
}

// Tag-category colored text for a query: each tag takes its category color,
// metatags go gray, anything the cache doesn't know stays primary.
func coloredQuery(_ query: String, categories: [String: Int]) -> AttributedString {
    var result = AttributedString();
    for (index, term) in query.split(whereSeparator: \.isWhitespace).enumerated() {
        if index > 0 { result += AttributedString(" "); }
        var piece = AttributedString(String(term));
        if let name = plainTagName(of: term) {
            if let category = categories[name] { piece.foregroundColor = tagCategoryColor(category); }
        } else if term.contains(":") {
            piece.foregroundColor = .gray;
        }
        result += piece;
    }
    return result;
}

// What ChipBar needs to offer the history and saved-search shelves: the
// lists plus the actions the chips and their context menus perform.
struct SearchShelf {
    let history: [String];
    let saved: [String];
    let onSelect: (String) -> Void;
    let onToggleSaved: (String) -> Void;
    let onRemoveHistory: (String) -> Void;
    let onClearHistory: () -> Void;
}

// Wires a SearchShelf to the stores, writing the results back to the view's
// state. `onSelect` runs the chosen query the way a typed submit would.
func makeSearchShelf(history: Binding<[String]>, saved: Binding<[String]>, onSelect: @escaping (String) -> Void) -> SearchShelf {
    SearchShelf(
        history: history.wrappedValue,
        saved: saved.wrappedValue,
        onSelect: onSelect,
        onToggleSaved: { query in withAnimation { saved.wrappedValue = toggleSavedSearch(query); } },
        onRemoveHistory: { query in withAnimation { history.wrappedValue = removeSearchHistory(query); } },
        onClearHistory: { withAnimation { history.wrappedValue = clearSearchHistory(); } }
    );
}
