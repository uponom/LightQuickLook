import Foundation

public struct JSONHighlighter: SyntaxHighlighter {
    public init() {}

    public func highlight(_ text: String, state: LexerState = .normal) -> HighlightResult {
        var s = UTF16Scanner(text)
        var spans: [TokenSpan] = []
        var carried = state
        if carried == .doubleQuotedString {
            let start = s.index
            var escaped = false
            while !s.isAtEnd {
                let character = s.current
                s.advance()
                if character == 34, !escaped { carried = .normal; break }
                if character == 92 { escaped.toggle() } else { escaped = false }
            }
            spans.append(TokenSpan(start, s.index - start, .string))
        }
        while !s.isAtEnd {
            let start = s.index
            switch s.current {
            case 34:
                let end = scanQuoted(s.units, from: start, quote: 34)
                var look = end
                while look < s.units.count, isSpace(s.units[look]) { look += 1 }
                spans.append(TokenSpan(start, end - start, look < s.units.count && s.units[look] == 58 ? .property : .string))
                if end == s.units.count, (end == start + 1 || s.units[end - 1] != 34) { carried = .doubleQuotedString }
                s.index = end
            case 45, 48...57:
                s.advance()
                while !s.isAtEnd, isDigit(s.current) || s.current == 46 || s.current == 69 || s.current == 101 || s.current == 43 || s.current == 45 { s.advance() }
                spans.append(TokenSpan(start, s.index - start, .number))
            case 116 where hasPrefix(s.units, at: start, "true"), 102 where hasPrefix(s.units, at: start, "false"), 110 where hasPrefix(s.units, at: start, "null"):
                while !s.isAtEnd, isASCIIAlpha(s.current) { s.advance() }
                spans.append(TokenSpan(start, s.index - start, .literal))
            case 123, 125, 91, 93, 44, 58:
                spans.append(TokenSpan(start, 1, .punctuation)); s.advance()
            default: s.advance()
            }
        }
        return HighlightResult(spans: spans, state: carried)
    }
}
