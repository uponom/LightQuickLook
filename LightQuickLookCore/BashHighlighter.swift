import Foundation

public struct BashHighlighter: SyntaxHighlighter {
    private static let keywords: Set<String> = ["if", "then", "elif", "else", "fi", "for", "while", "until", "do", "done", "case", "esac", "in", "function", "select", "time", "coproc"]
    public init() {}

    public func highlight(_ text: String, state: LexerState = .normal) -> HighlightResult {
        let u = Array(text.utf16)
        var spans: [TokenSpan] = []
        var i = 0
        var carried = state
        if case let .heredoc(delimiter, stripTabs, .bash) = carried {
            let target = Array(delimiter.utf16)
            while i < u.count {
                let start = i, end = lineEnd(in: u, from: i)
                var compare = start
                if stripTabs { while compare < end, u[compare] == 9 { compare += 1 } }
                spans.append(TokenSpan(start, end - start, .string))
                i = nextLine(in: u, after: end)
                if slice(u, from: compare, to: end, equals: target) { carried = .normal; break }
            }
        }
        while i < u.count {
            let start = i
            if i == 0, hasPrefix(u, at: i, "#!") {
                i = lineEnd(in: u, from: i); spans.append(TokenSpan(start, i - start, .directive))
            } else if u[i] == 35 {
                i = lineEnd(in: u, from: i); spans.append(TokenSpan(start, i - start, .comment))
            } else if u[i] == 39 || u[i] == 34 || (u[i] == 36 && i + 1 < u.count && u[i + 1] == 39) {
                let quoteIndex = u[i] == 36 ? i + 1 : i, quote = u[quoteIndex]
                i = scanQuoted(u, from: quoteIndex, quote: quote, escapes: quote != 39)
                spans.append(TokenSpan(start, i - start, .string))
            } else if u[i] == 36 {
                i += 1
                if i < u.count, u[i] == 123 { i += 1; while i < u.count, u[i] != 125 { i += 1 }; if i < u.count { i += 1 } }
                else if i < u.count, u[i] == 40 { var depth = 1; i += 1; while i < u.count && depth > 0 { if u[i] == 40 { depth += 1 }; if u[i] == 41 { depth -= 1 }; i += 1 } }
                else { while i < u.count, isIdentifier(u[i]) || u[i] == 63 || u[i] == 36 || u[i] == 64 || u[i] == 42 { i += 1 } }
                spans.append(TokenSpan(start, i - start, .variable))
            } else if u[i] == 60, i + 1 < u.count, u[i + 1] == 60 {
                i += 2; var stripTabs = false
                if i < u.count, u[i] == 45 { stripTabs = true; i += 1 }
                while i < u.count, isHorizontalSpace(u[i]) { i += 1 }
                let quote: UInt16? = i < u.count && (u[i] == 39 || u[i] == 34) ? u[i] : nil
                if quote != nil { i += 1 }
                let delimiterStart = i
                while i < u.count, isIdentifier(u[i]) { i += 1 }
                let delimiter = ascii(u[delimiterStart..<i])
                if quote != nil, i < u.count, u[i] == quote { i += 1 }
                spans.append(TokenSpan(start, i - start, .directive))
                if !delimiter.isEmpty {
                    carried = .heredoc(delimiter: delimiter, stripTabs: stripTabs, language: .bash)
                    i = nextLine(in: u, after: lineEnd(in: u, from: i))
                    let target = Array(delimiter.utf16)
                    while i < u.count {
                        let bodyStart = i, bodyEnd = lineEnd(in: u, from: i)
                        var compare = bodyStart
                        if stripTabs { while compare < bodyEnd, u[compare] == 9 { compare += 1 } }
                        spans.append(TokenSpan(bodyStart, bodyEnd - bodyStart, .string))
                        i = nextLine(in: u, after: bodyEnd)
                        if slice(u, from: compare, to: bodyEnd, equals: target) { carried = .normal; break }
                    }
                }
            } else if isASCIIAlpha(u[i]) || u[i] == 95 {
                i += 1; while i < u.count, isIdentifier(u[i]) { i += 1 }
                if Self.keywords.contains(ascii(u[start..<i])) { spans.append(TokenSpan(start, i - start, .keyword)) }
            } else if [124, 38, 59, 60, 62].contains(u[i]) {
                i += 1; if i < u.count, u[i] == u[start] { i += 1 }
                spans.append(TokenSpan(start, i - start, .operator))
            } else { i += 1 }
        }
        return HighlightResult(spans: validated(spans, length: u.count), state: carried)
    }
}
