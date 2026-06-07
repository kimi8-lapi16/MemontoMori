import Foundation
import AppKit

enum MarkdownRenderer {
    static func render(_ source: String) -> NSAttributedString {
        Parser(source: source).parse()
    }
}

private final class Parser {
    private let lines: [String]

    private let baseSize: CGFloat = 14
    private let codeSize: CGFloat = 13

    private var baseFont: NSFont { .systemFont(ofSize: baseSize) }
    private var codeFont: NSFont { .monospacedSystemFont(ofSize: codeSize, weight: .regular) }
    private var codeBackgroundColor: NSColor { NSColor.secondaryLabelColor.withAlphaComponent(0.12) }
    private var blockquoteColor: NSColor { .secondaryLabelColor }

    init(source: String) {
        self.lines = source.components(separatedBy: "\n")
    }

    func parse() -> NSAttributedString {
        let result = NSMutableAttributedString()
        var index = 0
        var shouldInsertGap = false

        func startBlock() {
            if shouldInsertGap {
                result.append(blankLine())
                shouldInsertGap = false
            }
        }

        while index < lines.count {
            let line = lines[index]

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                shouldInsertGap = (result.length > 0)
                index += 1
                continue
            }

            if let fenceInfo = openingFence(line) {
                startBlock()
                let (block, nextIndex) = collectFencedCode(start: index + 1, fence: fenceInfo)
                result.append(renderCodeBlock(block))
                index = nextIndex
                continue
            }

            if isHorizontalRule(line) {
                startBlock()
                result.append(renderHorizontalRule())
                index += 1
                continue
            }

            if let (level, text) = parseHeading(line) {
                startBlock()
                result.append(renderHeading(level: level, text: text))
                index += 1
                continue
            }

            if isBlockquoteLine(line) {
                startBlock()
                let (block, nextIndex) = collectBlockquote(start: index)
                result.append(renderBlockquote(block))
                index = nextIndex
                continue
            }

            if listMarker(line) != nil {
                startBlock()
                let (items, nextIndex) = collectList(start: index)
                result.append(renderList(items))
                index = nextIndex
                continue
            }

            startBlock()
            let (paragraph, nextIndex) = collectParagraph(start: index)
            result.append(renderParagraph(paragraph))
            index = nextIndex
        }

        return result
    }

    // MARK: - Block detection

    private struct FenceInfo {
        let marker: Character
        let length: Int
    }

    private func openingFence(_ line: String) -> FenceInfo? {
        let trimmed = line.drop(while: { $0 == " " })
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        var count = 0
        for ch in trimmed where ch == first { count += 1 }
        guard count >= 3 else { return nil }
        let afterMarker = trimmed.drop(while: { $0 == first })
        // remaining can be info string; allow anything
        _ = afterMarker
        return FenceInfo(marker: first, length: count)
    }

    private func isClosingFence(_ line: String, for fence: FenceInfo) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.allSatisfy({ $0 == fence.marker }) else { return false }
        return trimmed.count >= fence.length
    }

    private func collectFencedCode(start: Int, fence: FenceInfo) -> (String, Int) {
        var i = start
        var collected: [String] = []
        while i < lines.count {
            if isClosingFence(lines[i], for: fence) {
                return (collected.joined(separator: "\n"), i + 1)
            }
            collected.append(lines[i])
            i += 1
        }
        return (collected.joined(separator: "\n"), i)
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        guard let first = trimmed.first, first == "-" || first == "*" || first == "_" else { return false }
        return trimmed.allSatisfy { $0 == first }
    }

    private func parseHeading(_ line: String) -> (Int, String)? {
        var hashCount = 0
        for ch in line {
            if ch == "#" { hashCount += 1 } else { break }
        }
        guard hashCount >= 1, hashCount <= 6 else { return nil }
        let afterHashes = line.dropFirst(hashCount)
        guard afterHashes.first == " " || afterHashes.isEmpty else { return nil }
        let text = afterHashes.drop(while: { $0 == " " })
        return (hashCount, String(text))
    }

    private func isBlockquoteLine(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " })
        return trimmed.first == ">"
    }

    private func collectBlockquote(start: Int) -> ([String], Int) {
        var i = start
        var collected: [String] = []
        while i < lines.count, isBlockquoteLine(lines[i]) {
            var body = lines[i].drop(while: { $0 == " " })
            body = body.dropFirst() // drop '>'
            if body.first == " " { body = body.dropFirst() }
            collected.append(String(body))
            i += 1
        }
        return (collected, i)
    }

    private struct ListItem {
        var indent: Int
        var ordered: Bool
        var orderNumber: Int?
        var task: TaskState
        var text: String
    }

    private enum TaskState { case none, unchecked, checked }

    private func listMarker(_ line: String) -> (indent: Int, ordered: Bool, orderNumber: Int?, rest: String)? {
        var leadingSpaces = 0
        for ch in line {
            if ch == " " { leadingSpaces += 1 }
            else if ch == "\t" { leadingSpaces += 4 }
            else { break }
        }
        let body = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = body.first else { return nil }

        if first == "-" || first == "*" || first == "+" {
            let afterMarker = body.dropFirst()
            guard afterMarker.first == " " else { return nil }
            return (leadingSpaces, false, nil, String(afterMarker.dropFirst()))
        }

        if first.isNumber {
            var digits = ""
            var rest = body[...]
            for ch in body {
                if ch.isNumber { digits.append(ch); rest = rest.dropFirst() } else { break }
            }
            guard let dot = rest.first, dot == "." || dot == ")" else { return nil }
            rest = rest.dropFirst()
            guard rest.first == " " else { return nil }
            return (leadingSpaces, true, Int(digits), String(rest.dropFirst()))
        }

        return nil
    }

    private func collectList(start: Int) -> ([ListItem], Int) {
        var i = start
        var items: [ListItem] = []
        while i < lines.count, let marker = listMarker(lines[i]) {
            var text = marker.rest
            var task: TaskState = .none
            if text.hasPrefix("[ ] ") || text == "[ ]" {
                task = .unchecked
                text = String(text.dropFirst(min(4, text.count)))
            } else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") || text == "[x]" || text == "[X]" {
                task = .checked
                text = String(text.dropFirst(min(4, text.count)))
            }
            items.append(ListItem(
                indent: marker.indent,
                ordered: marker.ordered,
                orderNumber: marker.orderNumber,
                task: task,
                text: text
            ))
            i += 1
        }
        return (items, i)
    }

    private func collectParagraph(start: Int) -> (String, Int) {
        var i = start
        var collected: [String] = []
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            if openingFence(line) != nil { break }
            if isHorizontalRule(line) { break }
            if parseHeading(line) != nil { break }
            if isBlockquoteLine(line) { break }
            if listMarker(line) != nil { break }
            collected.append(line)
            i += 1
        }
        return (collected.joined(separator: " "), i)
    }

    // MARK: - Rendering

    private func paragraphStyle(
        firstIndent: CGFloat = 0,
        headIndent: CGFloat = 0,
        paragraphSpacing: CGFloat = 2
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = firstIndent
        style.headIndent = headIndent
        style.paragraphSpacing = paragraphSpacing
        style.lineHeightMultiple = 1.15
        return style
    }

    private func blankLine() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 0
        return NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: baseSize * 0.5),
            .paragraphStyle: style
        ])
    }

    private func renderHeading(level: Int, text: String) -> NSAttributedString {
        let sizes: [CGFloat] = [24, 20, 17, 15, 14, 13]
        let size = sizes[min(max(level - 1, 0), sizes.count - 1)]
        let font = NSFont.boldSystemFont(ofSize: size)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = level == 1 ? 6 : 4
        style.paragraphSpacing = 4
        style.lineHeightMultiple = 1.15

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: style
        ]
        let inline = renderInline(text, baseAttributes: attrs)
        let mutable = NSMutableAttributedString(attributedString: inline)
        mutable.append(NSAttributedString(string: "\n", attributes: attrs))
        return mutable
    }

    private func renderHorizontalRule() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: baseSize),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: style
        ]
        return NSAttributedString(string: "──────────\n", attributes: attrs)
    }

    private func renderCodeBlock(_ body: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        style.paragraphSpacing = 4
        style.paragraphSpacingBefore = 2
        style.lineHeightMultiple = 1.1

        let attrs: [NSAttributedString.Key: Any] = [
            .font: codeFont,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: codeBackgroundColor,
            .paragraphStyle: style
        ]
        let text = body + "\n"
        return NSAttributedString(string: text, attributes: attrs)
    }

    private func renderBlockquote(_ lines: [String]) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        style.paragraphSpacing = 4
        style.lineHeightMultiple = 1.15

        let attrs: [NSAttributedString.Key: Any] = [
            .font: italicFont(baseFont),
            .foregroundColor: blockquoteColor,
            .paragraphStyle: style
        ]

        let result = NSMutableAttributedString()
        for line in lines {
            let prefix = NSAttributedString(string: "│ ", attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: style
            ])
            result.append(prefix)
            result.append(renderInline(line, baseAttributes: attrs))
            result.append(NSAttributedString(string: "\n", attributes: attrs))
        }
        return result
    }

    private func renderList(_ items: [ListItem]) -> NSAttributedString {
        let minIndent = items.map(\.indent).min() ?? 0
        let result = NSMutableAttributedString()

        for item in items {
            let level = max(0, (item.indent - minIndent) / 2)
            let leading = CGFloat(12 + level * 16)
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = leading
            style.headIndent = leading + 16
            style.paragraphSpacing = 2
            style.lineHeightMultiple = 1.15

            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: style
            ]

            let bullet: String
            switch item.task {
            case .unchecked: bullet = "☐ "
            case .checked: bullet = "☑ "
            case .none:
                if item.ordered {
                    bullet = "\(item.orderNumber ?? 1). "
                } else {
                    bullet = level == 0 ? "• " : (level == 1 ? "◦ " : "▪ ")
                }
            }

            let bulletAttrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: item.task == .none ? NSColor.secondaryLabelColor : NSColor.textColor,
                .paragraphStyle: style
            ]

            result.append(NSAttributedString(string: bullet, attributes: bulletAttrs))
            result.append(renderInline(item.text, baseAttributes: textAttrs))
            result.append(NSAttributedString(string: "\n", attributes: textAttrs))
        }
        return result
    }

    private func renderParagraph(_ text: String) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle(paragraphSpacing: 4)
        ]
        let inline = NSMutableAttributedString(attributedString: renderInline(text, baseAttributes: attrs))
        inline.append(NSAttributedString(string: "\n", attributes: attrs))
        return inline
    }

    // MARK: - Inline

    private func renderInline(_ text: String, baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(text)
        var i = 0
        var buffer = ""

        func flushBuffer() {
            if !buffer.isEmpty {
                result.append(NSAttributedString(string: buffer, attributes: baseAttributes))
                buffer = ""
            }
        }

        while i < chars.count {
            let c = chars[i]

            if c == "\\", i + 1 < chars.count {
                buffer.append(chars[i + 1])
                i += 2
                continue
            }

            if c == "`" {
                if let end = findInlineCodeEnd(chars: chars, from: i + 1) {
                    flushBuffer()
                    let codeText = String(chars[(i + 1)..<end])
                    var attrs = baseAttributes
                    attrs[.font] = codeFont
                    attrs[.backgroundColor] = codeBackgroundColor
                    result.append(NSAttributedString(string: codeText, attributes: attrs))
                    i = end + 1
                    continue
                }
            }

            if c == "*" || c == "_" {
                if i + 1 < chars.count, chars[i + 1] == c {
                    if let end = findClosingDouble(chars: chars, marker: c, from: i + 2) {
                        flushBuffer()
                        let inner = String(chars[(i + 2)..<end])
                        var attrs = baseAttributes
                        let currentFont = (baseAttributes[.font] as? NSFont) ?? baseFont
                        attrs[.font] = boldFont(currentFont)
                        result.append(renderInline(inner, baseAttributes: attrs))
                        i = end + 2
                        continue
                    }
                }
                if let end = findClosingSingle(chars: chars, marker: c, from: i + 1) {
                    flushBuffer()
                    let inner = String(chars[(i + 1)..<end])
                    var attrs = baseAttributes
                    let currentFont = (baseAttributes[.font] as? NSFont) ?? baseFont
                    attrs[.font] = italicFont(currentFont)
                    result.append(renderInline(inner, baseAttributes: attrs))
                    i = end + 1
                    continue
                }
            }

            if c == "[" {
                if let close = findUnescaped(chars: chars, target: "]", from: i + 1),
                   close + 1 < chars.count, chars[close + 1] == "(",
                   let parenClose = findUnescaped(chars: chars, target: ")", from: close + 2) {
                    flushBuffer()
                    let linkText = String(chars[(i + 1)..<close])
                    let urlText = String(chars[(close + 2)..<parenClose]).trimmingCharacters(in: .whitespaces)
                    var attrs = baseAttributes
                    attrs[.foregroundColor] = NSColor.linkColor
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    if let url = URL(string: urlText) {
                        attrs[.link] = url
                        attrs[.toolTip] = urlText
                    }
                    let rendered = renderInline(linkText, baseAttributes: attrs)
                    result.append(rendered)
                    i = parenClose + 1
                    continue
                }
            }

            buffer.append(c)
            i += 1
        }

        flushBuffer()
        return result
    }

    private func findInlineCodeEnd(chars: [Character], from start: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "`" { return j }
            j += 1
        }
        return nil
    }

    private func findClosingDouble(chars: [Character], marker: Character, from start: Int) -> Int? {
        var j = start
        while j < chars.count - 1 {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == marker, chars[j + 1] == marker { return j }
            j += 1
        }
        return nil
    }

    private func findClosingSingle(chars: [Character], marker: Character, from start: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == marker {
                if j + 1 < chars.count, chars[j + 1] == marker {
                    j += 2
                    continue
                }
                return j
            }
            j += 1
        }
        return nil
    }

    private func findUnescaped(chars: [Character], target: Character, from start: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == target { return j }
            j += 1
        }
        return nil
    }

    // MARK: - Font helpers

    private func boldFont(_ font: NSFont) -> NSFont {
        let manager = NSFontManager.shared
        let result = manager.convert(font, toHaveTrait: .boldFontMask)
        return result
    }

    private func italicFont(_ font: NSFont) -> NSFont {
        let manager = NSFontManager.shared
        let result = manager.convert(font, toHaveTrait: .italicFontMask)
        return result
    }
}
