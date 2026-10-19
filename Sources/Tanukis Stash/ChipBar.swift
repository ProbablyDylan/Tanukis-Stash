//
//  ChipBar.swift
//  Tanuki
//

import SwiftUI

private let chipPopAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.55);
private let chipPopCleanupDelay: TimeInterval = 0.6; // must exceed chipPopAnimation settle time

// One content height for every state, so the bar doesn't change size when a
// shelf swaps in taller chips than the (possibly empty) suggestions row.
private let chipBarContentHeight: CGFloat = 40;

private enum ChipBarMode {
    case suggestions, history, saved
}

extension AnyTransition {
    // The bar slides in with the keyboard but leaves with a quick fade: the
    // gesture-driven keyboard dismissal is faster than the .snappy animation
    // the search-active flag changes under, and the bar lingered behind it.
    static func chipBar(from edge: Edge) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: AnyTransition.opacity.animation(.easeOut(duration: 0.12))
        )
    }
}

struct ChipBar: View {
    let suggestions: [TagSuggestion];
    let onTap: (TagSuggestion) -> Void;
    // When set, leading chips swap the suggestions for recent or saved searches.
    var shelf: SearchShelf? = nil;
    @State private var mode: ChipBarMode = .suggestions;
    @State private var queryCategories: [String: Int] = [:];
    @State private var displayed: [TagSuggestion] = [];
    @State private var popping: Set<TagSuggestion> = [];

    private var hasToggles: Bool {
        guard let shelf else { return false; }
        return !shelf.history.isEmpty || !shelf.saved.isEmpty;
    }

    var body: some View {
        // The shelf toggles are pinned outside the scroll view, so suggestions
        // slide in from the scroll region's clipped edge instead of over them.
        HStack(spacing: 8) {
            if let shelf, hasToggles {
                HStack(spacing: 8) {
                    if !shelf.history.isEmpty {
                        shelfToggle(.history, symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90", label: "Recent searches");
                    }
                    if !shelf.saved.isEmpty {
                        shelfToggle(.saved, symbol: mode == .saved ? "bookmark.fill" : "bookmark", label: "Saved searches");
                    }
                }
                .padding(.leading, 12)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    switch mode {
                    case .suggestions:
                        ForEach(displayed, id: \.self) { tag in
                            Button(action: { handleTap(tag); }) {
                                Text(tag.name)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.tint(tagCategoryColor(tag.category)).interactive(), in: .capsule)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: popping.contains(tag)
                                    ? AnyTransition.scale(scale: 1.4).combined(with: .opacity)
                                    : AnyTransition.opacity
                            ))
                        }
                    case .history:
                        if let shelf {
                            ForEach(shelf.history, id: \.self) { query in
                                queryChip(query, shelf: shelf)
                                    .contextMenu {
                                        Button(isSavedSearch(query, in: shelf.saved) ? "Remove from Saved" : "Save Search",
                                               systemImage: isSavedSearch(query, in: shelf.saved) ? "bookmark.slash" : "bookmark") {
                                            shelf.onToggleSaved(query);
                                        }
                                        Button("Remove from Recent", systemImage: "xmark") { shelf.onRemoveHistory(query); }
                                        Button("Clear Recent Searches", systemImage: "trash", role: .destructive) { shelf.onClearHistory(); }
                                    }
                            }
                        }
                    case .saved:
                        if let shelf {
                            ForEach(shelf.saved, id: \.self) { query in
                                queryChip(query, shelf: shelf)
                                    .contextMenu {
                                        Button("Remove from Saved", systemImage: "bookmark.slash") { shelf.onToggleSaved(query); }
                                    }
                            }
                        }
                    }
                }
                .padding(.leading, hasToggles ? 4 : 12)
                .padding(.trailing, 12)
                .frame(minHeight: chipBarContentHeight)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        // The bar swallows touches across its whole frame, as the scroll view
        // alone used to; near-misses must not fall through to the post behind.
        .contentShape(Rectangle())
        .onAppear {
            withAnimation(.snappy) { displayed = suggestions; }
        }
        .task(id: (shelf?.history ?? []) + (shelf?.saved ?? [])) {
            let names = ((shelf?.history ?? []) + (shelf?.saved ?? []))
                .flatMap { $0.split(whereSeparator: \.isWhitespace) }
                .compactMap { plainTagName(of: $0) };
            let categories = await Task.detached(priority: .userInitiated) { localTagCategories(names) }.value;
            guard !Task.isCancelled else { return; }
            queryCategories = categories;
        }
        // Emptying the open shelf (last chip removed) falls back to suggestions.
        .onChange(of: shelf?.history) { _, new in
            if mode == .history && (new ?? []).isEmpty { withAnimation(.snappy) { mode = .suggestions; } }
        }
        .onChange(of: shelf?.saved) { _, new in
            if mode == .saved && (new ?? []).isEmpty { withAnimation(.snappy) { mode = .suggestions; } }
        }
        .onChange(of: suggestions) { _, new in
            // Typing produces fresh suggestions; they take the bar back from a shelf.
            if !new.isEmpty && mode != .suggestions {
                withAnimation(.snappy) { mode = .suggestions; }
            }
            if popping.isEmpty {
                withAnimation(.snappy) { displayed = new; }
            } else {
                withAnimation(chipPopAnimation) { displayed = new; }
            }
        }
    }

    private func shelfToggle(_ target: ChipBarMode, symbol: String, label: LocalizedStringKey) -> some View {
        let isOn = mode == target;
        return Button {
            withAnimation(.snappy) { mode = isOn ? .suggestions : target; }
        } label: {
            Image(systemName: symbol)
                .frame(minWidth: 44, minHeight: chipBarContentHeight)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func queryChip(_ query: String, shelf: SearchShelf) -> some View {
        Button {
            shelf.onSelect(query);
        } label: {
            Text(coloredQuery(query, categories: queryCategories))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .transition(.opacity)
    }

    private func handleTap(_ tag: TagSuggestion) {
        popping.insert(tag);
        // Two-phase: let SwiftUI render once with `popping` updated so the
        // .transition modifier captures the pop variant before the chip leaves.
        DispatchQueue.main.async {
            onTap(tag);
            DispatchQueue.main.asyncAfter(deadline: .now() + chipPopCleanupDelay) {
                popping.remove(tag);
            }
        }
    }
}
