import Foundation

public enum SourceLanguage: String, CaseIterable, Sendable {
    case plain, json, yaml, powerShell, bash, terraform, markdown
}

public enum LanguageDetector {
    public static func detect(url: URL, prefix: String = "") -> SourceLanguage {
        switch url.pathExtension.lowercased() {
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "ps1", "psm1", "psd1": return .powerShell
        case "sh", "bash": return .bash
        case "tf", "tfvars", "hcl": return .terraform
        case "md", "markdown": return .markdown
        default:
            let line = prefix.prefix(160).lowercased()
            return line.hasPrefix("#!") && (line.contains("/bash") || line.contains("env bash")) ? .bash : .plain
        }
    }
}

public enum TokenKind: String, CaseIterable, Sendable {
    case plain, comment, string, number, keyword, controlKeyword, literal, variable, property, `operator`, directive, type, support, supportFunction, heading, link, code, punctuation
}

public struct TokenSpan: Equatable, Sendable {
    public let range: NSRange
    public let kind: TokenKind

    public init(_ location: Int, _ length: Int, _ kind: TokenKind) {
        self.range = NSRange(location: location, length: max(0, length))
        self.kind = kind
    }
}

public enum LexerState: Equatable, Sendable {
    case normal
    case blockComment
    case singleQuotedString
    case doubleQuotedString
    case powerShellHereString(quote: UInt16)
    case heredoc(delimiter: String, stripTabs: Bool, language: SourceLanguage)
    case markdownFence(marker: UInt16, count: Int)
    case yamlBlockScalar(indent: Int)
}

public struct HighlightResult: Sendable {
    public let spans: [TokenSpan]
    public let state: LexerState

    public init(spans: [TokenSpan], state: LexerState) {
        self.spans = spans
        self.state = state
    }
}

public protocol SyntaxHighlighter: Sendable {
    func highlight(_ text: String, state: LexerState) -> HighlightResult
}

public enum HighlighterFactory {
    public static func make(for language: SourceLanguage) -> any SyntaxHighlighter {
        switch language {
        case .json: JSONHighlighter()
        case .yaml: YAMLHighlighter()
        case .powerShell: PowerShellHighlighter()
        case .bash: BashHighlighter()
        case .terraform: TerraformHighlighter()
        case .markdown: MarkdownHighlighter()
        case .plain: PlainHighlighter()
        }
    }
}

public struct PlainHighlighter: SyntaxHighlighter {
    public init() {}
    public func highlight(_ text: String, state: LexerState = .normal) -> HighlightResult {
        HighlightResult(spans: [], state: .normal)
    }
}
