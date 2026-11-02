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
    func testThemeButtonsSwitchAndPersistTheSelectedTheme() throws {
        let suiteName = "io.github.uponom.LightQuickLook.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let view = CodePreviewView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 500),
            userDefaults: defaults
        )
        view.appearance = NSAppearance(named: .darkAqua)
        view.viewDidChangeEffectiveAppearance()

        let buttons = descendants(of: NSButton.self, in: view)
        let automatic = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "automaticTheme" })
        let light = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "lightTheme" })
        let dark = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "darkTheme" })
        let scrollView = try XCTUnwrap(descendants(of: NSScrollView.self, in: view).first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)

        func isBold(_ button: NSButton) -> Bool {
            button.font?.fontDescriptor.symbolicTraits.contains(.bold) == true
        }

        XCTAssertEqual(view.themePreference, .automatic)
        XCTAssertEqual(automatic.state, .on)
        XCTAssertTrue(isBold(automatic))
        XCTAssertFalse(isBold(light))
        XCTAssertFalse(isBold(dark))
        XCTAssertEqual(nsColorHex(textView.backgroundColor), VSCode2026Theme.dark.background.hex)

        light.performClick(nil)
        XCTAssertEqual(view.themePreference, .light)
        XCTAssertEqual(view.appearance?.name, .aqua)
        XCTAssertEqual(light.state, .on)
        XCTAssertEqual(automatic.state, .off)
        XCTAssertEqual(dark.state, .off)
        XCTAssertTrue(isBold(light))
        XCTAssertFalse(isBold(automatic))
        XCTAssertFalse(isBold(dark))
        XCTAssertEqual(nsColorHex(textView.backgroundColor), VSCode2026Theme.light.background.hex)

        dark.performClick(nil)
        XCTAssertEqual(view.appearance?.name, .darkAqua)
        XCTAssertTrue(isBold(dark))
        XCTAssertFalse(isBold(automatic))
        XCTAssertFalse(isBold(light))
        XCTAssertEqual(defaults.string(forKey: CodePreviewView.themePreferenceDefaultsKey), "dark")
        XCTAssertEqual(nsColorHex(textView.backgroundColor), VSCode2026Theme.dark.background.hex)

        let restoredView = CodePreviewView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 500),
            userDefaults: defaults
        )
        XCTAssertEqual(restoredView.themePreference, .dark)
        let restoredDark = try XCTUnwrap(
            descendants(of: NSButton.self, in: restoredView).first {
                $0.identifier?.rawValue == "darkTheme"
            }
        )
        XCTAssertEqual(restoredDark.state, .on)
        XCTAssertTrue(isBold(restoredDark))

        automatic.performClick(nil)
        XCTAssertNil(view.appearance)
        XCTAssertTrue(isBold(automatic))
        XCTAssertFalse(isBold(light))
        XCTAssertFalse(isBold(dark))
        XCTAssertEqual(defaults.string(forKey: CodePreviewView.themePreferenceDefaultsKey), "automatic")
    }

    @MainActor
    func testCodePreviewViewUsesReadableHCLPunctuationAndRecolorsLive() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.setThemePreference(.dark, persist: false)
        let source = "resource \"example\" \"test\" {\n  enabled = true\n}\n"
        let highlighted = TerraformHighlighter().highlight(source, state: .normal)
        view.replace(with: HighlightedChunk(text: source, spans: highlighted.spans))

        let scrollView = try XCTUnwrap(view.subviews.compactMap { $0 as? NSScrollView }.first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let text = source as NSString
        let punctuationOffsets = ["{", "=", "}"].map { text.range(of: $0).location }

        XCTAssertEqual(nsColorHex(textView.backgroundColor), VSCode2026Theme.dark.background.hex)
        for offset in punctuationOffsets {
            XCTAssertEqual(
                nsColorHex(view.foregroundColor(atUTF16Offset: offset)),
                VSCode2026Theme.dark.foreground.hex
            )
        }

        view.setThemePreference(.light, persist: false)
        XCTAssertEqual(nsColorHex(textView.backgroundColor), VSCode2026Theme.light.background.hex)
        for offset in punctuationOffsets {
            XCTAssertEqual(
                nsColorHex(view.foregroundColor(atUTF16Offset: offset)),
                VSCode2026Theme.light.foreground.hex
            )
        }
    }

    @MainActor
    func testPowerShellPreviewMatchesVSCode2026ScopePrecedence() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.setThemePreference(.dark, persist: false)
        let source = "param([string]$Name)\nWrite-Output \"Hello $Name\""
        let highlighted = PowerShellHighlighter().highlight(source, state: .normal)
        view.replace(with: HighlightedChunk(text: source, spans: highlighted.spans))

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
                let color = view.foregroundColor(atUTF16Offset: range.location)
                XCTAssertEqual(nsColorHex(color), theme.color(for: kind).hex, "Unexpected color for \(kind)", file: file, line: line)
            }
        }

        try assertColors(for: .dark)
        view.setThemePreference(.light, persist: false)
        try assertColors(for: .light)
    }

    @MainActor
    func testHighlightingUsesLazyRenderingAttributesWithoutFragmentingStorage() async throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.setThemePreference(.light, persist: false)
        let source = #"{"name":"value","enabled":true}"#
        let result = JSONHighlighter().highlight(source, state: .normal)
        view.displayPlainText(source, requiresSoftWrap: false)

        let scrollView = try XCTUnwrap(descendants(of: NSScrollView.self, in: view).first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let storage = try XCTUnwrap(textView.textStorage)
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = NSView()
        }
        window.layoutIfNeeded()
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        for _ in 0..<4 { await Task.yield() }
        let refreshesBeforeTokens = view.viewportRenderingRefreshCount
        XCTAssertNotNil(textView.textLayoutManager?.renderingAttributesValidator)
        var runsBefore = 0
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { _, _, _ in
            runsBefore += 1
        }
        let before = storage.attributes(at: 1, effectiveRange: nil)
        view.appendHighlightBatch(HighlightedRangeBatch(
            range: NSRange(location: 0, length: storage.length),
            spans: result.spans
        ))
        for _ in 0..<4 { await Task.yield() }
        let after = storage.attributes(at: 1, effectiveRange: nil)
        var runsAfter = 0
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { _, _, _ in
            runsAfter += 1
        }

        XCTAssertEqual(before[.foregroundColor] as? NSColor, after[.foregroundColor] as? NSColor)
        XCTAssertEqual(runsBefore, 1)
        XCTAssertEqual(runsAfter, 1)
        XCTAssertEqual(view.highlightedTokenCount, result.spans.count)
        XCTAssertGreaterThan(view.viewportRenderingRefreshCount, refreshesBeforeTokens)
        XCTAssertEqual(
            nsColorHex(view.foregroundColor(atUTF16Offset: 1)),
            VSCode2026Theme.light.color(for: .property).hex
        )
    }

    @MainActor
    func testLargeSingleLineJSONRecolorsAlreadyLaidOutFirstViewport() async throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 600))
        view.setThemePreference(.dark, persist: false)
        let repeatedEntry = #""visibleKey":"visibleValue","enabled":true,"count":12345,"#
        let source = "{" + String(repeating: repeatedEntry, count: 12_000) + #""last":false}"#
        XCTAssertGreaterThan(source.utf8.count, 600_000)
        XCTAssertTrue(TextLayoutPolicy.requiresSoftWrap(source))
        view.displayPlainText(source, requiresSoftWrap: true)

        let scrollView = try XCTUnwrap(descendants(of: NSScrollView.self, in: view).first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let layoutManager = try XCTUnwrap(textView.textLayoutManager)
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = NSView()
        }
        window.layoutIfNeeded()
        layoutManager.textViewportLayoutController.layoutViewport()
        for _ in 0..<4 { await Task.yield() }

        let initial = try XCTUnwrap(try HighlightPipeline.initialBatch(text: source, language: .json))
        view.appendHighlightBatch(initial.batch)
        for _ in 0..<4 { await Task.yield() }
        layoutManager.textViewportLayoutController.layoutViewport()
        window.displayIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var syntaxColoredPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.blueComponent - color.redComponent > 0.12,
                   color.blueComponent - color.greenComponent > 0.05 {
                    syntaxColoredPixels += 1
                }
            }
        }
        XCTAssertGreaterThan(syntaxColoredPixels, 20, "The laid-out first viewport should contain JSON token colors")
    }

    @MainActor
    func testLongLinesEnableSoftWrapAndSuspiciousLayoutProtection() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let longLine = String(repeating: "x", count: PreviewPolicy.longLineWrapUTF16Length + 1)
        view.displayPlainText(longLine, requiresSoftWrap: TextLayoutPolicy.requiresSoftWrap(longLine))

        let scrollView = try XCTUnwrap(descendants(of: NSScrollView.self, in: view).first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        XCTAssertTrue(view.isSoftWrappingEnabled)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertTrue(textView.textContainer?.widthTracksTextView == true)
        XCTAssertTrue(textView.textLayoutManager?.limitsLayoutForSuspiciousContents == true)
    }

    @MainActor
    func testFontSizeButtonsResizeRenderingAttributesWithoutRestylingAndClampAtBounds() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let source = "# Heading\nplain\n"
        view.replace(with: HighlightedChunk(
            text: source,
            spans: [
                TokenSpan(0, 9, .heading),
                TokenSpan(10, 5, .string),
            ]
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
        XCTAssertEqual(view.renderedFontSize, CodePreviewView.defaultFontSize + 1)
        XCTAssertEqual(
            view.foregroundAndFont(atUTF16Offset: 10).font.pointSize,
            CodePreviewView.defaultFontSize + 1
        )
        XCTAssertEqual(scrollView.magnification, 1, accuracy: 0.0001)
        for offset in [0, storage.length - 1] {
            let font = try XCTUnwrap(storage.attribute(.font, at: offset, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(font.pointSize, CodePreviewView.defaultFontSize + 1)
        }
        let headingFont = try XCTUnwrap(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(headingFont.pointSize, CodePreviewView.defaultFontSize + 1)
        XCTAssertTrue(headingFont.fontDescriptor.symbolicTraits.contains(.bold))

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
    func testLargeDocumentZoomUpdatesFontWithoutChangingText() throws {
        let view = CodePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let line = #"{"key":"value","enabled":true,"count":12345,"description":"large preview"}"# + "\n"
        let source = String(repeating: line, count: 7_000)
        XCTAssertGreaterThan(source.utf8.count, 450_000)
        view.replace(with: HighlightedChunk(text: source, spans: []))

        let scrollView = try XCTUnwrap(descendants(of: NSScrollView.self, in: view).first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let storage = try XCTUnwrap(textView.textStorage)
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        defer { window.contentView = NSView() }
        window.layoutIfNeeded()
        let editNotificationCount = SendableCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: storage,
            queue: nil
        ) { _ in
            editNotificationCount.value += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        view.adjustFontSize(by: 1)
        window.layoutIfNeeded()
        let enlargedFont = try XCTUnwrap(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(enlargedFont.pointSize, CodePreviewView.defaultFontSize + 1)

        view.adjustFontSize(by: -1)
        window.layoutIfNeeded()

        XCTAssertGreaterThan(editNotificationCount.value, 0)
        XCTAssertLessThanOrEqual(editNotificationCount.value, 2)
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
        let exportedTypes = try XCTUnwrap(host["UTExportedTypeDeclarations"] as? [[String: Any]])
        let jsonLinesType = try XCTUnwrap(exportedTypes.first {
            $0["UTTypeIdentifier"] as? String == "io.github.uponom.lightquicklook.json-lines"
        })
        XCTAssertEqual(jsonLinesType["UTTypeConformsTo"] as? [String], ["public.json"])
        let jsonLinesTags = try XCTUnwrap(jsonLinesType["UTTypeTagSpecification"] as? [String: Any])
        XCTAssertEqual(jsonLinesTags["public.filename-extension"] as? [String], ["jsonl"])
        let exportedIdentifiers = Set(exportedTypes.compactMap { $0["UTTypeIdentifier"] as? String })
        XCTAssertFalse(exportedIdentifiers.contains("public.toml"))
        XCTAssertFalse(exportedIdentifiers.contains("com.microsoft.ini"))

        let preview = try propertyList(at: "LightQuickLookPreview/Info.plist")
        let extensionDictionary = try XCTUnwrap(preview["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionDictionary["NSExtensionAttributes"] as? [String: Any])
        let supportedTypes = try XCTUnwrap(attributes["QLSupportedContentTypes"] as? [String])
        XCTAssertFalse(supportedTypes.contains("net.daringfireball.markdown"))
        XCTAssertEqual(Set(supportedTypes), [
            "public.yaml",
            "public.json",
            "public.toml",
            "com.microsoft.ini",
            "public.shell-script",
            "public.bash-script",
            "io.github.uponom.lightquicklook.powershell-source",
            "io.github.uponom.lightquicklook.hcl-source",
            "io.github.uponom.lightquicklook.json-lines",
        ])
    }

    func testLanguageDetectionUsesExtensionsBeforeGuessing() {
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/a.yml")), .yaml)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/a.jsonl")), .json)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/a.toml")), .toml)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/a.ini")), .ini)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/a.psd1")), .powerShell)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/a.tfvars")), .terraform)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/tool"), prefix: "#!/usr/bin/env bash\n"), .bash)
        XCTAssertEqual(LanguageDetector.detect(url: URL(fileURLWithPath: "/tmp/tool"), prefix: "plain"), .plain)
    }

    func testLongLinePolicyOnlyWrapsPathologicalLines() {
        XCTAssertFalse(TextLayoutPolicy.requiresSoftWrap("short\nlines\n", threshold: 8))
        XCTAssertTrue(TextLayoutPolicy.requiresSoftWrap("123456789", threshold: 8))
        XCTAssertFalse(TextLayoutPolicy.requiresSoftWrap("1234\n1234", threshold: 8))
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
