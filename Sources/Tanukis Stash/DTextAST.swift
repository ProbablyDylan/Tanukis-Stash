//
//  DTextAST.swift
//  Tanuki
//

import Foundation

// MARK: - Block-level nodes

enum DTextBlock: Identifiable {
    case paragraph([DTextInline])
    case heading(level: Int, anchor: String?, content: [DTextInline])
    case quote(attribution: String?, children: [DTextBlock])
    case codeBlock(String)
    case spoilerBlock(id: Int, children: [DTextBlock])
    case section(title: String?, children: [DTextBlock])
    case list(items: [DTextListItem])
    case table(rows: [DTextTableRow])
    case horizontalRule
    case lineBreak
    case nodtext(String)
    case thumbEmbed(postId: Int)
    case thumbRow(postIds: [Int])

    var id: String {
        switch self {
        case .paragraph(let inlines): return "p-\(inlines.hashDescription)"
        case .heading(let level, _, let content): return "h\(level)-\(content.hashDescription)"
        case .quote(let attr, let children): return "quote-\(attr ?? "anon")-\(children.count)"
        case .codeBlock(let s): return "code-\(s.hashValue)"
        case .spoilerBlock(let id, _): return "spoiler-\(id)"
        case .section(let title, let children): return "section-\(title ?? "untitled")-\(children.count)"
        case .list(let items): return "list-\(items.count)-\(items.hashDescription)"
        case .table(let rows): return "table-\(rows.count)-\(rows.hashDescription)"
        case .horizontalRule: return "hr"
        case .lineBreak: return "br"
        case .nodtext(let s): return "nodtext-\(s.hashValue)"
        case .thumbEmbed(let id): return "thumb-\(id)"
        case .thumbRow(let ids): return "thumbrow-\(ids.map(String.init).joined(separator: "-"))"
        }
    }
}

struct DTextListItem: Identifiable {
    let id = UUID()
    let depth: Int
    let content: [DTextInline]
}

struct DTextTableRow: Identifiable {
    let id = UUID()
    let cells: [DTextTableCell]
}

struct DTextTableCell: Identifiable {
    let id = UUID()
    let isHeader: Bool
    let content: [DTextInline]
}

// MARK: - Inline nodes

indirect enum DTextInline {
    case text(String)
    case bold([DTextInline])
    case italic([DTextInline])
    case underline([DTextInline])
    case strikethrough([DTextInline])
    case superscript([DTextInline])
    case `subscript`([DTextInline])
    case inlineCode(String)
    case color(String, [DTextInline])
    case inlineSpoiler(id: Int, [DTextInline])
    case link(DTextLink)
    case postRef(Int)
    case poolRef(Int)
    case commentRef(Int)
    case userRef(String)
    case wikiLink(tag: String, display: String?)
    case searchLink(query: String, display: String?)
}

struct DTextLink {
    let url: String
    let display: [DTextInline]
}

// MARK: - Helpers

extension Array where Element == DTextInline {
    var hashDescription: String {
        String(describing: self).hashValue.description
    }

    var plainText: String {
        map { inline -> String in
            switch inline {
            case .text(let s): return s
            case .bold(let c), .italic(let c), .underline(let c), .strikethrough(let c),
                 .superscript(let c), .subscript(let c), .color(_, let c), .inlineSpoiler(_, let c):
                return c.plainText
            case .inlineCode(let s): return s
            case .link(let l): return l.display.plainText
            case .postRef(let id): return "post #\(id)"
            case .poolRef(let id): return "pool #\(id)"
            case .commentRef(let id): return "comment #\(id)"
            case .userRef(let name): return "@\(name)"
            case .wikiLink(_, let display): return display ?? ""
            case .searchLink(_, let display): return display ?? ""
            }
        }.joined()
    }
}

extension Array where Element == DTextListItem {
    var hashDescription: String {
        String(describing: self.map { $0.content.plainText }).hashValue.description
    }
}

extension Array where Element == DTextTableRow {
    var hashDescription: String {
        String(describing: self.map { $0.cells.count }).hashValue.description
    }
}
