import Foundation
import XCTest
@testable import LightQuickLookCore

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var checks = 0

    var checkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return checks
    }

    func cancelAfterFirstCheck() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        checks += 1
        return checks > 1
    }
}

private actor HighlightBatchCollector {
    private var batches: [HighlightedRangeBatch] = []

    func append(_ batch: HighlightedRangeBatch) {
        batches.append(batch)
    }

    func collected() -> [HighlightedRangeBatch] { batches }
}

final class HighlighterTests: XCTestCase {
    private func tokenTexts(_ source: String, _ result: HighlightResult, kind: TokenKind) -> [String] {
        let text = source as NSString
        return result.spans.filter { $0.kind == kind }.map { text.substring(with: $0.range) }
    }

    private func assertValidRanges(_ source: String, _ result: HighlightResult, file: StaticString = #filePath, line: UInt = #line) {
        let length = (source as NSString).length
        for span in result.spans {
            XCTAssertGreaterThanOrEqual(span.range.location, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(span.range.length, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(span.range.location, length, file: file, line: line)
            if span.range.location >= 0, span.range.location <= length {
                XCTAssertLessThanOrEqual(span.range.length, length - span.range.location, file: file, line: line)
            }
        }
    }

    func testJSONHighlightsKeysValuesAndUnicodeRanges() {
        let source = "😀 {\"ключ\": \"Русский äöü\", \"n\": -12.5, \"ok\": true, \"x\": null}"
        let result = JSONHighlighter().highlight(source, state: .normal)
        assertValidRanges(source, result)
        XCTAssertTrue(tokenTexts(source, result, kind: .property).contains("\"ключ\""))
        XCTAssertEqual(tokenTexts(source, result, kind: .number), ["-12.5"])
        XCTAssertTrue(tokenTexts(source, result, kind: .literal).contains("true"))
    }

    func testJSONLinesUsesJSONDetectionAndHighlighting() {
        let source = "{\"name\":\"alpha\",\"enabled\":true}\n{\"name\":\"beta\",\"enabled\":false}\n"
        let language = LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/sample.jsonl"))
        let result = HighlighterFactory.make(for: language).highlight(source, state: .normal)

        XCTAssertEqual(language, .json)
        assertValidRanges(source, result)
        XCTAssertEqual(tokenTexts(source, result, kind: .property), [
            "\"name\"", "\"enabled\"", "\"name\"", "\"enabled\"",
        ])
        XCTAssertEqual(tokenTexts(source, result, kind: .literal), ["true", "false"])
        XCTAssertEqual(result.state, .normal)
    }

    func testJSONCarriesAStringAcrossProcessingChunks() {
        let first = JSONHighlighter().highlight("{\"value\": \"unterminated", state: .normal)
        XCTAssertEqual(first.state, .doubleQuotedString)
        let secondSource = " continuation 😀\", \"ok\": true}"
        let second = JSONHighlighter().highlight(secondSource, state: first.state)
        assertValidRanges(secondSource, second)
        XCTAssertEqual(second.state, .normal)
        XCTAssertTrue(tokenTexts(secondSource, second, kind: .string).contains(" continuation 😀\""))
    }

    func testYAMLHighlightsCommentsKeysDirectivesAndBlockState() {
        let source = "name: \"# not comment 😀\" # comment\nenabled: true\ntext: |\n  Русский\n"
        let result = YAMLHighlighter().highlight(source, state: .normal)
        assertValidRanges(source, result)
        XCTAssertTrue(tokenTexts(source, result, kind: .property).contains("name"))
        XCTAssertEqual(tokenTexts(source, result, kind: .comment), ["# comment"])
        XCTAssertTrue(tokenTexts(source, result, kind: .directive).contains("|"))
    }

    func testPowerShellHighlightsPriorityConstructsAndCarriesState() {
        let source = "if ($env:PATH -match 'bin') { # Русский 😀\n  Write-Output \"ok\"\n}\n<# open"
        let result = PowerShellHighlighter().highlight(source, state: .normal)
        assertValidRanges(source, result)
        XCTAssertTrue(tokenTexts(source, result, kind: .controlKeyword).contains("if"))
        XCTAssertTrue(tokenTexts(source, result, kind: .variable).contains("$env:PATH"))
        XCTAssertTrue(tokenTexts(source, result, kind: .operator).contains("-match"))
        XCTAssertEqual(result.state, .blockComment)
        let continued = PowerShellHighlighter().highlight(" continued #> return", state: result.state)
        XCTAssertEqual(continued.state, .normal)
        XCTAssertTrue(tokenTexts(" continued #> return", continued, kind: .controlKeyword).contains("return"))
    }

    func testPowerShellUsesVSCodeScopeEquivalentKinds() {
        let source = "param([string]$Name)\nWrite-Output \"Hello $Name\""
        let result = PowerShellHighlighter().highlight(source, state: .normal)
        assertValidRanges(source, result)

        XCTAssertEqual(tokenTexts(source, result, kind: .controlKeyword), ["param"])
        XCTAssertEqual(tokenTexts(source, result, kind: .type), ["string"])
        XCTAssertEqual(tokenTexts(source, result, kind: .variable), ["$Name"])
        XCTAssertEqual(tokenTexts(source, result, kind: .supportFunction), ["Write-Output"])
        XCTAssertEqual(tokenTexts(source, result, kind: .support), ["$Name"])
        XCTAssertEqual(tokenTexts(source, result, kind: .string), ["\"Hello $Name\""])
    }

    func testPowerShellHereStringEndsOnlyAtLineStart() {
        let first = PowerShellHighlighter().highlight("@\"\ninline \"@ ignored\n", state: .normal)
        XCTAssertEqual(first.state, .powerShellHereString(quote: 34))
        XCTAssertEqual(PowerShellHighlighter().highlight("\"@\nreturn", state: first.state).state, .normal)
    }

    func testBashHighlightsShebangVariablesKeywordsAndHeredoc() {
        let source = "#!/bin/bash\nif [[ $USER ]]; then # comment\ncat <<'EOF'\n"
        let first = BashHighlighter().highlight(source, state: .normal)
        assertValidRanges(source, first)
        XCTAssertTrue(tokenTexts(source, first, kind: .directive).contains("#!/bin/bash"))
        XCTAssertTrue(tokenTexts(source, first, kind: .variable).contains("$USER"))
        XCTAssertEqual(first.state, .heredoc(delimiter: "EOF", stripTabs: false, language: .bash))
        XCTAssertEqual(BashHighlighter().highlight("Русский 😀\nEOF\ndone\n", state: first.state).state, .normal)
    }

    func testTerraformHighlightsAttributesLiteralsCommentsAndHeredoc() {
        let source = "resource \"x\" \"y\" {\n enabled = true // comment\n value = <<-EOT\n"
        let first = TerraformHighlighter().highlight(source, state: .normal)
        assertValidRanges(source, first)
        XCTAssertTrue(tokenTexts(source, first, kind: .keyword).contains("resource"))
        XCTAssertTrue(tokenTexts(source, first, kind: .property).contains("enabled"))
        XCTAssertEqual(first.state, .heredoc(delimiter: "EOT", stripTabs: true, language: .terraform))
        XCTAssertEqual(TerraformHighlighter().highlight("  EOT\n", state: first.state).state, .normal)
    }

    func testMarkdownHighlightsSourceWithoutRendering() {
        let source = "# Heading 😀\n> quote\n- item with `code` and [link](https://example.test)\n```swift\nlet x = 1\n```\n"
        let result = MarkdownHighlighter().highlight(source, state: .normal)
        assertValidRanges(source, result)
        XCTAssertTrue(tokenTexts(source, result, kind: .heading).contains("# Heading 😀"))
        XCTAssertTrue(tokenTexts(source, result, kind: .code).contains("`code`"))
        XCTAssertTrue(tokenTexts(source, result, kind: .link).contains("[link](https://example.test)"))
        XCTAssertEqual(result.state, .normal)
    }

    func testAllLexersSurviveDeterministicMalformedUnicode() {
        var seed: UInt64 = 0x51A7E
        let alphabet = Array("{}[]()<>#/'\"$😀Русскийäöü\n\t-_=*`012abc")
        for language in SourceLanguage.allCases {
            let highlighter = HighlighterFactory.make(for: language)
            for _ in 0..<120 {
                var source = ""
                for _ in 0..<300 {
                    seed = seed &* 6364136223846793005 &+ 1
                    source.append(alphabet[Int(seed % UInt64(alphabet.count))])
                }
                assertValidRanges(source, highlighter.highlight(source, state: .normal))
            }
        }
    }

    func testAdversarialRunsRemainBounded() {
        let samples = [String(repeating: "\"", count: 100_000), String(repeating: "#", count: 100_000), String(repeating: "${", count: 50_000), String(repeating: "<", count: 100_000), String(repeating: "[", count: 100_000), String(repeating: "/*", count: 50_000)]
        for language in SourceLanguage.allCases {
            let highlighter = HighlighterFactory.make(for: language)
            for source in samples { assertValidRanges(source, highlighter.highlight(source, state: .normal)) }
        }
    }

    func testPowerShellUnclosedTypeBracketsStayLinearEnoughForPreviewing() {
        let source = String(repeating: "[A", count: 50_000)
        let start = ContinuousClock.now
        let result = PowerShellHighlighter().highlight(source, state: .normal)
        let elapsed = start.duration(to: .now)

        assertValidRanges(source, result)
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    func testLexerCancellationStopsInsideLargeToken() {
        let source = "\"" + String(repeating: "\\\\", count: 500_000)
        let probe = CancellationProbe()
        let cancellation = HighlightCancellation { probe.cancelAfterFirstCheck() }
        let result = JSONHighlighter().highlight(
            source,
            state: .normal,
            cancellation: cancellation
        )

        XCTAssertGreaterThan(probe.checkCount, 1)
        XCTAssertLessThan(
            result.spans.first?.range.length ?? 0,
            (source as NSString).length
        )
    }

    func testIncrementalPipelineUsesSmallFirstBatchAndGlobalRanges() throws {
        let line = #"{"name":"value","enabled":true}"# + "\n"
        let source = String(repeating: line, count: 10_000)
        var batches: [HighlightedRangeBatch] = []
        try HighlightPipeline.enumerateBatches(text: source, language: .json) {
            batches.append($0)
        }

        XCTAssertGreaterThan(batches.count, 1)
        XCTAssertLessThanOrEqual(batches[0].range.length, PreviewPolicy.initialHighlightUTF16Length)
        for batch in batches.dropFirst() {
            XCTAssertLessThanOrEqual(batch.range.length, PreviewPolicy.highlightChunkUTF16Length)
        }
        XCTAssertEqual(batches.first?.range.location, 0)
        XCTAssertEqual(NSMaxRange(try XCTUnwrap(batches.last?.range)), (source as NSString).length)
        for batch in batches {
            for span in batch.spans {
                XCTAssertGreaterThanOrEqual(span.range.location, batch.range.location)
                XCTAssertLessThanOrEqual(NSMaxRange(span.range), NSMaxRange(batch.range))
            }
        }
    }

    func testInitialBatchContinuesWithoutGapsOrDuplicateWork() async throws {
        let source = #"{"message":""# + String(repeating: "x", count: 40_000) +
            #"","enabled":true,"count":12345}"#
        let initial = try XCTUnwrap(try HighlightPipeline.initialBatch(text: source, language: .json))
        XCTAssertEqual(initial.batch.range.location, 0)
        XCTAssertEqual(initial.batch.range.length, PreviewPolicy.initialHighlightUTF16Length)
        XCTAssertEqual(initial.stateAfter, .doubleQuotedString)

        let collector = HighlightBatchCollector()
        try await HighlightPipeline.enumerateBatchesAsync(
            text: source,
            language: .json,
            startingAtUTF16Location: NSMaxRange(initial.batch.range),
            initialState: initial.stateAfter,
            initialTargetUTF16Length: PreviewPolicy.highlightChunkUTF16Length
        ) { batch in
            await collector.append(batch)
        }
        let remaining = await collector.collected()
        let batches = [initial.batch] + remaining

        var expectedLocation = 0
        for batch in batches {
            XCTAssertEqual(batch.range.location, expectedLocation)
            expectedLocation = NSMaxRange(batch.range)
        }
        XCTAssertEqual(expectedLocation, (source as NSString).length)

        let enabledRange = (source as NSString).range(of: #""enabled""#)
        XCTAssertTrue(batches.flatMap(\.spans).contains {
            $0.kind == .property && $0.range == enabledRange
        })
    }

    func testChunkerMakesProgressForNonPositiveTargets() {
        let source = "😀 Русский text"
        XCTAssertEqual(TextChunker.split(text: source, targetUTF16Length: 0).joined(), source)
        XCTAssertEqual(TextChunker.split(text: source, targetUTF16Length: -10).joined(), source)
    }

    func testRangeValidationRejectsOverflowingAndNegativeRanges() {
        let valid = TokenSpan(2, 3, .string)
        let spans = [valid, TokenSpan(-1, 1, .comment), TokenSpan(Int.max, 1, .number), TokenSpan(1, Int.max, .keyword)]
        XCTAssertEqual(validated(spans, length: 5), [valid])
    }
}
