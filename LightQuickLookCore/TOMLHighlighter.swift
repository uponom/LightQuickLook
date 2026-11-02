import Foundation

public struct TOMLHighlighter: SyntaxHighlighter {
    public init() {}

    public func highlight(
        _ text: String,
        state: LexerState,
        cancellation: HighlightCancellation
    ) -> HighlightResult {
        let units = Array(text.utf16)
        var spans: [TokenSpan] = []
        var index = 0
        var carried = state

        if case let .tomlMultilineString(quote) = carried {
            let continuation = scanMultilineString(
                units,
                from: 0,
                quote: quote,
                cancellation: cancellation
            )
            spans.append(TokenSpan(0, continuation.end, .string))
            index = continuation.end
            if continuation.closed { carried = .normal }
        } else if carried == .singleQuotedString || carried == .doubleQuotedString {
            let quote: UInt16 = carried == .singleQuotedString ? 39 : 34
            let continuation = scanStringContinuation(
                units,
                from: 0,
                quote: quote,
                escapes: quote == 34,
                cancellation: cancellation
            )
            spans.append(TokenSpan(0, continuation.end, .string))
            index = continuation.end
            if continuation.closed { carried = .normal }
        }

        while index < units.count {
            if cancellation.shouldStop(atUTF16Offset: index) { break }
            let start = index

            if isSpace(units[index]) {
                index += 1
            } else if units[index] == 35 {
                index = lineEnd(in: units, from: index, cancellation: cancellation)
                spans.append(TokenSpan(start, index - start, .comment))
            } else if units[index] == 91, isFirstNonWhitespaceOnLine(units, at: index) {
                let header = scanTableHeader(units, from: index, cancellation: cancellation)
                spans.append(TokenSpan(index, header.openingLength, .punctuation))
                if header.contentEnd > header.contentStart {
                    spans.append(TokenSpan(
                        header.contentStart,
                        header.contentEnd - header.contentStart,
                        .heading
                    ))
                }
                if header.closed {
                    spans.append(TokenSpan(header.closingStart, header.openingLength, .punctuation))
                }
                index = header.end
            } else if isTripleQuote(units, at: index) {
                let quote = units[index]
                let string = scanMultilineString(
                    units,
                    from: index + 3,
                    quote: quote,
                    cancellation: cancellation
                )
                index = string.end
                spans.append(TokenSpan(start, index - start, .string))
                if !string.closed { carried = .tomlMultilineString(quote: quote) }
            } else if units[index] == 34 || units[index] == 39 {
                let quote = units[index]
                let end = scanQuoted(
                    units,
                    from: index,
                    quote: quote,
                    escapes: quote == 34,
                    cancellation: cancellation
                )
                let closed = end > index + 1 && units[end - 1] == quote
                let kind: TokenKind = tokenIntroducesKey(units, after: end) ? .property : .string
                spans.append(TokenSpan(start, end - start, kind))
                index = end
                if !closed {
                    carried = quote == 34 ? .doubleQuotedString : .singleQuotedString
                }
            } else if units[index] == 61 {
                spans.append(TokenSpan(index, 1, .operator))
                index += 1
            } else if [91, 93, 123, 125, 44, 46].contains(units[index]) {
                spans.append(TokenSpan(index, 1, .punctuation))
                index += 1
            } else if isNumberStart(units, at: index) {
                index = scanBareValue(
                    units,
                    from: index,
                    cancellation: cancellation
                )
                let value = ascii(units[start..<index]).lowercased()
                let kind: TokenKind = ["inf", "+inf", "-inf", "nan", "+nan", "-nan"].contains(value)
                    ? .literal
                    : .number
                spans.append(TokenSpan(start, index - start, kind))
            } else if isBareKeyCharacter(units[index]) {
                index += 1
                while index < units.count, isBareKeyCharacter(units[index]) {
                    if cancellation.shouldStop(atUTF16Offset: index) { break }
                    index += 1
                }
                let word = ascii(units[start..<index]).lowercased()
                if tokenIntroducesKey(units, after: index) {
                    spans.append(TokenSpan(start, index - start, .property))
                } else if ["true", "false", "inf", "nan"].contains(word) {
                    spans.append(TokenSpan(start, index - start, .literal))
                }
            } else {
                index += 1
            }
        }

        return HighlightResult(
            spans: validated(spans, length: units.count),
            state: carried
        )
    }
}

private extension TOMLHighlighter {
    struct StringScanResult {
        let end: Int
        let closed: Bool
    }

    struct TableHeaderScanResult {
        let openingLength: Int
        let contentStart: Int
        let contentEnd: Int
        let closingStart: Int
        let end: Int
        let closed: Bool
    }

    func scanStringContinuation(
        _ units: [UInt16],
        from start: Int,
        quote: UInt16,
        escapes: Bool,
        cancellation: HighlightCancellation
    ) -> StringScanResult {
        var index = start
        var escaped = false
        while index < units.count {
            if cancellation.shouldStop(atUTF16Offset: index) {
                return StringScanResult(end: index, closed: false)
            }
            let character = units[index]
            index += 1
            if character == quote, !escaped {
                return StringScanResult(end: index, closed: true)
            }
            if escapes, character == 92 { escaped.toggle() } else { escaped = false }
        }
        return StringScanResult(end: units.count, closed: false)
    }

    func scanMultilineString(
        _ units: [UInt16],
        from start: Int,
        quote: UInt16,
        cancellation: HighlightCancellation
    ) -> StringScanResult {
        var index = start
        while index < units.count {
            if cancellation.shouldStop(atUTF16Offset: index) {
                return StringScanResult(end: index, closed: false)
            }
            if index + 2 < units.count,
               units[index] == quote,
               units[index + 1] == quote,
               units[index + 2] == quote,
               (quote == 39 || !isEscaped(units, at: index)) {
                return StringScanResult(end: index + 3, closed: true)
            }
            index += 1
        }
        return StringScanResult(end: units.count, closed: false)
    }

    func scanTableHeader(
        _ units: [UInt16],
        from start: Int,
        cancellation: HighlightCancellation
    ) -> TableHeaderScanResult {
        let openingLength = hasPrefix(units, at: start, "[[") ? 2 : 1
        let rawContentStart = start + openingLength
        let endOfLine = lineEnd(in: units, from: rawContentStart, cancellation: cancellation)
        var index = rawContentStart
        var quote: UInt16 = 0
        var escaped = false

        while index < endOfLine {
            if cancellation.shouldStop(atUTF16Offset: index) { break }
            let character = units[index]
            if quote != 0 {
                if character == quote, !escaped { quote = 0 }
                if quote == 34, character == 92 { escaped.toggle() } else { escaped = false }
                index += 1
                continue
            }
            if character == 34 || character == 39 {
                quote = character
                escaped = false
                index += 1
                continue
            }
            let hasClosing = openingLength == 2
                ? hasPrefix(units, at: index, "]]" )
                : character == 93
            if hasClosing {
                var trimmedStart = rawContentStart
                while trimmedStart < index, isHorizontalSpace(units[trimmedStart]) {
                    trimmedStart += 1
                }
                var trimmedEnd = index
                while trimmedEnd > trimmedStart, isHorizontalSpace(units[trimmedEnd - 1]) {
                    trimmedEnd -= 1
                }
                return TableHeaderScanResult(
                    openingLength: openingLength,
                    contentStart: trimmedStart,
                    contentEnd: trimmedEnd,
                    closingStart: index,
                    end: index + openingLength,
                    closed: true
                )
            }
            index += 1
        }

        return TableHeaderScanResult(
            openingLength: openingLength,
            contentStart: rawContentStart,
            contentEnd: endOfLine,
            closingStart: endOfLine,
            end: endOfLine,
            closed: false
        )
    }

    func tokenIntroducesKey(_ units: [UInt16], after end: Int) -> Bool {
        var look = end
        while look < units.count, isHorizontalSpace(units[look]) { look += 1 }
        return look < units.count && (units[look] == 61 || units[look] == 46)
    }

    func scanBareValue(
        _ units: [UInt16],
        from start: Int,
        cancellation: HighlightCancellation
    ) -> Int {
        var index = start
        while index < units.count {
            if cancellation.shouldStop(atUTF16Offset: index) { break }
            let character = units[index]
            if isSpace(character) || [35, 44, 93, 125].contains(character) { break }
            index += 1
        }
        return index
    }

    func isTripleQuote(_ units: [UInt16], at index: Int) -> Bool {
        guard index + 2 < units.count else { return false }
        let quote = units[index]
        return (quote == 34 || quote == 39)
            && units[index + 1] == quote
            && units[index + 2] == quote
    }

    func isEscaped(_ units: [UInt16], at index: Int) -> Bool {
        var cursor = index
        var backslashes = 0
        while cursor > 0, units[cursor - 1] == 92 {
            backslashes += 1
            cursor -= 1
        }
        return backslashes % 2 == 1
    }

    func isFirstNonWhitespaceOnLine(_ units: [UInt16], at index: Int) -> Bool {
        var cursor = index
        while cursor > 0 {
            let previous = units[cursor - 1]
            if previous == 10 || previous == 13 { break }
            if !isHorizontalSpace(previous) { return false }
            cursor -= 1
        }
        return true
    }

    func isBareKeyCharacter(_ character: UInt16) -> Bool {
        isASCIIAlpha(character) || isDigit(character) || character == 95 || character == 45
    }

    func isNumberStart(_ units: [UInt16], at index: Int) -> Bool {
        if isDigit(units[index]) { return true }
        guard units[index] == 43 || units[index] == 45, index + 1 < units.count else {
            return false
        }
        return isDigit(units[index + 1])
            || hasPrefix(units, at: index + 1, "inf", caseInsensitive: true)
            || hasPrefix(units, at: index + 1, "nan", caseInsensitive: true)
    }
}
