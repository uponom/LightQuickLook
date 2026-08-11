import AppKit
import Foundation
import XCTest
@testable import LightQuickLookCore

final class LanguageAndDecoderTests: XCTestCase {
    func testVSCode2026ThemesUseOfficialEditorColorsAndReadableTokens() {
        XCTAssertEqual(VSCode2026Theme.dark.background.hex, 0x121314)
        XCTAssertEqual(VSCode2026Theme.dark.foreground.hex, 0xBBBEBF)
        XCTAssertEqual(VSCode2026Theme.light.background.hex, 0xFFFFFF)
        XCTAssertEqual(VSCode2026Theme.light.foreground.hex, 0x202020)
        XCTAssertEqual(VSCode2026Theme.dark.color(for: .keyword).hex, 0xFF7B72)
        XCTAssertEqual(VSCode2026Theme.dark.color(for: .controlKeyword).hex, 0xC586C0)
        XCTAssertEqual(VSCode2026Theme.dark.color(for: .type).hex, 0xFF7B72)
        XCTAssertEqual(VSCode2026Theme.dark.color(for: .support).hex, 0x79C0FF)
        XCTAssertEqual(VSCode2026Theme.dark.color(for: .supportFunction).hex, 0xDCDCAA)
        XCTAssertEqual(VSCode2026Theme.dark.color(for: .variable).hex, 0xC9D1D9)
        XCTAssertEqual(VSCode2026Theme.light.color(for: .keyword).hex, 0xCF222E)
        XCTAssertEqual(VSCode2026Theme.light.color(for: .controlKeyword).hex, 0xAF00DB)
        XCTAssertEqual(VSCode2026Theme.light.color(for: .type).hex, 0xCF222E)
        XCTAssertEqual(VSCode2026Theme.light.color(for: .support).hex, 0x0550AE)
        XCTAssertEqual(VSCode2026Theme.light.color(for: .supportFunction).hex, 0x795E26)
        XCTAssertEqual(VSCode2026Theme.light.color(for: .variable).hex, 0x1F2328)

        for theme in VSCode2026Theme.allCases {
            XCTAssertEqual(theme.color(for: .operator), theme.foreground)
            XCTAssertEqual(theme.color(for: .punctuation), theme.foreground)
            for kind in TokenKind.allCases {
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(theme.color(for: kind), theme.background),
                    4.5,
                    "\(theme) \(kind) does not meet WCAG AA text contrast"
                )
            }
        }
    }

    @MainActor
    func testCodePreviewViewUsesReadableHCLPunctuationAndRecolorsLive() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.appearance = NSAppearance(named: .darkAqua)
        let source = "resource \"example\" \"test\" {\n  enabled = true\n}\n"
        let highlighted = TerraformHighlighter().highlight(source, state: .normal)
        view.replace(with: HighlightedChunk(text: source, spans: highlighted.spans))

        let scrollView = try XCTUnwrap(view.subviews.compactMap { $0 as? NSScrollView }.first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let storage = try XCTUnwrap(textView.textStorage)
        let text = source as NSString
        let punctuationOffsets = ["{", "=", "}"].map { text.range(of: $0).location }

        XCTAssertEqual(nsColorHex(textView.backgroundColor), VSCode2026Theme.dark.background.hex)
        for offset in punctuationOffsets {
            let color = try XCTUnwrap(storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor)
            XCTAssertEqual(nsColorHex(color), VSCode2026Theme.dark.foreground.hex)
        }

        view.appearance = NSAppearance(named: .aqua)
        view.viewDidChangeEffectiveAppearance()
        XCTAssertEqual(nsColorHex(textView.backgroundColor), VSCode2026Theme.light.background.hex)
        for offset in punctuationOffsets {
            let color = try XCTUnwrap(storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor)
            XCTAssertEqual(nsColorHex(color), VSCode2026Theme.light.foreground.hex)
        }
    }

    @MainActor
    func testPowerShellPreviewMatchesVSCode2026ScopePrecedence() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.appearance = NSAppearance(named: .darkAqua)
        let source = "param([string]$Name)\nWrite-Output \"Hello $Name\""
        let highlighted = PowerShellHighlighter().highlight(source, state: .normal)
        view.replace(with: HighlightedChunk(text: source, spans: highlighted.spans))

        let scrollView = try XCTUnwrap(view.subviews.compactMap { $0 as? NSScrollView }.first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let storage = try XCTUnwrap(textView.textStorage)
        let text = source as NSString
        let firstVariable = text.range(of: "$Name")
        let secondSearchRange = NSRange(location: NSMaxRange(firstVariable), length: text.length - NSMaxRange(firstVariable))
        let secondVariable = text.range(of: "$Name", options: [], range: secondSearchRange)
        let expectations: [(NSRange, TokenKind)] = [
            (text.range(of: "param"), .controlKeyword),
            (text.range(of: "string"), .type),
            (firstVariable, .variable),
            (text.range(of: "Write-Output"), .supportFunction),
            (text.range(of: "Hello"), .string),
            (secondVariable, .support),
        ]

        func assertColors(for theme: VSCode2026Theme, file: StaticString = #filePath, line: UInt = #line) throws {
            for (range, kind) in expectations {
                let color = try XCTUnwrap(
                    storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor,
                    file: file,
                    line: line
                )
                XCTAssertEqual(nsColorHex(color), theme.color(for: kind).hex, "Unexpected color for \(kind)", file: file, line: line)
            }
        }

        try assertColors(for: .dark)
        view.appearance = NSAppearance(named: .aqua)
        view.viewDidChangeEffectiveAppearance()
        try assertColors(for: .light)
    }

    func testBundleRegistrationDoesNotClaimMarkdown() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        func propertyList(at relativePath: String) throws -> [String: Any] {
            let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
            return try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
        }

        let host = try propertyList(at: "LightQuickLook/Info.plist")
        XCTAssertNil(host["UTImportedTypeDeclarations"])

        let preview = try propertyList(at: "LightQuickLookPreview/Info.plist")
        let extensionDictionary = try XCTUnwrap(preview["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionDictionary["NSExtensionAttributes"] as? [String: Any])
        let supportedTypes = try XCTUnwrap(attributes["QLSupportedContentTypes"] as? [String])
        XCTAssertFalse(supportedTypes.contains("net.daringfireball.markdown"))
        XCTAssertEqual(Set(supportedTypes), [
            "public.yaml",
            "public.json",
            "public.shell-script",
            "public.bash-script",
            "io.github.uponom.lightquicklook.powershell-source",
            "io.github.uponom.lightquicklook.hcl-source",
        ])
    }

    func testLanguageDetectionUsesExtensionsBeforeGuessing() {
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/a.yml")), .yaml)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/a.psd1")), .powerShell)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/a.tfvars")), .terraform)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/tool"), prefix: "#!/usr/bin/env bash\n"), .bash)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/tool"), prefix: "plain"), .plain)
    }

    private func contrastRatio(_ foreground: ThemeRGBColor, _ background: ThemeRGBColor) -> Double {
        func luminance(_ color: ThemeRGBColor) -> Double {
            func linear(_ component: UInt8) -> Double {
                let value = Double(component) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        }

        let first = luminance(foreground)
        let second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func nsColorHex(_ color: NSColor) -> UInt32? {
        guard let converted = color.usingColorSpace(.sRGB) else { return nil }
        func component(_ value: CGFloat) -> UInt32 {
            UInt32((value * 255).rounded())
        }
        return component(converted.redComponent) << 16 |
            component(converted.greenComponent) << 8 |
            component(converted.blueComponent)
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
