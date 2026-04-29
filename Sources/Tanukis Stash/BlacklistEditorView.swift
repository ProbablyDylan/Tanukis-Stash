//
//  BlacklistEditorView.swift
//  Tanuki
//

import SwiftUI
import UIKit

struct BlacklistEditorView: View {
    @Environment(\.dismiss) private var dismiss;
    @State private var text: String = UserDefaults.standard.string(forKey: UDKey.userBlacklist) ?? "";
    @State private var originalText: String = UserDefaults.standard.string(forKey: UDKey.userBlacklist) ?? "";
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0);
    @State private var tagSuggestions: [TagSuggestion] = [];
    @State private var suggestionTask: Task<Void, Never>?;
    @State private var lastQuery: String = "";
    @State private var isSaving: Bool = false;
    @State private var saveError: String? = nil;
    @State private var hasLoadedFromServer: Bool = false;
    @State private var dirtyAnimated: Bool = false;

    private var dirty: Bool { text != originalText; }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                BlacklistTextView(
                    text: $text,
                    selectedRange: $selectedRange,
                    suggestions: tagSuggestions,
                    onSuggestionTap: applySuggestion
                )
            }
            .navigationTitle("Blacklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if dirty {
                        Menu {
                            Button("Discard Changes", systemImage: "trash", role: .destructive) {
                                dismiss();
                            }
                        } label: {
                            Image(systemName: "xmark")
                        }
                    } else {
                        Button(action: { dismiss(); }) {
                            Image(systemName: "xmark")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else if dirtyAnimated {
                        Button(action: { Task { await save(); } }) {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .onChange(of: text) {
                if saveError != nil { withAnimation { saveError = nil; } }
                refreshSuggestions();
                if dirtyAnimated != dirty {
                    withAnimation(.snappy) { dirtyAnimated = dirty; }
                }
            }
            .onChange(of: originalText) {
                if dirtyAnimated != dirty {
                    withAnimation(.snappy) { dirtyAnimated = dirty; }
                }
            }
            .onChange(of: selectedRange) {
                refreshSuggestions();
            }
            .task {
                guard !hasLoadedFromServer else { return; }
                hasLoadedFromServer = true;
                if let bl = await fetchBlacklist() {
                    if !dirty {
                        text = bl;
                        originalText = bl;
                    } else {
                        originalText = bl;
                    }
                }
            }
        }
    }

    private func refreshSuggestions() {
        guard let token = currentBlacklistToken(in: text, selectedRange: selectedRange) else {
            if !tagSuggestions.isEmpty { tagSuggestions = []; }
            lastQuery = "";
            suggestionTask?.cancel();
            return;
        }
        if token.query == lastQuery { return; }
        lastQuery = token.query;
        debouncedTagSuggestion(query: token.query, task: &suggestionTask, results: $tagSuggestions);
    }

    private func applySuggestion(_ tag: TagSuggestion) {
        guard let token = currentBlacklistToken(in: text, selectedRange: selectedRange) else { return; }
        let prefix = token.hadDash ? "-" : "";
        let replacement = prefix + tag.name + " ";
        let nsText = text as NSString;
        let newText = nsText.replacingCharacters(in: token.nsRange, with: replacement);
        let newCaret = token.nsRange.location + (replacement as NSString).length;
        text = newText;
        selectedRange = NSRange(location: newCaret, length: 0);
        tagSuggestions = [];
        lastQuery = "";
    }

    private func save() async {
        isSaving = true;
        saveError = nil;
        let success = await updateBlacklist(tags: text);
        isSaving = false;
        if success {
            UserDefaults.standard.set(text, forKey: UDKey.userBlacklist);
            originalText = text;
            dismiss();
        } else {
            withAnimation { saveError = "Couldn't save blacklist. Try again."; }
        }
    }
}

struct BlacklistToken {
    let nsRange: NSRange;
    let query: String;
    let hadDash: Bool;
}

func currentBlacklistToken(in text: String, selectedRange: NSRange) -> BlacklistToken? {
    let nsText = text as NSString;
    let length = nsText.length;
    let caret = max(0, min(selectedRange.location, length));
    let upperCaret = max(caret, min(selectedRange.location + selectedRange.length, length));

    let delimiters = CharacterSet.whitespacesAndNewlines;

    var start = caret;
    while start > 0 {
        let ch = nsText.substring(with: NSRange(location: start - 1, length: 1));
        if let scalar = ch.unicodeScalars.first, delimiters.contains(scalar) { break; }
        start -= 1;
    }

    var end = upperCaret;
    while end < length {
        let ch = nsText.substring(with: NSRange(location: end, length: 1));
        if let scalar = ch.unicodeScalars.first, delimiters.contains(scalar) { break; }
        end += 1;
    }

    let tokenRange = NSRange(location: start, length: end - start);
    if tokenRange.length == 0 { return nil; }
    var token = nsText.substring(with: tokenRange);

    var hadDash = false;
    if token.hasPrefix("-") {
        hadDash = true;
        token = String(token.dropFirst());
    }

    if token.count < 2 { return nil; }
    if token.contains(":") { return nil; }

    return BlacklistToken(nsRange: tokenRange, query: token, hadDash: hadDash);
}

struct ChipBar: View {
    let suggestions: [TagSuggestion];
    let onTap: (TagSuggestion) -> Void;
    @State private var displayed: [TagSuggestion] = [];

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(displayed, id: \.self) { tag in
                    Button(action: { onTap(tag); }) {
                        Text(tag.name)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(tagCategoryColor(tag.category))
                    .transition(.scale.combined(with: .opacity))
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
        .onAppear { displayed = suggestions; }
        .onChange(of: suggestions) { _, new in
            withAnimation(.snappy) { displayed = new; }
        }
    }
}

struct BlacklistTextView: UIViewRepresentable {
    @Binding var text: String;
    @Binding var selectedRange: NSRange;
    var suggestions: [TagSuggestion];
    var onSuggestionTap: (TagSuggestion) -> Void;

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView();
        tv.font = UIFont.monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular);
        tv.autocorrectionType = .no;
        tv.autocapitalizationType = .none;
        tv.smartQuotesType = .no;
        tv.smartDashesType = .no;
        tv.spellCheckingType = .no;
        tv.delegate = context.coordinator;
        tv.text = text;
        tv.backgroundColor = .clear;
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12);
        tv.alwaysBounceVertical = true;

        let host = UIHostingController(rootView: ChipBar(suggestions: suggestions, onTap: onSuggestionTap));
        host.sizingOptions = .intrinsicContentSize;
        host.view.backgroundColor = .clear;
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 44);
        host.view.autoresizingMask = [.flexibleWidth];
        tv.inputAccessoryView = host.view;
        context.coordinator.host = host;

        return tv;
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let needsTextUpdate = uiView.text != text;
        if needsTextUpdate { uiView.text = text; }

        let length = (text as NSString).length;
        let loc = max(0, min(selectedRange.location, length));
        let len = max(0, min(selectedRange.length, length - loc));
        let bounded = NSRange(location: loc, length: len);
        if uiView.selectedRange != bounded { uiView.selectedRange = bounded; }

        context.coordinator.host?.rootView = ChipBar(suggestions: suggestions, onTap: onSuggestionTap);
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlacklistTextView;
        var host: UIHostingController<ChipBar>?;
        init(_ parent: BlacklistTextView) { self.parent = parent; }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text;
            parent.selectedRange = textView.selectedRange;
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if parent.selectedRange != textView.selectedRange {
                parent.selectedRange = textView.selectedRange;
            }
        }
    }
}
