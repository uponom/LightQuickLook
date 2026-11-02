import Foundation

public struct PowerShellHighlighter: SyntaxHighlighter {
    private static let keywords: Set<String> = ["if", "else", "elseif", "switch", "foreach", "for", "while", "do", "until", "function", "filter", "param", "class", "enum", "return", "break", "continue", "try", "catch", "finally", "throw", "trap", "begin", "process", "end", "data", "dynamicparam", "in"]
    private static let operators: Set<String> = ["-eq", "-ne", "-gt", "-ge", "-lt", "-le", "-like", "-notlike", "-match", "-notmatch", "-contains", "-notcontains", "-in", "-notin", "-and", "-or", "-not", "-xor"]

    public init() {}

    public func highlight(
        _ text: String,
        state: LexerState,
        cancellation: HighlightCancellation
    ) -> HighlightResult {
        let u = Array(text.utf16)
        var spans: [TokenSpan] = []
        var i = 0
        var carried = state
        var noClosingTypeBracketBefore = 0
        while i < u.count {
            if cancellation.shouldStop(atUTF16Offset: i) { break }
            if carried == .blockComment {
                let start = i
                while i < u.count, !hasPrefix(u, at: i, "#>") {
                    if cancellation.shouldStop(atUTF16Offset: i) { break }
                    i += 1
                }
                if cancellation.isCancelled { break }
                if i < u.count { i += 2; carried = .normal }
                spans.append(TokenSpan(start, i - start, .comment)); continue
            }
            if case let .powerShellHereString(quote) = carried {
                let start = i
                var lineStart = i
                while lineStart < u.count {
                    let end = lineEnd(in: u, from: lineStart, cancellation: cancellation)
                    if cancellation.isCancelled { break }
                    if lineStart + 1 < end, u[lineStart] == quote, u[lineStart + 1] == 64 {
                        i = lineStart + 2; carried = .normal; break
                    }
                    i = nextLine(in: u, after: end); lineStart = i
                }
                if cancellation.isCancelled { break }
                if i >= u.count { i = u.count }
                spans.append(TokenSpan(start, i - start, .string)); continue
            }
            let start = i
            if hasPrefix(u, at: i, "<#") {
                i += 2; carried = .blockComment
                while i < u.count, !hasPrefix(u, at: i, "#>") {
                    if cancellation.shouldStop(atUTF16Offset: i) { break }
                    i += 1
                }
                if cancellation.isCancelled { break }
                if i < u.count { i += 2; carried = .normal }
                spans.append(TokenSpan(start, i - start, .comment))
            }
            else if u[i] == 35 {
                let end = lineEnd(in: u, from: i, cancellation: cancellation)
                if cancellation.isCancelled { break }
                spans.append(TokenSpan(i, end - i, .comment)); i = end
            } else if u[i] == 64, i + 1 < u.count, u[i + 1] == 39 || u[i + 1] == 34 {
                let quote = u[i + 1]; i += 2; carried = .powerShellHereString(quote: quote)
                spans.append(TokenSpan(start, 2, .directive))
            } else if u[i] == 39 || u[i] == 34 {
                let quote = u[i]
                i = scanPowerShellQuoted(u, from: i, quote: quote, cancellation: cancellation)
                if cancellation.isCancelled { break }
                spans.append(TokenSpan(start, i - start, .string))
                if quote == 34 {
                    appendInterpolatedVariables(
                        in: u,
                        from: start + 1,
                        to: max(start + 1, i - 1),
                        cancellation: cancellation,
                        into: &spans
                    )
                }
            } else if u[i] == 36 {
                i = scanVariable(u, from: i, cancellation: cancellation)
                spans.append(TokenSpan(start, i - start, .variable))
            } else if u[i] == 91 {
                if i < noClosingTypeBracketBefore {
                    i += 1
                } else {
                    let end = lineEnd(in: u, from: i, cancellation: cancellation)
                    if cancellation.isCancelled { break }
                    if let close = closingTypeBracket(
                        in: u,
                        from: i,
                        before: end,
                        cancellation: cancellation
                    ) {
                        appendTypeNames(
                            in: u,
                            from: i + 1,
                            to: close,
                            cancellation: cancellation,
                            into: &spans
                        )
                        i = close + 1
                    } else {
                        // There is no closing bracket in the rest of this line,
                        // so retrying the same scan for every later '[' would be O(n²).
                        noClosingTypeBracketBefore = end
                        i += 1
                    }
                }
            } else if u[i] == 45, i + 1 < u.count, isASCIIAlpha(u[i + 1]) {
                i += 1; while i < u.count, isASCIIAlpha(u[i]) || u[i] == 45 { i += 1 }
                let word = ascii(u[start..<i]).lowercased()
                spans.append(TokenSpan(start, i - start, Self.operators.contains(word) ? .operator : .directive))
            } else if isASCIIAlpha(u[i]) {
                i += 1; while i < u.count, isIdentifier(u[i]) { i += 1 }
                let word = ascii(u[start..<i]).lowercased()
                if Self.keywords.contains(word) {
                    // keyword.control.powershell is more specific than the
                    // generic 2026 keyword rule and therefore retains the
                    // inherited Dark+/Light+ control-flow color.
                    spans.append(TokenSpan(start, i - start, .controlKeyword))
                } else if word.contains("-") {
                    // The built-in VS Code PowerShell grammar classifies
                    // Verb-Noun commands as support.function.powershell.
                    spans.append(TokenSpan(start, i - start, .supportFunction))
                }
            } else if isDigit(u[i]) {
                i += 1; while i < u.count, isDigit(u[i]) || u[i] == 46 { i += 1 }
                spans.append(TokenSpan(start, i - start, .number))
            } else { i += 1 }
        }
        return HighlightResult(spans: validated(spans, length: u.count), state: carried)
    }

    private func scanPowerShellQuoted(
        _ units: [UInt16],
        from start: Int,
        quote: UInt16,
        cancellation: HighlightCancellation
    ) -> Int {
        var cursor = start + 1
        while cursor < units.count {
            if cancellation.shouldStop(atUTF16Offset: cursor) { return cursor }
            if units[cursor] == 96 { // PowerShell's backtick escape
                cursor = min(units.count, cursor + 2)
            } else if units[cursor] == quote {
                if quote == 39, cursor + 1 < units.count, units[cursor + 1] == quote {
                    cursor += 2
                } else {
                    return cursor + 1
                }
            } else {
                cursor += 1
            }
        }
        return units.count
    }

    private func scanVariable(
        _ units: [UInt16],
        from start: Int,
        cancellation: HighlightCancellation
    ) -> Int {
        var cursor = start + 1
        if cursor < units.count, units[cursor] == 123 {
            cursor += 1
            while cursor < units.count, units[cursor] != 125 {
                if cancellation.shouldStop(atUTF16Offset: cursor) { return cursor }
                cursor += 1
            }
            if cursor < units.count { cursor += 1 }
        } else {
            while cursor < units.count, isIdentifier(units[cursor]) || units[cursor] == 63 || units[cursor] == 36 { cursor += 1 }
        }
        return cursor
    }

    private func appendInterpolatedVariables(
        in units: [UInt16],
        from start: Int,
        to end: Int,
        cancellation: HighlightCancellation,
        into spans: inout [TokenSpan]
    ) {
        var cursor = start
        while cursor < end {
            if cancellation.shouldStop(atUTF16Offset: cursor) { return }
            if units[cursor] == 96 {
                cursor = min(end, cursor + 2)
            } else if units[cursor] == 36 {
                let variableEnd = min(end, scanVariable(units, from: cursor, cancellation: cancellation))
                spans.append(TokenSpan(cursor, variableEnd - cursor, .support))
                cursor = max(cursor + 1, variableEnd)
            } else {
                cursor += 1
            }
        }
    }

    private func closingTypeBracket(
        in units: [UInt16],
        from start: Int,
        before end: Int,
        cancellation: HighlightCancellation
    ) -> Int? {
        var cursor = start + 1
        while cursor < end {
            if cancellation.shouldStop(atUTF16Offset: cursor) { return nil }
            if units[cursor] == 93 { return cursor }
            cursor += 1
        }
        return nil
    }

    private func appendTypeNames(
        in units: [UInt16],
        from start: Int,
        to end: Int,
        cancellation: HighlightCancellation,
        into spans: inout [TokenSpan]
    ) {
        var cursor = start
        while cursor < end {
            if cancellation.shouldStop(atUTF16Offset: cursor) { return }
            guard isASCIIAlpha(units[cursor]) || units[cursor] == 95 else {
                cursor += 1
                continue
            }
            let nameStart = cursor
            while cursor < end,
                  isASCIIAlpha(units[cursor]) || isDigit(units[cursor]) || units[cursor] == 95 || units[cursor] == 46 {
                cursor += 1
            }
            spans.append(TokenSpan(nameStart, cursor - nameStart, .type))
        }
    }
}
