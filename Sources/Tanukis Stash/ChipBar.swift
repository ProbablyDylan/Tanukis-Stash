//
//  ChipBar.swift
//  Tanuki
//

import SwiftUI

private let chipPopAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.55);
private let chipPopCleanupDelay: TimeInterval = 0.6; // must exceed chipPopAnimation settle time

private enum ChipBarMode {
    case suggestions, history, saved
}

struct ChipBar: View {
    let suggestions: [TagSuggestion];
    let onTap: (TagSuggestion) -> Void;
    // When set, leading chips swap the suggestions for recent or saved searches.
    var shelf: SearchShelf? = nil;
    @State private var mode: ChipBarMode = .suggestions;
    @State private var displayed: [TagSuggestion] = [];
    @State private var popping: Set<TagSuggestion> = [];

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let shelf {
                    if !shelf.history.isEmpty {
                        shelfToggle(.history, symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90", label: "Recent searches");
                    }
                    if !shelf.saved.isEmpty {
                        shelfToggle(.saved, symbol: mode == .saved ? "bookmark.fill" : "bookmark", label: "Saved searches");
                    }
                }
                switch mode {
                case .suggestions:
                    ForEach(displayed, id: \.self) { tag in
                        Button(action: { handleTap(tag); }) {
                            Text(tag.name)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
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
        .onAppear {
            withAnimation(.snappy) { displayed = suggestions; }
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
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
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
            Text(query)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
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
