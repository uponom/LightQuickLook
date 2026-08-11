import Foundation

public struct PowerShellHighlighter: SyntaxHighlighter {
    private static let keywords: Set<String> = ["if", "else", "elseif", "switch", "foreach", "for", "while", "do", "until", "function", "filter", "param", "class", "enum", "return", "break", "continue", "try", "catch", "finally", "throw", "trap", "begin", "process", "end", "data", "dynamicparam", "in"]
    private static let operators: Set<String> = ["-eq", "-ne", "-gt", "-ge", "-lt", "-le", "-like", "-notlike", "-match", "-notmatch", "-contains", "-notcontains", "-in", "-notin", "-and", "-or", "-not", "-xor"]

    public init() {}

    public func highlight(_ text: String, state: LexerState = .normal) -> HighlightResult {
        let u = Array(text.utf16)
        var spans: [TokenSpan] = []
        var i = 0
        var carried = state
        while i < u.count {
            if carried == .blockComment {
                let start = i
                while i < u.count, !hasPrefix(u, at: i, "#>") { i += 1 }
                if i < u.count { i += 2; carried = .normal }
                spans.append(TokenSpan(start, i - start, .comment)); continue
            }
            if case let .powerShellHereString(quote) = carried {
                let start = i
                var lineStart = i
                while lineStart < u.count {
                    let end = lineEnd(in: u, from: lineStart)
                    if lineStart + 1 < end, u[lineStart] == quote, u[lineStart + 1] == 64 {
                        i = lineStart + 2; carried = .normal; break
                    }
                    i = nextLine(in: u, after: end); lineStart = i
                }
                if i >= u.count { i = u.count }
                spans.append(TokenSpan(start, i - start, .string)); continue
            }
            let start = i
            if hasPrefix(u, at: i, "<#") {
                i += 2; carried = .blockComment
                while i < u.count, !hasPrefix(u, at: i, "#>") { i += 1 }
                if i < u.count { i += 2; carried = .normal }
                spans.append(TokenSpan(start, i - start, .comment))
            }
            else if u[i] == 35 {
                let end = lineEnd(in: u, from: i); spans.append(TokenSpan(i, end - i, .comment)); i = end
            } else if u[i] == 64, i + 1 < u.count, u[i + 1] == 39 || u[i + 1] == 34 {
                let quote = u[i + 1]; i += 2; carried = .powerShellHereString(quote: quote)
                spans.append(TokenSpan(start, 2, .directive))
            } else if u[i] == 39 || u[i] == 34 {
                let quote = u[i]; i = scanQuoted(u, from: i, quote: quote, escapes: quote == 34)
                spans.append(TokenSpan(start, i - start, .string))
            } else if u[i] == 36 {
                i += 1
                if i < u.count, u[i] == 123 { i += 1; while i < u.count, u[i] != 125 { i += 1 }; if i < u.count { i += 1 } }
                else { while i < u.count, isIdentifier(u[i]) || u[i] == 63 || u[i] == 36 { i += 1 } }
                spans.append(TokenSpan(start, i - start, .variable))
            } else if u[i] == 45, i + 1 < u.count, isASCIIAlpha(u[i + 1]) {
                i += 1; while i < u.count, isASCIIAlpha(u[i]) || u[i] == 45 { i += 1 }
                let word = ascii(u[start..<i]).lowercased()
                spans.append(TokenSpan(start, i - start, Self.operators.contains(word) ? .operator : .directive))
            } else if isASCIIAlpha(u[i]) {
                i += 1; while i < u.count, isIdentifier(u[i]) { i += 1 }
                if Self.keywords.contains(ascii(u[start..<i]).lowercased()) { spans.append(TokenSpan(start, i - start, .keyword)) }
            } else if isDigit(u[i]) {
                i += 1; while i < u.count, isDigit(u[i]) || u[i] == 46 { i += 1 }
                spans.append(TokenSpan(start, i - start, .number))
            } else { i += 1 }
        }
        return HighlightResult(spans: validated(spans, length: u.count), state: carried)
    }
}
