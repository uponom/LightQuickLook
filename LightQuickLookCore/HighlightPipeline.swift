import Foundation

public struct HighlightedChunk: Sendable {
    public let text: String
    public let spans: [TokenSpan]

    public init(text: String, spans: [TokenSpan]) {
        self.text = text
        self.spans = spans
    }
}

public struct HighlightedRangeBatch: Sendable {
    public let range: NSRange
    public let spans: [TokenSpan]

    public init(range: NSRange, spans: [TokenSpan]) {
        self.range = range
        self.spans = spans
    }
}

public struct HighlightedBatchProgress: Sendable {
    public let batch: HighlightedRangeBatch
    public let stateAfter: LexerState

    public init(batch: HighlightedRangeBatch, stateAfter: LexerState) {
        self.batch = batch
        self.stateAfter = stateAfter
    }
}

public enum HighlightPipeline {
    public static func process(text: String, language: SourceLanguage, targetUTF16Length: Int = 256 * 1_024) -> [HighlightedChunk] {
        let highlighter = HighlighterFactory.make(for: language)
        var chunks: [HighlightedChunk] = []
        var state = LexerState.normal
        TextChunker.forEachRange(
            in: text,
            initialTargetUTF16Length: targetUTF16Length,
            subsequentTargetUTF16Length: targetUTF16Length
        ) { source, range in
            let chunk = source.substring(with: range)
            let result = highlighter.highlight(chunk, state: state)
            chunks.append(HighlightedChunk(text: chunk, spans: result.spans))
            state = result.state
        }
        return chunks
    }

    public static func initialBatch(
        text: String,
        language: SourceLanguage,
        targetUTF16Length: Int = PreviewPolicy.initialHighlightUTF16Length,
        cancellation: HighlightCancellation = .never
    ) throws -> HighlightedBatchProgress? {
        guard let range = TextChunker.firstRange(in: text, targetUTF16Length: targetUTF16Length) else {
            return nil
        }
        if cancellation.isCancelled { throw CancellationError() }

        let highlighter = HighlighterFactory.make(for: language)
        let result = highlighter.highlight(
            (text as NSString).substring(with: range),
            state: .normal,
            cancellation: cancellation
        )
        if cancellation.isCancelled { throw CancellationError() }
        let globalSpans = result.spans.map {
            TokenSpan(range.location + $0.range.location, $0.range.length, $0.kind)
        }
        return HighlightedBatchProgress(
            batch: HighlightedRangeBatch(range: range, spans: globalSpans),
            stateAfter: result.state
        )
    }

    public static func enumerateBatches(
        text: String,
        language: SourceLanguage,
        initialTargetUTF16Length: Int = PreviewPolicy.initialHighlightUTF16Length,
        subsequentTargetUTF16Length: Int = PreviewPolicy.highlightChunkUTF16Length,
        cancellation: HighlightCancellation = .never,
        body: (HighlightedRangeBatch) throws -> Void
    ) throws {
        let highlighter = HighlighterFactory.make(for: language)
        var state = LexerState.normal
        try TextChunker.forEachRange(
            in: text,
            initialTargetUTF16Length: initialTargetUTF16Length,
            subsequentTargetUTF16Length: subsequentTargetUTF16Length
        ) { source, range in
            if cancellation.isCancelled { throw CancellationError() }
            let chunk = source.substring(with: range)
            let result = highlighter.highlight(chunk, state: state, cancellation: cancellation)
            if cancellation.isCancelled { throw CancellationError() }
            state = result.state
            let globalSpans = result.spans.map {
                TokenSpan(range.location + $0.range.location, $0.range.length, $0.kind)
            }
            try body(HighlightedRangeBatch(range: range, spans: globalSpans))
        }
    }

    public static func enumerateBatchesAsync(
        text: String,
        language: SourceLanguage,
        startingAtUTF16Location: Int = 0,
        initialState: LexerState = .normal,
        initialTargetUTF16Length: Int = PreviewPolicy.initialHighlightUTF16Length,
        subsequentTargetUTF16Length: Int = PreviewPolicy.highlightChunkUTF16Length,
        cancellation: HighlightCancellation = .never,
        body: @escaping @Sendable (HighlightedRangeBatch) async throws -> Void
    ) async throws {
        let highlighter = HighlighterFactory.make(for: language)
        let source = text as NSString
        let ranges = TextChunker.ranges(
            in: text,
            startingAtUTF16Location: startingAtUTF16Location,
            initialTargetUTF16Length: initialTargetUTF16Length,
            subsequentTargetUTF16Length: subsequentTargetUTF16Length
        )
        var state = initialState
        for range in ranges {
            if cancellation.isCancelled { throw CancellationError() }
            let chunk = source.substring(with: range)
            let result = highlighter.highlight(chunk, state: state, cancellation: cancellation)
            if cancellation.isCancelled { throw CancellationError() }
            state = result.state
            let globalSpans = result.spans.map {
                TokenSpan(range.location + $0.range.location, $0.range.length, $0.kind)
            }
            try await body(HighlightedRangeBatch(range: range, spans: globalSpans))
        }
    }
}

public enum TextChunker {
    public static func split(text: String, targetUTF16Length: Int = 256 * 1_024) -> [String] {
        var chunks: [String] = []
        forEachRange(
            in: text,
            initialTargetUTF16Length: targetUTF16Length,
            subsequentTargetUTF16Length: targetUTF16Length
        ) { source, range in
            chunks.append(source.substring(with: range))
        }
        return chunks
    }

    public static func firstRange(in text: String, targetUTF16Length: Int) -> NSRange? {
        let source = text as NSString
        guard source.length > 0 else { return nil }
        return nextRange(in: source, location: 0, targetUTF16Length: targetUTF16Length)
    }

    public static func ranges(
        in text: String,
        startingAtUTF16Location: Int = 0,
        initialTargetUTF16Length: Int,
        subsequentTargetUTF16Length: Int
    ) -> [NSRange] {
        var result: [NSRange] = []
        forEachRange(
            in: text,
            startingAtUTF16Location: startingAtUTF16Location,
            initialTargetUTF16Length: initialTargetUTF16Length,
            subsequentTargetUTF16Length: subsequentTargetUTF16Length
        ) { _, range in
            result.append(range)
        }
        return result
    }

    public static func forEachRange(
        in text: String,
        startingAtUTF16Location: Int = 0,
        initialTargetUTF16Length: Int,
        subsequentTargetUTF16Length: Int,
        body: (NSString, NSRange) throws -> Void
    ) rethrows {
        let nsText = text as NSString
        let startingLocation = min(max(0, startingAtUTF16Location), nsText.length)
        guard nsText.length > 0 else {
            if startingLocation == 0 {
                try body(nsText, NSRange(location: 0, length: 0))
            }
            return
        }
        guard startingLocation < nsText.length else { return }

        var location = startingLocation
        var isFirstRange = true
        while location < nsText.length {
            let requestedLength = isFirstRange ? initialTargetUTF16Length : subsequentTargetUTF16Length
            let range = nextRange(
                in: nsText,
                location: location,
                targetUTF16Length: requestedLength
            )
            try body(nsText, range)
            location = NSMaxRange(range)
            isFirstRange = false
        }
    }

    private static func nextRange(
        in source: NSString,
        location: Int,
        targetUTF16Length: Int
    ) -> NSRange {
        let safeTargetLength = max(1, targetUTF16Length)
        var length = min(safeTargetLength, source.length - location)
        if location + length < source.length {
            let searchStart = max(location, location + length - 8_192)
            let search = source.range(
                of: "\n",
                options: .backwards,
                range: NSRange(
                    location: searchStart,
                    length: location + length - searchStart
                )
            )
            if search.location != NSNotFound {
                length = search.location + search.length - location
            }
            if length > 0 {
                let last = source.character(at: location + length - 1)
                if last >= 0xD800 && last <= 0xDBFF {
                    length = length == 1 ? min(2, source.length - location) : length - 1
                }
            }
        }
        if length <= 0 { length = min(1, source.length - location) }
        return NSRange(location: location, length: length)
    }
}
