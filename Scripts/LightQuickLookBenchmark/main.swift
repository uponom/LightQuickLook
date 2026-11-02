import Foundation
import Darwin
import LightQuickLookCore

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

func makeMinifiedJSON(bytes: Int) -> Data {
    let item = #""key":"value","enabled":true,"count":12345"#
    var text = "{"
    while text.utf8.count + item.utf8.count + 2 <= bytes {
        if text.count > 1 { text.append(",") }
        text.append(item)
    }
    text.append("}")
    return Data(text.utf8)
}

print("architecture=\(ProcessInfo.processInfo.machineArchitecture) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
let cases: [(name: String, data: Data)] = [
    ("formatted-100KiB", makeJSON(bytes: 100 * 1_024)),
    ("formatted-256KiB", makeJSON(bytes: 256 * 1_024)),
    ("formatted-1MiB", makeJSON(bytes: 1 * 1_024 * 1_024)),
    ("formatted-8MiB", makeJSON(bytes: 8 * 1_024 * 1_024)),
    ("minified-256KiB", makeMinifiedJSON(bytes: 256 * 1_024)),
    ("minified-1MiB", makeMinifiedJSON(bytes: 1 * 1_024 * 1_024)),
]

for benchmarkCase in cases {
    let data = benchmarkCase.data
    var decoded = ""
    let decode = try elapsedMilliseconds { decoded = try TextDecoder.decode(data).text }
    var tokenCount = 0
    var batchCount = 0
    var firstBatch = 0.0
    let highlightStart = ContinuousClock.now
    let highlight = elapsedMilliseconds {
        try! HighlightPipeline.enumerateBatches(text: decoded, language: .json) { batch in
            batchCount += 1
            tokenCount += batch.spans.count
            if batchCount == 1 {
                firstBatch = Double(highlightStart.duration(to: .now).components.attoseconds) / 1_000_000_000_000_000
            }
        }
    }
    let wrapDetection = elapsedMilliseconds { _ = TextLayoutPolicy.requiresSoftWrap(decoded) }
    print(
        "case=\(benchmarkCase.name) bytes=\(data.count) " +
        "decode_ms=\(String(format: "%.3f", decode)) " +
        "first_batch_ms=\(String(format: "%.3f", firstBatch)) " +
        "highlight_ms=\(String(format: "%.3f", highlight)) " +
        "wrap_scan_ms=\(String(format: "%.3f", wrapDetection)) " +
        "batches=\(batchCount) tokens=\(tokenCount) utf16=\((decoded as NSString).length)"
    )
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
