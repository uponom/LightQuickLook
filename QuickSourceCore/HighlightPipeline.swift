import Foundation

public struct HighlightedChunk: Sendable {
    public let text: String
    public let spans: [TokenSpan]

    public init(text: String, spans: [TokenSpan]) {
        self.text = text
        self.spans = spans
    }
}

public enum HighlightPipeline {
    public static func process(text: String, language: SourceLanguage, targetUTF16Length: Int = 256 * 1_024) -> [HighlightedChunk] {
        let highlighter = HighlighterFactory.make(for: language)
        var chunks: [HighlightedChunk] = []
        var state = LexerState.normal
        for chunk in TextChunker.split(text: text, targetUTF16Length: targetUTF16Length) {
            let result = highlighter.highlight(chunk, state: state)
            chunks.append(HighlightedChunk(text: chunk, spans: result.spans))
            state = result.state
        }
        return chunks
    }
}

public enum TextChunker {
    public static func split(text: String, targetUTF16Length: Int = 256 * 1_024) -> [String] {
        guard !text.isEmpty else { return [""] }
        let nsText = text as NSString
        var chunks: [String] = []
        var location = 0
        while location < nsText.length {
            var length = min(targetUTF16Length, nsText.length - location)
            if location + length < nsText.length {
                let searchStart = max(location, location + length - 8_192)
                let search = nsText.range(of: "\n", options: .backwards, range: NSRange(location: searchStart, length: location + length - searchStart))
                if search.location != NSNotFound { length = search.location + search.length - location }
                if length > 0 {
                    let last = nsText.character(at: location + length - 1)
                    if last >= 0xD800 && last <= 0xDBFF { length -= 1 }
                }
            }
            if length <= 0 { length = min(1, nsText.length - location) }
            chunks.append(nsText.substring(with: NSRange(location: location, length: length)))
            location += length
        }
        return chunks
    }
}
