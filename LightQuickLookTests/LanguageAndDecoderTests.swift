import AppKit
import Carbon.HIToolbox
import Foundation
import XCTest
@testable import LightQuickLookCore

private final class SendableCounter: @unchecked Sendable {
    var value = 0
}

final class LanguageAndDecoderTests: XCTestCase {
    @MainActor
    func testCodePreviewViewUsesTextKit2BeforeAndAfterContentChanges() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let scrollView = try XCTUnwrap(descendants(of: NSScrollView.self, in: view).first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)

        XCTAssertNotNil(textView.textLayoutManager)
        XCTAssertNotNil(textView.textContentStorage)

        view.replace(with: HighlightedChunk(
            text: #"{"enabled":true}"#,
            spans: [TokenSpan(1, 9, .property), TokenSpan(11, 4, .literal)]
        ))

        XCTAssertNotNil(textView.textLayoutManager)
        XCTAssertNotNil(textView.textContentStorage)
        XCTAssertEqual(textView.string, #"{"enabled":true}"#)
    }

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

    @MainActor
    func testFontSizeButtonsMagnifyRenderedTextWithoutRestylingAndClampAtBounds() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let source = "# Heading\nplain\n"
        view.replace(with: HighlightedChunk(
            text: source,
            spans: [TokenSpan(0, 9, .heading)]
        ))

        let scrollView = try XCTUnwrap(descendants(of: NSScrollView.self, in: view).first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let storage = try XCTUnwrap(textView.textStorage)
        let decreaseButton = try XCTUnwrap(
            descendants(of: NSButton.self, in: view).first {
                $0.identifier?.rawValue == "decreaseFontSize"
            }
        )
        let increaseButton = try XCTUnwrap(
            descendants(of: NSButton.self, in: view).first {
                $0.identifier?.rawValue == "increaseFontSize"
            }
        )

        XCTAssertEqual(view.fontSize, CodePreviewView.defaultFontSize)
        XCTAssertTrue(decreaseButton.isEnabled)
        XCTAssertTrue(increaseButton.isEnabled)
        XCTAssertEqual(decreaseButton.keyEquivalent, "-")
        XCTAssertEqual(decreaseButton.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(increaseButton.keyEquivalent, "+")
        XCTAssertEqual(increaseButton.keyEquivalentModifierMask, [.command])

        increaseButton.performClick(nil)
        XCTAssertEqual(view.fontSize, CodePreviewView.defaultFontSize + 1)
        XCTAssertEqual(
            scrollView.magnification,
            (CodePreviewView.defaultFontSize + 1) / CodePreviewView.defaultFontSize,
            accuracy: 0.0001
        )
        for offset in [0, storage.length - 1] {
            let font = try XCTUnwrap(storage.attribute(.font, at: offset, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(font.pointSize, CodePreviewView.defaultFontSize)
        }

        view.adjustFontSize(by: 100)
        XCTAssertEqual(view.fontSize, CodePreviewView.maximumFontSize)
        XCTAssertFalse(increaseButton.isEnabled)
        XCTAssertTrue(decreaseButton.isEnabled)

        view.adjustFontSize(by: -100)
        XCTAssertEqual(view.fontSize, CodePreviewView.minimumFontSize)
        XCTAssertTrue(increaseButton.isEnabled)
        XCTAssertFalse(decreaseButton.isEnabled)
    }

    @MainActor
    func testFontButtonsUseNativeMultiClickTracking() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let increaseButton = try XCTUnwrap(
            descendants(of: NSButton.self, in: view).first {
                $0.identifier?.rawValue == "increaseFontSize"
            }
        )

        XCTAssertTrue(type(of: increaseButton) == NSButton.self)
        XCTAssertFalse(increaseButton.ignoresMultiClick)
        for _ in 0..<6 { increaseButton.performClick(nil) }

        XCTAssertEqual(view.fontSize, CodePreviewView.defaultFontSize + 6)
    }

    @MainActor
    func testLargeDocumentZoomDoesNotMutateTextStorage() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let line = #"{"key":"value","enabled":true,"count":12345}"# + "\n"
        let source = String(repeating: line, count: 5_000)
        XCTAssertGreaterThan(source.utf8.count, 200_000)
        view.replace(with: HighlightedChunk(text: source, spans: []))

        let scrollView = try XCTUnwrap(descendants(of: NSScrollView.self, in: view).first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let storage = try XCTUnwrap(textView.textStorage)
        let editNotificationCount = SendableCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: storage,
            queue: nil
        ) { _ in
            editNotificationCount.value += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        for _ in 0..<10 {
            view.adjustFontSize(by: 1)
            view.adjustFontSize(by: -1)
        }

        XCTAssertEqual(editNotificationCount.value, 0)
        XCTAssertEqual(storage.string, source)
        XCTAssertEqual(scrollView.magnification, 1, accuracy: 0.0001)
    }

    @MainActor
    func testCommandKeyEquivalentsAndControlScrollChangeFontSize() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let commandPlus = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "+",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24
        ))
        let commandMinus = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "-",
            charactersIgnoringModifiers: "-",
            isARepeat: false,
            keyCode: 27
        ))

        let scrollView = try XCTUnwrap(descendants(of: NSScrollView.self, in: view).first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        XCTAssertTrue(textView.performKeyEquivalent(with: commandPlus))
        XCTAssertEqual(view.fontSize, CodePreviewView.defaultFontSize + 1)
        XCTAssertTrue(view.performKeyEquivalent(with: commandMinus))
        XCTAssertEqual(view.fontSize, CodePreviewView.defaultFontSize)

        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        cgEvent.flags = .maskControl
        let controlScroll = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        scrollView.scrollWheel(with: controlScroll)
        XCTAssertEqual(view.fontSize, CodePreviewView.defaultFontSize + 1)
    }

    @MainActor
    func testSystemHotKeyDefinitionsAndRouting() {
        XCTAssertEqual(FontSizeHotKeyMonitor.shortcuts, [
            FontSizeHotKeyMonitor.Shortcut(
                action: .decrease,
                keyCode: UInt32(kVK_ANSI_Minus),
                modifiers: UInt32(cmdKey),
                identifier: FontSizeHotKeyMonitor.Action.decrease.rawValue
            ),
            FontSizeHotKeyMonitor.Shortcut(
                action: .increase,
                keyCode: UInt32(kVK_ANSI_Equal),
                modifiers: UInt32(cmdKey | shiftKey),
                identifier: FontSizeHotKeyMonitor.Action.increase.rawValue
            ),
            FontSizeHotKeyMonitor.Shortcut(
                action: .increase,
                keyCode: UInt32(kVK_ANSI_Equal),
                modifiers: UInt32(cmdKey),
                identifier: FontSizeHotKeyMonitor.Action.increase.rawValue
            ),
        ])

        var actions: [FontSizeHotKeyMonitor.Action] = []
        let monitor = FontSizeHotKeyMonitor { actions.append($0) }
        XCTAssertFalse(monitor.route(signature: 0, identifier: 1))
        XCTAssertFalse(monitor.route(signature: FontSizeHotKeyMonitor.signature, identifier: 99))
        XCTAssertTrue(monitor.route(
            signature: FontSizeHotKeyMonitor.signature,
            identifier: FontSizeHotKeyMonitor.Action.decrease.rawValue
        ))
        XCTAssertTrue(monitor.route(
            signature: FontSizeHotKeyMonitor.signature,
            identifier: FontSizeHotKeyMonitor.Action.increase.rawValue
        ))
        XCTAssertEqual(actions, [.decrease, .increase])
    }

    @MainActor
    func testWindowKeyboardMonitorFiltersZoomShortcutForPreviewWindow() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        XCTAssertFalse(view.isKeyboardMonitorInstalled)
        window.contentView = view
        defer { window.contentView = NSView() }
        XCTAssertTrue(view.isKeyboardMonitorInstalled)
        XCTAssertTrue(view.isSystemHotKeyMonitorRunning)

        let commandPlus = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "+",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24
        ))
        XCTAssertNil(view.filterMonitoredKeyDown(commandPlus))
        XCTAssertEqual(view.fontSize, CodePreviewView.defaultFontSize + 1)

        let unrelatedCommand = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "x",
            charactersIgnoringModifiers: "x",
            isARepeat: false,
            keyCode: 7
        ))
        XCTAssertNotNil(view.filterMonitoredKeyDown(unrelatedCommand))
        XCTAssertEqual(view.fontSize, CodePreviewView.defaultFontSize + 1)

        window.contentView = NSView()
        XCTAssertFalse(view.isKeyboardMonitorInstalled)
        XCTAssertFalse(view.isSystemHotKeyMonitorRunning)
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

    @MainActor
    private func descendants<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        root.subviews.flatMap { child -> [T] in
            var matches = (child as? T).map { [$0] } ?? []
            matches.append(contentsOf: descendants(of: type, in: child))
            return matches
        }
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
