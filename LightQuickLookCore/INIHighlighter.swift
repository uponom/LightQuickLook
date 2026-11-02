import Foundation

public struct INIHighlighter: SyntaxHighlighter {
    public init() {}

    public func highlight(
        _ text: String,
        state: LexerState,
        cancellation: HighlightCancellation
    ) -> HighlightResult {
        let units = Array(text.utf16)
        var spans: [TokenSpan] = []
        var lineStart = 0

        while lineStart < units.count {
            if cancellation.shouldStop(atUTF16Offset: lineStart) { break }
            let end = lineEnd(in: units, from: lineStart, cancellation: cancellation)
            if cancellation.isCancelled { break }
            var content = lineStart
            while content < end, isHorizontalSpace(units[content]) { content += 1 }

            if content < end, units[content] == 35 || units[content] == 59 {
                spans.append(TokenSpan(content, end - content, .comment))
            } else if content < end, units[content] == 91 {
                highlightSection(
                    units,
                    contentStart: content,
                    lineEnd: end,
                    cancellation: cancellation,
                    spans: &spans
                )
            } else if let separator = assignmentSeparator(
                units,
                from: content,
                to: end,
                cancellation: cancellation
            ) {
                var keyEnd = separator
                while keyEnd > content, isHorizontalSpace(units[keyEnd - 1]) { keyEnd -= 1 }
                if keyEnd > content {
                    spans.append(TokenSpan(content, keyEnd - content, .property))
                }
                spans.append(TokenSpan(separator, 1, .operator))
                highlightValue(
                    units,
                    from: separator + 1,
                    to: end,
                    cancellation: cancellation,
                    spans: &spans
                )
            }

            lineStart = nextLine(in: units, after: end)
        }

        return HighlightResult(
            spans: validated(spans, length: units.count),
            state: .normal
        )
    }
}

private extension INIHighlighter {
    func highlightSection(
        _ units: [UInt16],
        contentStart: Int,
        lineEnd: Int,
        cancellation: HighlightCancellation,
        spans: inout [TokenSpan]
    ) {
        var closing = contentStart + 1
        while closing < lineEnd, units[closing] != 93 {
            if cancellation.shouldStop(atUTF16Offset: closing) { return }
            closing += 1
        }
        spans.append(TokenSpan(contentStart, 1, .punctuation))
        if closing > contentStart + 1 {
            spans.append(TokenSpan(contentStart + 1, closing - contentStart - 1, .heading))
        }
        guard closing < lineEnd else { return }
        spans.append(TokenSpan(closing, 1, .punctuation))

        var trailing = closing + 1
        while trailing < lineEnd, isHorizontalSpace(units[trailing]) { trailing += 1 }
        if trailing < lineEnd, units[trailing] == 35 || units[trailing] == 59 {
            spans.append(TokenSpan(trailing, lineEnd - trailing, .comment))
        }
    }

    func assignmentSeparator(
        _ units: [UInt16],
        from start: Int,
        to end: Int,
        cancellation: HighlightCancellation
    ) -> Int? {
        var index = start
        var quote: UInt16 = 0
        var escaped = false
        while index < end {
            if cancellation.shouldStop(atUTF16Offset: index) { return nil }
            let character = units[index]
            if quote != 0 {
                if character == quote, !escaped { quote = 0 }
                if quote == 34, character == 92 { escaped.toggle() } else { escaped = false }
            } else if character == 34 || character == 39 {
                quote = character
                escaped = false
            } else if character == 61 || character == 58 {
                return index
            } else if character == 35 || character == 59 {
                return nil
            }
            index += 1
        }
        return nil
    }

    func highlightValue(
        _ units: [UInt16],
        from start: Int,
        to end: Int,
        cancellation: HighlightCancellation,
        spans: inout [TokenSpan]
    ) {
        var valueStart = start
        while valueStart < end, isHorizontalSpace(units[valueStart]) { valueStart += 1 }

        var commentStart: Int?
        var index = valueStart
        var quote: UInt16 = 0
        var escaped = false
        while index < end {
            if cancellation.shouldStop(atUTF16Offset: index) { return }
            let character = units[index]
            if quote != 0 {
                if character == quote, !escaped { quote = 0 }
                if quote == 34, character == 92 { escaped.toggle() } else { escaped = false }
            } else if character == 34 || character == 39 {
                quote = character
                escaped = false
            } else if (character == 35 || character == 59),
                      index == valueStart || isHorizontalSpace(units[index - 1]) {
                commentStart = index
                break
            }
            index += 1
        }

        var valueEnd = commentStart ?? end
        while valueEnd > valueStart, isHorizontalSpace(units[valueEnd - 1]) { valueEnd -= 1 }
        if valueEnd > valueStart {
            let value = ascii(units[valueStart..<valueEnd])
            spans.append(TokenSpan(valueStart, valueEnd - valueStart, valueKind(value)))
        }
        if let commentStart {
            spans.append(TokenSpan(commentStart, end - commentStart, .comment))
        }
    }

    func valueKind(_ value: String) -> TokenKind {
        let lower = value.lowercased()
        if ["true", "false", "yes", "no", "on", "off", "null", "none"].contains(lower) {
            return .literal
        }
        if Double(value.replacingOccurrences(of: "_", with: "")) != nil {
            return .number
        }
        return .string
    }
}
