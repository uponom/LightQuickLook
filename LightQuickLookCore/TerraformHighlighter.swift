import Foundation

public struct TerraformHighlighter: SyntaxHighlighter {
    private static let keywords: Set<String> = ["terraform", "provider", "resource", "data", "variable", "locals", "module", "output", "moved", "import", "check"]
    public init() {}

    public func highlight(_ text: String, state: LexerState = .normal) -> HighlightResult {
        let u = Array(text.utf16)
        var spans: [TokenSpan] = [], i = 0
        var carried = state
        if case let .heredoc(delimiter, stripTabs, .terraform) = carried {
            let target = Array(delimiter.utf16)
            while i < u.count {
                let start = i, end = lineEnd(in: u, from: i)
                var compare = start; if stripTabs { while compare < end, isHorizontalSpace(u[compare]) { compare += 1 } }
                spans.append(TokenSpan(start, end - start, .string)); i = nextLine(in: u, after: end)
                if slice(u, from: compare, to: end, equals: target) { carried = .normal; break }
            }
        }
        while i < u.count {
            let start = i
            if carried == .blockComment {
                while i < u.count, !hasPrefix(u, at: i, "*/") { i += 1 }
                if i < u.count { i += 2; carried = .normal }
                spans.append(TokenSpan(start, i - start, .comment))
            } else if hasPrefix(u, at: i, "/*") {
                i += 2; carried = .blockComment
                while i < u.count, !hasPrefix(u, at: i, "*/") { i += 1 }
                if i < u.count { i += 2; carried = .normal }
                spans.append(TokenSpan(start, i - start, .comment))
            } else if u[i] == 35 || hasPrefix(u, at: i, "//") {
                i = lineEnd(in: u, from: i); spans.append(TokenSpan(start, i - start, .comment))
            } else if u[i] == 34 {
                i = scanQuoted(u, from: i, quote: 34); spans.append(TokenSpan(start, i - start, .string))
            } else if u[i] == 60, i + 1 < u.count, u[i + 1] == 60 {
                i += 2; var strip = false
                if i < u.count, u[i] == 45 { strip = true; i += 1 }
                while i < u.count, isHorizontalSpace(u[i]) { i += 1 }
                let ds = i; while i < u.count, isIdentifier(u[i]) { i += 1 }
                let delimiter = ascii(u[ds..<i]); spans.append(TokenSpan(start, i - start, .directive))
                if !delimiter.isEmpty {
                    carried = .heredoc(delimiter: delimiter, stripTabs: strip, language: .terraform)
                    i = nextLine(in: u, after: lineEnd(in: u, from: i))
                    let target = Array(delimiter.utf16)
                    while i < u.count {
                        let bodyStart = i, bodyEnd = lineEnd(in: u, from: i)
                        var compare = bodyStart
                        if strip { while compare < bodyEnd, isHorizontalSpace(u[compare]) { compare += 1 } }
                        spans.append(TokenSpan(bodyStart, bodyEnd - bodyStart, .string))
                        i = nextLine(in: u, after: bodyEnd)
                        if slice(u, from: compare, to: bodyEnd, equals: target) { carried = .normal; break }
                    }
                }
            } else if isDigit(u[i]) || (u[i] == 45 && i + 1 < u.count && isDigit(u[i + 1])) {
                i += 1; while i < u.count, isDigit(u[i]) || u[i] == 46 { i += 1 }
                spans.append(TokenSpan(start, i - start, .number))
            } else if isASCIIAlpha(u[i]) || u[i] == 95 {
                i += 1; while i < u.count, isIdentifier(u[i]) { i += 1 }
                var look = i; while look < u.count, isHorizontalSpace(u[look]) { look += 1 }
                let word = ascii(u[start..<i]).lowercased()
                let kind: TokenKind? = Self.keywords.contains(word) ? .keyword : (["true", "false", "null"].contains(word) ? .literal : (look < u.count && u[look] == 61 ? .property : nil))
                if let kind { spans.append(TokenSpan(start, i - start, kind)) }
            } else if hasPrefix(u, at: i, "${") || hasPrefix(u, at: i, "%{") {
                i += 2; spans.append(TokenSpan(start, 2, .directive))
            } else if [61, 43, 45, 42, 47, 33, 60, 62, 63, 58].contains(u[i]) {
                i += 1; spans.append(TokenSpan(start, 1, .operator))
            } else if [123, 125, 91, 93, 40, 41, 44].contains(u[i]) {
                i += 1; spans.append(TokenSpan(start, 1, .punctuation))
            } else { i += 1 }
        }
        return HighlightResult(spans: validated(spans, length: u.count), state: carried)
    }
}
