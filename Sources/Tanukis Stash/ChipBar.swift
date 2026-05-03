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
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(tagCategoryColor(tag.category)).interactive(), in: .capsule)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .scale(scale: 1.4).combined(with: .opacity)
                    ))
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
        .onChange(of: suggestions) { _, new in
            withAnimation(.snappy) { displayed = new; }
        }
    }
}
