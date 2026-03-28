//
//  DTextParser.swift
//  Tanuki
//

import Foundation

struct DTextParser {
    private var spoilerCounter: Int = 0

    mutating func parse(_ input: String) -> [DTextBlock] {
        let lines = input.replacingOccurrences(of: "\r\n", with: "\n")
        return parseBlocks(lines)
    }

    // MARK: - Block parsing

    private mutating func parseBlocks(_ input: String) -> [DTextBlock] {
        var blocks: [DTextBlock] = []
        var remaining = input[input.startIndex...]
        var paragraphLines: [String] = []

        func flushParagraph() {
            let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(parseInlines(text)))
            }
            paragraphLines.removeAll()
        }

        while !remaining.isEmpty {
            let line = consumeLine(&remaining)

            // [hr]
            if line.trimmingCharacters(in: .whitespaces).lowercased() == "[hr]" {
                flushParagraph()
                blocks.append(.horizontalRule)
                continue
            }

            // [br]
            if line.trimmingCharacters(in: .whitespaces).lowercased() == "[br]" {
                flushParagraph()
                blocks.append(.lineBreak)
                continue
            }

            // Headings: h1. through h6.
            if let headingMatch = line.firstMatch(of: /^h([1-6])\.(?:#([a-zA-Z0-9_-]+))?\s+(.+)$/) {
                flushParagraph()
                let level = Int(headingMatch.1)!
                let anchor = headingMatch.2.map(String.init)
                let content = String(headingMatch.3)
                blocks.append(.heading(level: level, anchor: anchor, content: parseInlines(content)))
                continue
            }

            // List items: * item, ** nested
            if line.firstMatch(of: /^\*+\s+/) != nil {
                flushParagraph()
                var listItems: [DTextListItem] = []
                listItems.append(parseListItem(line))
                while !remaining.isEmpty {
                    let nextLine = peekLine(remaining)
                    if nextLine.firstMatch(of: /^\*+\s+/) != nil {
                        _ = consumeLine(&remaining)
                        listItems.append(parseListItem(nextLine))
                    } else {
                        break
                    }
                }
                blocks.append(.list(items: listItems))
                continue
            }

            // thumb #123
            if let thumbMatch = line.firstMatch(of: /(?i)^thumb\s+#(\d+)\s*$/) {
                flushParagraph()
                blocks.append(.thumbEmbed(postId: Int(thumbMatch.1)!))
                continue
            }

            // Block-level tags
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()

            // [quote] ... [/quote]
            if trimmed.hasPrefix("[quote]") {
                flushParagraph()
                let content = extractBlockContent(tag: "quote", firstLine: line, remaining: &remaining)
                let (attribution, body) = parseQuoteAttribution(content)
                blocks.append(.quote(attribution: attribution, children: parseBlocks(body)))
                continue
            }

            // [code] ... [/code] (block)
            if trimmed.hasPrefix("[code]") {
                flushParagraph()
                let content = extractBlockContentRaw(tag: "code", firstLine: line, remaining: &remaining)
                blocks.append(.codeBlock(content))
                continue
            }

            // [spoiler] ... [/spoiler]
            if trimmed.hasPrefix("[spoiler]") {
                flushParagraph()
                spoilerCounter += 1
                let sid = spoilerCounter
                let content = extractBlockContent(tag: "spoiler", firstLine: line, remaining: &remaining)
                blocks.append(.spoilerBlock(id: sid, children: parseBlocks(content)))
                continue
            }

            // [section] or [expand] ... [/section] or [/expand]
            if trimmed.hasPrefix("[section") || trimmed.hasPrefix("[expand") {
                flushParagraph()
                let (title, content) = extractSectionContent(firstLine: line, remaining: &remaining)
                blocks.append(.section(title: title, children: parseBlocks(content)))
                continue
            }

            // [nodtext] ... [/nodtext]
            if trimmed.hasPrefix("[nodtext]") {
                flushParagraph()
                let content = extractBlockContentRaw(tag: "nodtext", firstLine: line, remaining: &remaining)
                blocks.append(.nodtext(content))
                continue
            }

            // [table] ... [/table]
            if trimmed.hasPrefix("[table]") {
                flushParagraph()
                let content = extractBlockContentRaw(tag: "table", firstLine: line, remaining: &remaining)
                blocks.append(parseTable(content))
                continue
            }

            // Blank line = paragraph break
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flushParagraph()
                continue
            }

            // Regular text line
            paragraphLines.append(line)
        }

        flushParagraph()
        return blocks
    }

    // MARK: - Block content extraction

    private func extractBlockContent(tag: String, firstLine: String, remaining: inout Substring) -> String {
        let openTag = "[\(tag)]"
        let closeTag = "[/\(tag)]"
        var content = ""
        var depth = 0

        // Get content after opening tag on first line
        if let range = firstLine.range(of: openTag, options: .caseInsensitive) {
            let after = String(firstLine[range.upperBound...])
            if let closeRange = after.range(of: closeTag, options: .caseInsensitive), depth == 0 {
                return String(after[after.startIndex..<closeRange.lowerBound])
            }
            depth = 1
            if !after.isEmpty { content = after }
        } else {
            depth = 1
        }

        while !remaining.isEmpty && depth > 0 {
            let line = consumeLine(&remaining)

            // Count nested opens and closes using case-insensitive search on original string
            var searchStart = line.startIndex
            while let openRange = line.range(of: openTag, options: .caseInsensitive, range: searchStart..<line.endIndex) {
                depth += 1
                searchStart = openRange.upperBound
            }

            searchStart = line.startIndex
            while let closeRange = line.range(of: closeTag, options: .caseInsensitive, range: searchStart..<line.endIndex) {
                depth -= 1
                if depth == 0 {
                    let beforeClose = String(line[line.startIndex..<closeRange.lowerBound])
                    if !content.isEmpty { content += "\n" }
                    content += beforeClose
                    return content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                searchStart = closeRange.upperBound
            }

            if depth > 0 {
                if !content.isEmpty { content += "\n" }
                content += line
            }
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractBlockContentRaw(tag: String, firstLine: String, remaining: inout Substring) -> String {
        let openTag = "[\(tag)]"
        let closeTag = "[/\(tag)]"
        var content = ""

        if let range = firstLine.range(of: openTag, options: .caseInsensitive) {
            let after = String(firstLine[range.upperBound...])
            if let closeRange = after.range(of: closeTag, options: .caseInsensitive) {
                return String(after[after.startIndex..<closeRange.lowerBound])
            }
            if !after.isEmpty { content = after }
        }

        while !remaining.isEmpty {
            let line = consumeLine(&remaining)
            if let closeRange = line.range(of: closeTag, options: .caseInsensitive) {
                let before = String(line[line.startIndex..<closeRange.lowerBound])
                if !content.isEmpty { content += "\n" }
                content += before
                return content
            }
            if !content.isEmpty { content += "\n" }
            content += line
        }

        return content
    }

    private func extractSectionContent(firstLine: String, remaining: inout Substring) -> (title: String?, content: String) {
        var title: String?
        let lower = firstLine.lowercased()

        // Parse title from [section=Title] or [section,expanded=Title] or [expand=Title]
        if let match = firstLine.firstMatch(of: /(?i)\[(section|expand)(?:,\s*expanded)?(?:=([^\]]*))?\]/) {
            title = match.2.map(String.init)
        }

        let isSection = lower.contains("[section")
        let closeTag = isSection ? "[/section]" : "[/expand]"
        let openTag = isSection ? "[section" : "[expand"
        var content = ""
        var depth = 1

        // Content after opening tag on first line
        if let closeBracket = firstLine.range(of: "]", range: firstLine.range(of: openTag, options: .caseInsensitive)!.upperBound..<firstLine.endIndex) {
            let after = String(firstLine[closeBracket.upperBound...])
            if !after.isEmpty { content = after }
        }

        while !remaining.isEmpty && depth > 0 {
            let line = consumeLine(&remaining)
            let lineLower = line.lowercased()

            if lineLower.contains(openTag) { depth += 1 }
            if lineLower.contains(closeTag) {
                depth -= 1
                if depth == 0 {
                    if let closeRange = line.range(of: closeTag, options: .caseInsensitive) {
                        let before = String(line[line.startIndex..<closeRange.lowerBound])
                        if !content.isEmpty { content += "\n" }
                        content += before
                    }
                    break
                }
            }

            if depth > 0 {
                if !content.isEmpty { content += "\n" }
                content += line
            }
        }

        return (title, content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Quote attribution

    private func parseQuoteAttribution(_ content: String) -> (String?, String) {
        // "Username":/users/12345 said:
        if let match = content.firstMatch(of: /^"([^"]+)":[^\s]+\s+said:\n?/) {
            let attr = String(match.1)
            let body = String(content[match.range.upperBound...])
            return (attr, body.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (nil, content)
    }

    // MARK: - List items

    private mutating func parseListItem(_ line: String) -> DTextListItem {
        let match = line.firstMatch(of: /^(\*+)\s+(.*)$/)!
        let depth = match.1.count
        let content = String(match.2)
        return DTextListItem(depth: depth, content: parseInlines(content))
    }

    // MARK: - Table parsing

    private mutating func parseTable(_ content: String) -> DTextBlock {
        var rows: [DTextTableRow] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces).lowercased()
            if line.contains("[tr]") {
                var cells: [DTextTableCell] = []
                i += 1
                while i < lines.count {
                    let cellLine = lines[i].trimmingCharacters(in: .whitespaces)
                    let cellLower = cellLine.lowercased()
                    if cellLower.contains("[/tr]") { break }

                    let isHeader = cellLower.hasPrefix("[th]")
                    if isHeader || cellLower.hasPrefix("[td]") {
                        let tag = isHeader ? "th" : "td"
                        let openTag = "[\(tag)]"
                        let closeTag = "[/\(tag)]"
                        if let openRange = cellLine.range(of: openTag, options: .caseInsensitive),
                           let closeRange = cellLine.range(of: closeTag, options: .caseInsensitive) {
                            let cellContent = String(cellLine[openRange.upperBound..<closeRange.lowerBound])
                            cells.append(DTextTableCell(isHeader: isHeader, content: parseInlines(cellContent)))
                        }
                    }
                    i += 1
                }
                rows.append(DTextTableRow(cells: cells))
            }
            i += 1
        }

        return .table(rows: rows)
    }

    // MARK: - Inline parsing

    mutating func parseInlines(_ input: String) -> [DTextInline] {
        var result: [DTextInline] = []
        var pos = input.startIndex
        var textStart = input.startIndex

        func flushText(upTo end: String.Index) {
            if textStart < end {
                let text = String(input[textStart..<end])
                if !text.isEmpty {
                    result.append(.text(text))
                }
            }
            textStart = end
        }

        while pos < input.endIndex {
            // BBCode tags
            if input[pos] == "[" {
                if let (node, end) = tryParseBBCode(input, from: pos) {
                    flushText(upTo: pos)
                    result.append(node)
                    pos = end
                    textStart = end
                    continue
                }
            }

            // Named link: "text":url
            if input[pos] == "\"" {
                if let (node, end) = tryParseNamedLink(input, from: pos) {
                    flushText(upTo: pos)
                    result.append(node)
                    pos = end
                    textStart = end
                    continue
                }
            }

            // Wiki link: [[...]] and search link: {{...}}
            if pos < input.index(before: input.endIndex) {
                let next = input.index(after: pos)
                if input[pos] == "[" && input[next] == "[" {
                    if let (node, end) = tryParseWikiLink(input, from: pos) {
                        flushText(upTo: pos)
                        result.append(node)
                        pos = end
                        textStart = end
                        continue
                    }
                }
                if input[pos] == "{" && input[next] == "{" {
                    if let (node, end) = tryParseSearchLink(input, from: pos) {
                        flushText(upTo: pos)
                        result.append(node)
                        pos = end
                        textStart = end
                        continue
                    }
                }
            }

            // Reference patterns: post #123, pool #123, comment #123
            if let (node, end) = tryParseReference(input, from: pos) {
                flushText(upTo: pos)
                result.append(node)
                pos = end
                textStart = end
                continue
            }

            // Bare URLs
            if let (node, end) = tryParseBareURL(input, from: pos) {
                flushText(upTo: pos)
                result.append(node)
                pos = end
                textStart = end
                continue
            }

            pos = input.index(after: pos)
        }

        // Flush remaining text
        flushText(upTo: input.endIndex)

        return result
    }

    // MARK: - BBCode inline parsing

    private mutating func tryParseBBCode(_ input: String, from pos: String.Index) -> (DTextInline, String.Index)? {
        let sub = input[pos...]

        // Simple tags
        let simpleTags: [(String, ([DTextInline]) -> DTextInline)] = [
            ("b", { .bold($0) }),
            ("i", { .italic($0) }),
            ("u", { .underline($0) }),
            ("s", { .strikethrough($0) }),
            ("sup", { .superscript($0) }),
            ("sub", { .subscript($0) }),
        ]

        for (tag, constructor) in simpleTags {
            let open = "[\(tag)]"
            let close = "[/\(tag)]"
            if sub.lowercased().hasPrefix(open) {
                if let closeRange = input.range(of: close, options: .caseInsensitive, range: input.index(pos, offsetBy: open.count)..<input.endIndex) {
                    let innerStart = input.index(pos, offsetBy: open.count)
                    let inner = String(input[innerStart..<closeRange.lowerBound])
                    let children = parseInlines(inner)
                    return (constructor(children), closeRange.upperBound)
                }
            }
        }

        // [code]...[/code] inline
        if sub.lowercased().hasPrefix("[code]") {
            let afterOpen = input.index(pos, offsetBy: 6)
            if let closeRange = input.range(of: "[/code]", options: .caseInsensitive, range: afterOpen..<input.endIndex) {
                let content = String(input[afterOpen..<closeRange.lowerBound])
                return (.inlineCode(content), closeRange.upperBound)
            }
        }

        // [color=...]...[/color]
        if let match = sub.firstMatch(of: /(?i)^\[color=([^\]]+)\]/) {
            let colorName = String(match.1);
            let afterOpen = match.range.upperBound;
            if let closeRange = input.range(of: "[/color]", options: .caseInsensitive, range: afterOpen..<input.endIndex) {
                let inner = String(input[afterOpen..<closeRange.lowerBound]);
                let children = parseInlines(inner);
                return (.color(colorName, children), closeRange.upperBound)
            }
        }

        // [spoiler]...[/spoiler] inline
        if sub.lowercased().hasPrefix("[spoiler]") {
            let afterOpen = input.index(pos, offsetBy: 9)
            if let closeRange = input.range(of: "[/spoiler]", options: .caseInsensitive, range: afterOpen..<input.endIndex) {
                spoilerCounter += 1
                let inner = String(input[afterOpen..<closeRange.lowerBound])
                let children = parseInlines(inner)
                return (.inlineSpoiler(id: spoilerCounter, children), closeRange.upperBound)
            }
        }

        // [url=...]...[/url]
        if let match = sub.firstMatch(of: /(?i)^\[url=([^\]]+)\]/) {
            let urlStr = String(match.1);
            let afterOpen = match.range.upperBound;
            if let closeRange = input.range(of: "[/url]", options: .caseInsensitive, range: afterOpen..<input.endIndex) {
                let inner = String(input[afterOpen..<closeRange.lowerBound]);
                let children = parseInlines(inner);
                return (.link(DTextLink(url: urlStr, display: children)), closeRange.upperBound)
            }
        }

        return nil
    }

    // MARK: - Named link: "text":url

    private func tryParseNamedLink(_ input: String, from pos: String.Index) -> (DTextInline, String.Index)? {
        // Must match "display text":url_without_spaces
        guard input[pos] == "\"" else { return nil }

        // Find closing quote
        let afterQuote = input.index(after: pos)
        guard afterQuote < input.endIndex else { return nil }

        guard let closeQuote = input.range(of: "\":", range: afterQuote..<input.endIndex) else { return nil }

        let display = String(input[afterQuote..<closeQuote.lowerBound])
        guard !display.isEmpty else { return nil }

        let urlStart = closeQuote.upperBound
        guard urlStart < input.endIndex else { return nil }

        // Consume URL until whitespace or end
        var urlEnd = urlStart
        while urlEnd < input.endIndex && !input[urlEnd].isWhitespace {
            urlEnd = input.index(after: urlEnd)
        }

        let urlStr = String(input[urlStart..<urlEnd])
        guard !urlStr.isEmpty else { return nil }

        // Validate it looks like a URL or relative path
        guard urlStr.hasPrefix("http") || urlStr.hasPrefix("/") || urlStr.hasPrefix("#") else { return nil }

        return (.link(DTextLink(url: urlStr, display: [.text(display)])), urlEnd)
    }

    // MARK: - Wiki links: [[tag]] or [[tag|display]]

    private func tryParseWikiLink(_ input: String, from pos: String.Index) -> (DTextInline, String.Index)? {
        let afterOpen = input.index(pos, offsetBy: 2)
        guard let closeRange = input.range(of: "]]", range: afterOpen..<input.endIndex) else { return nil }

        let inner = String(input[afterOpen..<closeRange.lowerBound])
        guard !inner.isEmpty else { return nil }

        let parts = inner.split(separator: "|", maxSplits: 1)
        let tag = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let display = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : nil

        return (.wikiLink(tag: tag, display: display), closeRange.upperBound)
    }

    // MARK: - Search links: {{query}} or {{query|display}}

    private func tryParseSearchLink(_ input: String, from pos: String.Index) -> (DTextInline, String.Index)? {
        let afterOpen = input.index(pos, offsetBy: 2)
        guard let closeRange = input.range(of: "}}", range: afterOpen..<input.endIndex) else { return nil }

        let inner = String(input[afterOpen..<closeRange.lowerBound])
        guard !inner.isEmpty else { return nil }

        let parts = inner.split(separator: "|", maxSplits: 1)
        let query = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let display = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : nil

        return (.searchLink(query: query, display: display), closeRange.upperBound)
    }

    // MARK: - Reference patterns

    private func tryParseReference(_ input: String, from pos: String.Index) -> (DTextInline, String.Index)? {
        // Only match at word boundary
        if pos > input.startIndex {
            let prevChar = input[input.index(before: pos)]
            if prevChar.isLetter || prevChar.isNumber { return nil }
        }

        let sub = input[pos...]

        if let match = sub.firstMatch(of: /(?i)^post\s+#(\d+)/) {
            guard let id = Int(match.1) else { return nil }
            return (.postRef(id), match.range.upperBound)
        }
        if let match = sub.firstMatch(of: /(?i)^pool\s+#(\d+)/) {
            guard let id = Int(match.1) else { return nil }
            return (.poolRef(id), match.range.upperBound)
        }
        if let match = sub.firstMatch(of: /(?i)^comment\s+#(\d+)/) {
            guard let id = Int(match.1) else { return nil }
            return (.commentRef(id), match.range.upperBound)
        }

        return nil
    }

    // MARK: - Bare URLs

    private func tryParseBareURL(_ input: String, from pos: String.Index) -> (DTextInline, String.Index)? {
        let sub = input[pos...]
        guard sub.hasPrefix("http://") || sub.hasPrefix("https://") else { return nil }

        // Only match at word boundary
        if pos > input.startIndex {
            let prevChar = input[input.index(before: pos)]
            if prevChar.isLetter || prevChar.isNumber { return nil }
        }

        var end = pos
        while end < input.endIndex && !input[end].isWhitespace && input[end] != ">" && input[end] != "]" {
            end = input.index(after: end)
        }

        // Strip trailing punctuation
        while end > pos {
            let prev = input[input.index(before: end)]
            if [Character("."), Character(","), Character(";"), Character(")"), Character("!")].contains(prev) {
                end = input.index(before: end)
            } else {
                break
            }
        }

        let urlStr = String(input[pos..<end])
        guard urlStr.count > 8 else { return nil }

        return (.link(DTextLink(url: urlStr, display: [.text(urlStr)])), end)
    }

    // MARK: - Line utilities

    private func consumeLine(_ remaining: inout Substring) -> String {
        if let newlineIndex = remaining.firstIndex(of: "\n") {
            let line = String(remaining[remaining.startIndex..<newlineIndex])
            remaining = remaining[remaining.index(after: newlineIndex)...]
            return line
        } else {
            let line = String(remaining)
            remaining = remaining[remaining.endIndex...]
            return line
        }
    }

    private func peekLine(_ remaining: Substring) -> String {
        if let newlineIndex = remaining.firstIndex(of: "\n") {
            return String(remaining[remaining.startIndex..<newlineIndex])
        }
        return String(remaining)
    }
}
