//
//  DTextView.swift
//  Tanuki
//

import SwiftUI

struct DTextView: View {
    let text: String
    @State private var revealedSpoilers: Set<Int> = []
    @State private var blocks: [DTextBlock] = []

    private let domain = UserDefaults.standard.string(forKey: "api_source") ?? "e926.net"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks) { block in
                DTextBlockView(block: block, revealedSpoilers: $revealedSpoilers, domain: domain)
            }
        }
        .onAppear { parseIfNeeded() }
        .onChange(of: text) { parseIfNeeded() }
    }

    private func parseIfNeeded() {
        var parser = DTextParser()
        blocks = parser.parse(text)
    }
}
