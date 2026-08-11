import Foundation

struct UTF16Scanner {
    let units: [UInt16]
    var index = 0

    init(_ text: String) { units = Array(text.utf16) }
    var isAtEnd: Bool { index >= units.count }
    var current: UInt16 { isAtEnd ? 0 : units[index] }
    func peek(_ distance: Int = 1) -> UInt16 {
        let position = index + distance
        return position >= 0 && position < units.count ? units[position] : 0
    }
    mutating func advance(_ count: Int = 1) { index = min(units.count, index + count) }
}

@inline(__always) func isSpace(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
@inline(__always) func isHorizontalSpace(_ c: UInt16) -> Bool { c == 32 || c == 9 }
@inline(__always) func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
@inline(__always) func isASCIIAlpha(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }
@inline(__always) func isIdentifier(_ c: UInt16) -> Bool { isASCIIAlpha(c) || isDigit(c) || c == 95 || c == 45 || c == 58 }

func ascii(_ units: ArraySlice<UInt16>) -> String {
    String(decoding: units, as: UTF16.self)
}

func lineEnd(in units: [UInt16], from start: Int) -> Int {
    var i = start
    while i < units.count, units[i] != 10, units[i] != 13 { i += 1 }
    return i
}

func nextLine(in units: [UInt16], after end: Int) -> Int {
    var i = end
    if i < units.count, units[i] == 13 { i += 1 }
    if i < units.count, units[i] == 10 { i += 1 }
    return i
}

func scanQuoted(_ units: [UInt16], from start: Int, quote: UInt16, escapes: Bool = true) -> Int {
    var i = start + 1
    while i < units.count {
        if escapes, units[i] == 92 { i = min(units.count, i + 2); continue }
        if units[i] == quote { return i + 1 }
        i += 1
    }
    return units.count
}

func hasPrefix(_ units: [UInt16], at index: Int, _ literal: String, caseInsensitive: Bool = false) -> Bool {
    guard index >= 0, index <= units.count else { return false }
    let target = literal.utf16
    guard target.count <= units.count - index else { return false }
    var offset = 0
    for targetUnit in target {
        var lhs = units[index + offset], rhs = targetUnit
        if caseInsensitive {
            if lhs >= 65 && lhs <= 90 { lhs += 32 }
            if rhs >= 65 && rhs <= 90 { rhs += 32 }
        }
        if lhs != rhs { return false }
        offset += 1
    }
    return true
}

func slice(_ units: [UInt16], from start: Int, to end: Int, equals target: [UInt16]) -> Bool {
    guard start >= 0, end >= start, end <= units.count, end - start == target.count else { return false }
    for offset in target.indices where units[start + offset] != target[offset] { return false }
    return true
}

func validated(_ spans: [TokenSpan], length: Int) -> [TokenSpan] {
    spans.filter {
        $0.range.location >= 0 &&
        $0.range.length >= 0 &&
        $0.range.location <= length &&
        $0.range.length <= length - $0.range.location
    }
}
