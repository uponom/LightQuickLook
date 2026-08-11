import Foundation
import LightQuickLookCore

enum Failure: Error { case assertion(String) }

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure.assertion(message) }
}

func validate(_ text: String, _ result: HighlightResult) throws {
    let length = (text as NSString).length
    for span in result.spans {
        try check(
            span.range.location >= 0 &&
            span.range.length >= 0 &&
            span.range.location <= length &&
            span.range.length <= length - span.range.location,
            "Invalid range \(span.range) for length \(length)"
        )
    }
}

do {
    let unicode = "Русский äöü ÄÖÜ ß 😀"
    let decodedUTF8 = try TextDecoder.decode(Data(unicode.utf8))
    try check(decodedUTF8.text == unicode, "UTF-8 decoding")
    let utf16 = Data([0xFF, 0xFE]) + unicode.data(using: .utf16LittleEndian)!
    let decodedUTF16 = try TextDecoder.decode(utf16)
    try check(decodedUTF16.text == unicode, "UTF-16 LE decoding")
    do { _ = try TextDecoder.decode(Data([0, 1, 0, 2])); throw Failure.assertion("Binary guard") } catch TextDecodeError.binary {}

    let fixtures: [(SourceLanguage, String)] = [
        (.json, "😀 {\"ключ\": \"value\", \"ok\": true, \"n\": -12.5}"),
        (.yaml, "name: \"# value\" # comment\ntext: |\n  Русский\n"),
        (.powerShell, "if ($env:PATH -match 'bin') { # comment\n@\"\ntext\n\"@\n}"),
        (.bash, "#!/bin/bash\nif [[ $USER ]]; then cat <<EOF\ntext\nEOF\nfi\n"),
        (.terraform, "resource \"x\" \"y\" { enabled = true /* comment */ }") ,
        (.markdown, "# Heading\n- `code` [link](https://example.test)\n```\nx\n```\n")
    ]
    for (language, text) in fixtures {
        let chunks = HighlightPipeline.process(text: text, language: language, targetUTF16Length: 17)
        for chunk in chunks { try validate(chunk.text, HighlightResult(spans: chunk.spans, state: .normal)) }
    }
    let splitJSON = JSONHighlighter().highlight("{\"x\":\"long", state: .normal)
    try check(splitJSON.state == .doubleQuotedString, "JSON chunk state")
    let splitJSONEnd = JSONHighlighter().highlight(" value\"}", state: splitJSON.state)
    try check(splitJSONEnd.state == .normal, "JSON chunk state termination")

    var seed: UInt64 = 0x51A7E
    let alphabet = Array("{}[]()<>#/'\"$😀Русскийäöü\n\t-_=*`012abc")
    for language in SourceLanguage.allCases {
        let lexer = HighlighterFactory.make(for: language)
        for _ in 0..<100 {
            var text = ""
            for _ in 0..<500 {
                seed = seed &* 6364136223846793005 &+ 1
                text.append(alphabet[Int(seed % UInt64(alphabet.count))])
            }
            try validate(text, lexer.highlight(text, state: .normal))
        }
        for text in [String(repeating: "\"", count: 100_000), String(repeating: "#", count: 100_000), String(repeating: "${", count: 50_000), String(repeating: "<", count: 100_000), String(repeating: "[", count: 100_000), String(repeating: "/*", count: 50_000)] {
            try validate(text, lexer.highlight(text, state: .normal))
        }
    }
    try check(TextChunker.split(text: "😀 source", targetUTF16Length: 0).joined() == "😀 source", "Non-positive chunk size")
    print("LightQuickLookSelfTest: PASS")
} catch {
    fputs("LightQuickLookSelfTest: FAIL — \(error)\n", stderr)
    exit(1)
}
