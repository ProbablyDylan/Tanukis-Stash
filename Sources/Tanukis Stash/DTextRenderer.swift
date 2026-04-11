//
//  DTextRenderer.swift
//  Tanuki
//

import SwiftUI
import Kingfisher

// MARK: - Block renderer

struct DTextBlockView: View {
    let block: DTextBlock
    @Binding var revealedSpoilers: Set<Int>
    let domain: String

    var body: some View {
        switch block {
        case .paragraph(let inlines):
            DTextInlineView(inlines: inlines, revealedSpoilers: $revealedSpoilers, domain: domain)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .heading(let level, _, let content):
            DTextInlineView(inlines: content, revealedSpoilers: $revealedSpoilers, domain: domain)
                .font(headingFont(level))
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .quote(let attribution, let children):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    if let name = attribution {
                        Text("\(name) said:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(children) { child in
                        DTextBlockView(block: child, revealedSpoilers: $revealedSpoilers, domain: domain)
                    }
                }
            }
            .padding(.leading, 4)

        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case .spoilerBlock(let id, let children):
            if revealedSpoilers.contains(id) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(children) { child in
                        DTextBlockView(block: child, revealedSpoilers: $revealedSpoilers, domain: domain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture { revealedSpoilers.remove(id) }
            } else {
                Text("Spoiler (tap to reveal)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { revealedSpoilers.insert(id) }
            }

        case .section(let title, let children):
            DisclosureGroup(title ?? "Show") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(children) { child in
                        DTextBlockView(block: child, revealedSpoilers: $revealedSpoilers, domain: domain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .list(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 0) {
                        Text(String(repeating: "    ", count: item.depth - 1) + "•  ")
                            .foregroundStyle(.secondary)
                        DTextInlineView(inlines: item.content, revealedSpoilers: $revealedSpoilers, domain: domain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .table(let rows):
            DTextTableView(rows: rows, revealedSpoilers: $revealedSpoilers, domain: domain)

        case .horizontalRule:
            Divider()

        case .lineBreak:
            Spacer().frame(height: 8)

        case .nodtext(let text):
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .thumbEmbed(let postId):
            DTextThumbEmbed(postId: postId)

        case .thumbRow(let postIds):
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(postIds, id: \.self) { id in
                        DTextThumbEmbed(postId: id)
                    }
                }
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        case 4: return .headline
        case 5: return .subheadline
        default: return .footnote
        }
    }
}

// MARK: - Inline renderer (AttributedString-based)

struct DTextInlineView: View {
    let inlines: [DTextInline]
    @Binding var revealedSpoilers: Set<Int>
    let domain: String

    var body: some View {
        Text(buildAttributedString(inlines))
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "tanuki", url.host == "spoiler",
                   let idStr = url.pathComponents.last, let id = Int(idStr) {
                    if revealedSpoilers.contains(id) {
                        revealedSpoilers.remove(id)
                    } else {
                        revealedSpoilers.insert(id)
                    }
                    return .handled
                }
                return .systemAction
            })
    }

    private func buildAttributedString(_ nodes: [DTextInline]) -> AttributedString {
        var result = AttributedString()
        for node in nodes {
            result.append(renderInline(node))
        }
        return result
    }

    private func renderInline(_ node: DTextInline) -> AttributedString {
        switch node {
        case .text(let s):
            return AttributedString(s)

        case .bold(let children):
            var str = buildAttributedString(children)
            str.inlinePresentationIntent = .stronglyEmphasized
            return str

        case .italic(let children):
            var str = buildAttributedString(children)
            str.inlinePresentationIntent = .emphasized
            return str

        case .underline(let children):
            var str = buildAttributedString(children)
            str.underlineStyle = .single
            return str

        case .strikethrough(let children):
            var str = buildAttributedString(children)
            str.strikethroughStyle = .single
            return str

        case .superscript(let children):
            var str = buildAttributedString(children)
            str.baselineOffset = 6
            str.font = .caption2
            return str

        case .subscript(let children):
            var str = buildAttributedString(children)
            str.baselineOffset = -4
            str.font = .caption2
            return str

        case .inlineCode(let s):
            var str = AttributedString(s)
            str.font = .system(.body, design: .monospaced)
            str.backgroundColor = .secondary.opacity(0.15)
            return str

        case .color(let colorName, let children):
            var str = buildAttributedString(children)
            str.foregroundColor = parseColor(colorName)
            return str

        case .inlineSpoiler(let id, let children):
            if revealedSpoilers.contains(id) {
                var str = buildAttributedString(children)
                str.backgroundColor = .secondary.opacity(0.15)
                str.link = URL(string: "tanuki://spoiler/\(id)")
                return str
            } else {
                var str = AttributedString(children.plainText)
                str.foregroundColor = .clear
                str.backgroundColor = .secondary.opacity(0.3)
                str.link = URL(string: "tanuki://spoiler/\(id)")
                return str
            }

        case .link(let link):
            var str = buildAttributedString(link.display)
            if let url = URL(string: link.url) {
                str.link = url
            }
            return str

        case .postRef(let id):
            var str = AttributedString("post #\(id)")
            str.link = URL(string: "tanuki://post/\(id)")
            return str

        case .poolRef(let id):
            var str = AttributedString("pool #\(id)")
            str.link = URL(string: "tanuki://pool/\(id)")
            return str

        case .commentRef(let id):
            var str = AttributedString("comment #\(id)");
            str.link = URL(string: "tanuki://comment/\(id)");
            return str;

        case .userRef(let name):
            var str = AttributedString("@\(name)")
            str.link = URL(string: "https://\(domain)/users/\(name)")
            return str

        case .wikiLink(let tag, let display):
            var str = AttributedString(display ?? tag.replacingOccurrences(of: "_", with: " "))
            str.link = URL(string: "tanuki://wiki/\(tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag)")
            return str

        case .searchLink(let query, let display):
            var str = AttributedString(display ?? query.replacingOccurrences(of: "_", with: " "))
            str.link = URL(string: "tanuki://search/\(query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query)")
            return str

        case .topicRef(let id):
            var str = AttributedString("topic #\(id)");
            str.link = URL(string: "https://\(domain)/forum_topics/\(id)");
            return str;

        case .forumRef(let id):
            var str = AttributedString("forum #\(id)");
            str.link = URL(string: "https://\(domain)/forum_posts/\(id)");
            return str;

        case .artistRef(let id):
            var str = AttributedString("artist #\(id)");
            str.link = URL(string: "https://\(domain)/artists/\(id)");
            return str;

        case .translationNote(let children):
            var str = buildAttributedString(children);
            str.font = .caption2;
            str.foregroundColor = .secondary;
            str.baselineOffset = 6;
            return str;
        }
    }

    private func parseColor(_ name: String) -> Color {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.hasPrefix("#") {
            return Color(hex: lower)
        }
        switch lower {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "cyan": return .cyan
        case "pink": return .pink
        case "white": return .white
        case "black": return .black
        case "gray", "grey": return .gray
        default: return .primary
        }
    }
}

// MARK: - Table view

struct DTextTableView: View {
    let rows: [DTextTableRow]
    @Binding var revealedSpoilers: Set<Int>
    let domain: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(row.cells) { cell in
                        if cell.isHeader {
                            DTextInlineView(inlines: cell.content, revealedSpoilers: $revealedSpoilers, domain: domain)
                                .fontWeight(.bold)
                                .padding(.vertical, 6)
                        } else {
                            DTextInlineView(inlines: cell.content, revealedSpoilers: $revealedSpoilers, domain: domain)
                                .padding(.vertical, 6)
                                .textSelection(.enabled)
                        }
                    }
                }
                .background(row.cells.contains(where: { $0.isHeader }) ? Color.secondary.opacity(0.1) : Color.clear)
                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Thumb embed

struct DTextThumbEmbed: View {
    let postId: Int
    @State private var post: PostContent?

    var body: some View {
        Group {
            if let post = post {
                NavigationLink(destination: PostView(post: post, search: "")) {
                    KFImage(URL(string: post.preview.url ?? ""))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 150, height: 150)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                ProgressView()
                    .frame(width: 150, height: 150)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .task { post = await getPost(postId: postId) }
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: Double
        switch cleaned.count {
        case 3:
            r = Double((int >> 8) & 0xF) / 15.0
            g = Double((int >> 4) & 0xF) / 15.0
            b = Double(int & 0xF) / 15.0
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}
