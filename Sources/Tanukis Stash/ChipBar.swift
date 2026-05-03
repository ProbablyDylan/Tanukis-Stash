//
//  ChipBar.swift
//  Tanuki
//

import SwiftUI

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
