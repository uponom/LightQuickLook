import Foundation

public struct MarkdownHighlighter: SyntaxHighlighter {
    public init() {}

    public func highlight(_ text: String, state: LexerState = .normal) -> HighlightResult {
        let u = Array(text.utf16)
        var spans: [TokenSpan] = []
        var line = 0
        var carried = state
        while line < u.count {
            let end = lineEnd(in: u, from: line)
            var content = line
            while content < end, isHorizontalSpace(u[content]) { content += 1 }
            if case let .markdownFence(marker, count) = carried {
                var run = 0; while content + run < end, u[content + run] == marker { run += 1 }
                if run >= count { spans.append(TokenSpan(content, end - content, .directive)); carried = .normal }
                else { spans.append(TokenSpan(line, end - line, .code)) }
                line = nextLine(in: u, after: end); continue
            }
            var fenceRun = 0
            if content < end, u[content] == 96 || u[content] == 126 {
                while content + fenceRun < end, u[content + fenceRun] == u[content] { fenceRun += 1 }
            }
            if fenceRun >= 3 {
                spans.append(TokenSpan(content, end - content, .directive)); carried = .markdownFence(marker: u[content], count: fenceRun)
            } else if content < end, u[content] == 35 {
                var count = 0; while content + count < end, u[content + count] == 35, count < 6 { count += 1 }
                if content + count == end || isHorizontalSpace(u[content + count]) { spans.append(TokenSpan(content, end - content, .heading)) }
            } else {
                if content < end, u[content] == 62 { spans.append(TokenSpan(content, 1, .directive)) }
                if content < end, u[content] == 45 || u[content] == 42 || u[content] == 43,
                   content + 1 < end, isHorizontalSpace(u[content + 1]) { spans.append(TokenSpan(content, 1, .directive)) }
                if content < end, isDigit(u[content]) {
                    var j = content; while j < end, isDigit(u[j]) { j += 1 }
                    if j < end, (u[j] == 46 || u[j] == 41), j + 1 < end, isHorizontalSpace(u[j + 1]) { spans.append(TokenSpan(content, j - content + 1, .directive)) }
                }
                var i = content
                while i < end {
                    if u[i] == 96 {
                        let start = i; i += 1; while i < end, u[i] != 96 { i += 1 }; if i < end { i += 1 }
                        spans.append(TokenSpan(start, i - start, .code))
                    } else if u[i] == 91 {
                        let start = i; while i < end, u[i] != 93 { i += 1 }
                        if i + 1 < end, u[i] == 93, u[i + 1] == 40 { i += 2; while i < end, u[i] != 41 { i += 1 }; if i < end { i += 1 }; spans.append(TokenSpan(start, i - start, .link)) }
                        else { i = min(end, start + 1) }
                    } else if u[i] == 42 || u[i] == 95 { spans.append(TokenSpan(i, 1, .directive)); i += 1 }
                    else { i += 1 }
                }
            }
            line = nextLine(in: u, after: end)
        }
        return HighlightResult(spans: validated(spans, length: u.count), state: carried)
    }
}
