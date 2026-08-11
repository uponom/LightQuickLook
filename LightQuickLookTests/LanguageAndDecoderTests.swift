import Foundation
import XCTest
@testable import LightQuickLookCore

final class LanguageAndDecoderTests: XCTestCase {
    func testLanguageDetectionUsesExtensionsBeforeGuessing() {
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/a.yml")), .yaml)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/a.psd1")), .powerShell)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/a.tfvars")), .terraform)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/tool"), prefix: "#!/usr/bin/env bash\n"), .bash)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/tool"), prefix: "plain"), .plain)
    }

    func testDecoderHandlesUnicodeAndBOMs() throws {
        let source = "Русский äöü 😀"
        XCTAssertEqual(try TextDecoder.decode(Data(source.utf8)).text, source)
        XCTAssertEqual(try TextDecoder.decode(Data([0xEF, 0xBB, 0xBF]) + Data(source.utf8)).text, source)
        let little = Data([0xFF, 0xFE]) + source.data(using: .utf16LittleEndian)!
        let big = Data([0xFE, 0xFF]) + source.data(using: .utf16BigEndian)!
        XCTAssertEqual(try TextDecoder.decode(little).text, source)
        XCTAssertEqual(try TextDecoder.decode(big).text, source)
    }

    func testDecoderRejectsBinaryButNotUTF16() throws {
        XCTAssertThrowsError(try TextDecoder.decode(Data([0, 1, 2, 3, 0])))
        let utf16 = Data([0xFF, 0xFE]) + "hello".data(using: .utf16LittleEndian)!
        XCTAssertEqual(try TextDecoder.decode(utf16).text, "hello")
    }

    func testPreviewLoaderRejectsSymbolicLinks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("source.json")
        let link = directory.appendingPathComponent("link.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try PreviewFileLoader.load(url: link))
    }

    func testPreviewLoaderRejectsNonFileURLsAndDirectories() throws {
        XCTAssertThrowsError(try PreviewFileLoader.load(url: URL(string: "https://example.test/source.json")!))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try PreviewFileLoader.load(url: directory))
    }

    func testPreviewLoaderCapsLargeFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let size = PreviewPolicy.maximumPreviewBytes + 4_096
        try Data(repeating: 0x20, count: size).write(to: url)
        let document = try PreviewFileLoader.load(url: url)
        XCTAssertTrue(document.isTruncated)
        XCTAssertEqual(document.text.utf8.count, PreviewPolicy.maximumPreviewBytes)
        XCTAssertEqual(document.fileSize, UInt64(size))
    }
}
