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
    guard !normalized.isEmpty else { return loadSearchHistory(); }
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

// What ChipBar needs to offer the history and saved-search shelves: the
// lists plus the actions the chips and their context menus perform.
struct SearchShelf {
    let history: [String];
    let saved: [String];
    let onSelect: (String) -> Void;
    let onToggleSaved: (String) -> Void;
    let onRemoveHistory: (String) -> Void;
    let onClearHistory: () -> Void;

    var hasItems: Bool { !history.isEmpty || !saved.isEmpty }
}

// Wires a SearchShelf to the stores, writing the results back to the view's
// state. `onSelect` runs the chosen query the way a typed submit would.
func makeSearchShelf(history: Binding<[String]>, saved: Binding<[String]>, onSelect: @escaping (String) -> Void) -> SearchShelf {
    SearchShelf(
        history: history.wrappedValue,
        saved: saved.wrappedValue,
        onSelect: onSelect,
        onToggleSaved: { saved.wrappedValue = toggleSavedSearch($0); },
        onRemoveHistory: { history.wrappedValue = removeSearchHistory($0); },
        onClearHistory: { history.wrappedValue = clearSearchHistory(); }
    );
}
