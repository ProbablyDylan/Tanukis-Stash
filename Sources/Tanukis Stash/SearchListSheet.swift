//
//  SearchListSheet.swift
//  Tanuki
//

import SwiftUI

enum SearchSheetKind: String, Identifiable {
    case history, saved

    var id: String { rawValue }
}

// Recent or saved searches as a list. Tapping a row runs that search; swipes
// remove it (or, on a recent row, save it).
struct SearchListSheet: View {
    let kind: SearchSheetKind;
    let shelf: SearchShelf;
    @Environment(\.dismiss) private var dismiss;
    @State private var categories: [String: Int] = [:];
    @State private var confirmClear = false;

    private var queries: [String] {
        kind == .history ? shelf.history : shelf.saved
    }

    var body: some View {
        NavigationStack {
            Group {
                if queries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(queries, id: \.self) { query in
                            row(query)
                        }
                    }
                }
            }
            .navigationTitle(kind == .history ? "Recent Searches" : "Saved Searches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss(); }
                }
                if kind == .history && !queries.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear Recent Searches", systemImage: "trash", role: .destructive) { confirmClear = true; }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            // Attached to the button so the system presents it as
                            // a popover from there, not a bottom action sheet.
                            .confirmationDialog("Clear all recent searches?", isPresented: $confirmClear, titleVisibility: .visible) {
                                Button("Clear", role: .destructive) { shelf.onClearHistory(); }
                            }
                    }
                }
            }
        }
        .task(id: queries) {
            let names = queries
                .flatMap { $0.split(whereSeparator: \.isWhitespace) }
                .compactMap { plainTagName(of: $0) };
            let found = await Task.detached(priority: .userInitiated) { localTagCategories(names) }.value;
            guard !Task.isCancelled else { return; }
            categories = found;
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if kind == .history {
            ContentUnavailableView("No Recent Searches", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90", description: Text("Searches you run show up here."))
        } else {
            ContentUnavailableView("No Saved Searches", systemImage: "bookmark", description: Text("Tap the bookmark on a search's results to keep it here."))
        }
    }

    private func row(_ query: String) -> some View {
        Button {
            dismiss();
            shelf.onSelect(query);
        } label: {
            Text(coloredQuery(query, categories: categories))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        // A single line deletes outright; only Clear confirms.
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                if kind == .history { shelf.onRemoveHistory(query); } else { shelf.onToggleSaved(query); }
            }
        }
        .swipeActions(edge: .leading) {
            if kind == .history {
                let saved = isSavedSearch(query, in: shelf.saved);
                Button(saved ? "Unsave" : "Save", systemImage: saved ? "bookmark.slash" : "bookmark") { shelf.onToggleSaved(query); }
                    .tint(.blue)
            }
        }
    }
}
