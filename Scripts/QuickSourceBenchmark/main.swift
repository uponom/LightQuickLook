import Foundation
import AppKit
import QuickSourceCore

func elapsedMilliseconds(_ operation: () throws -> Void) rethrows -> Double {
    let start = ContinuousClock.now
    try operation()
    return Double(start.duration(to: .now).components.attoseconds) / 1_000_000_000_000_000
}

func makeJSON(bytes: Int) -> Data {
    let line = "{\"name\":\"Русский äöü 😀\",\"enabled\":true,\"value\":123.45}\n"
    var text = String(repeating: line, count: max(1, bytes / line.utf8.count + 1))
    while text.utf8.count > bytes { text.removeLast() }
    return Data(text.utf8)
}

print("architecture=\(ProcessInfo.processInfo.machineArchitecture) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
for size in [100 * 1_024, 256 * 1_024, 1 * 1_024 * 1_024, 8 * 1_024 * 1_024] {
    let data = makeJSON(bytes: size)
    var decoded = ""
    let decode = try elapsedMilliseconds { decoded = try TextDecoder.decode(data).text }
    var tokenCount = 0
    var chunks: [HighlightedChunk] = []
    let highlight = elapsedMilliseconds {
        chunks = HighlightPipeline.process(text: decoded, language: .json)
        tokenCount = chunks.reduce(0) { $0 + $1.spans.count }
    }
    var attributedLength = 0
    let attributed = elapsedMilliseconds {
        let output = NSMutableAttributedString()
        for chunk in chunks {
            let value = NSMutableAttributedString(string: chunk.text)
            for span in chunk.spans { value.addAttribute(.foregroundColor, value: NSColor.labelColor, range: span.range) }
            output.append(value)
        }
        attributedLength = output.length
    }
    print("bytes=\(data.count) decode_ms=\(String(format: "%.3f", decode)) highlight_ms=\(String(format: "%.3f", highlight)) attributed_ms=\(String(format: "%.3f", attributed)) tokens=\(tokenCount) utf16=\(attributedLength)")
}

var usage = rusage()
getrusage(RUSAGE_SELF, &usage)
print("peak_rss_mib=\(String(format: "%.1f", Double(usage.ru_maxrss) / 1_048_576.0))")

extension ProcessInfo {
    var machineArchitecture: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        if buffer.last == 0 { buffer.removeLast() }
        return String(decoding: buffer.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
