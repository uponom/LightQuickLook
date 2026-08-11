import Foundation

public struct YAMLHighlighter: SyntaxHighlighter {
    public init() {}

    public func highlight(_ text: String, state: LexerState = .normal) -> HighlightResult {
        let units = Array(text.utf16)
        var spans: [TokenSpan] = []
        var line = 0
        var carriedState = state
        while line < units.count {
            let end = lineEnd(in: units, from: line)
            var content = line
            var indent = 0
            while content < end, isHorizontalSpace(units[content]) { indent += units[content] == 9 ? 4 : 1; content += 1 }
            if case let .yamlBlockScalar(required) = carriedState {
                if content == end || indent > required {
                    spans.append(TokenSpan(line, end - line, .string))
                    line = nextLine(in: units, after: end); continue
                }
                carriedState = .normal
            }
            if hasPrefix(units, at: content, "---") || hasPrefix(units, at: content, "...") {
                spans.append(TokenSpan(content, min(3, end - content), .directive))
            }
            var i = content
            var keyCandidate = true
            while i < end {
                let start = i
                if units[i] == 35 {
                    spans.append(TokenSpan(i, end - i, .comment)); break
                } else if units[i] == 34 || units[i] == 39 {
                    let quote = units[i]
                    let close = min(end, scanQuoted(units, from: i, quote: quote, escapes: quote == 34))
                    var look = close
                    while look < end, isHorizontalSpace(units[look]) { look += 1 }
                    spans.append(TokenSpan(i, close - i, look < end && units[look] == 58 ? .property : .string)); i = close
                } else if units[i] == 38 || units[i] == 42 || units[i] == 33 {
                    i += 1; while i < end, isIdentifier(units[i]) || units[i] == 46 { i += 1 }
                    spans.append(TokenSpan(start, i - start, .directive))
                } else if units[i] == 124 || units[i] == 62 {
                    i += 1; while i < end, units[i] == 43 || units[i] == 45 || isDigit(units[i]) { i += 1 }
                    spans.append(TokenSpan(start, i - start, .directive)); carriedState = .yamlBlockScalar(indent: indent)
                } else if isDigit(units[i]) || (units[i] == 45 && i + 1 < end && isDigit(units[i + 1])) {
                    i += 1; while i < end, isDigit(units[i]) || units[i] == 46 || units[i] == 95 { i += 1 }
                    spans.append(TokenSpan(start, i - start, .number))
                } else if isASCIIAlpha(units[i]) || units[i] == 95 {
                    i += 1
                    while i < end, units[i] != 58, isIdentifier(units[i]) || units[i] == 46 { i += 1 }
                    var look = i; while look < end, isHorizontalSpace(units[look]) { look += 1 }
                    let word = ascii(units[start..<i]).lowercased()
                    if look < end, units[look] == 58, keyCandidate { spans.append(TokenSpan(start, i - start, .property)) }
                    else if ["true", "false", "yes", "no", "null", "nil", "~", "on", "off"].contains(word) { spans.append(TokenSpan(start, i - start, .literal)) }
                } else { if units[i] == 58 { keyCandidate = false }; i += 1 }
            }
            line = nextLine(in: units, after: end)
        }
        return HighlightResult(spans: validated(spans, length: units.count), state: carriedState)
    }
}
