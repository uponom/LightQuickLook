import AppKit
import LightQuickLookCore
import os

enum PreviewPerformance {
    static let signposter = OSSignposter(
        subsystem: "io.github.uponom.LightQuickLook",
        category: "PreviewPerformance"
    )

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}

private final class MainThreadEventBox: @unchecked Sendable {
    var event: NSEvent?

    init(_ event: NSEvent) {
        self.event = event
    }
}

private final class EventMonitorToken: @unchecked Sendable {
    var value: Any?
}

enum PreviewThemePreference: String, CaseIterable, Sendable {
    case automatic
    case light
    case dark
}

@MainActor
private final class TokenSpanIndex {
    private struct Batch {
        let range: NSRange
        let spans: [TokenSpan]
        let prefixMaximumEnds: [Int]?
    }

    private var batches: [Batch] = []
    private(set) var count = 0

    func reset() {
        batches.removeAll(keepingCapacity: true)
        count = 0
    }

    func append(_ batch: HighlightedRangeBatch) {
        let spans = batch.spans
        var maximumEnd = 0
        var hasNestedOrOverlappingEnds = false
        let prefixMaximumEnds = spans.map { span -> Int in
            if span.range.location < maximumEnd { hasNestedOrOverlappingEnds = true }
            maximumEnd = max(maximumEnd, NSMaxRange(span.range))
            return maximumEnd
        }
        batches.append(Batch(
            range: batch.range,
            spans: spans,
            prefixMaximumEnds: hasNestedOrOverlappingEnds ? prefixMaximumEnds : nil
        ))
        count += spans.count
    }

    func forEachSpan(intersecting query: NSRange, _ body: (TokenSpan) -> Void) {
        guard query.length > 0 else { return }
        let queryEnd = NSMaxRange(query)
        for batch in batches where NSIntersectionRange(batch.range, query).length > 0 {
            var lower = 0
            var upper = batch.spans.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                let maximumEnd = batch.prefixMaximumEnds?[middle] ?? NSMaxRange(batch.spans[middle].range)
                if maximumEnd <= query.location {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }

            var index = lower
            while index < batch.spans.count {
                let span = batch.spans[index]
                if span.range.location >= queryEnd { break }
                if NSIntersectionRange(span.range, query).length > 0 { body(span) }
                index += 1
            }
        }
    }
}

@MainActor
private final class FontZoomScrollView: NSScrollView {
    var controlScrollHandler: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.control) else {
            super.scrollWheel(with: event)
            return
        }

        controlScrollHandler?(event)
    }
}

@MainActor
private final class FontZoomTextView: NSTextView {
    var keyEquivalentHandler: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class CodePreviewView: NSView {
    static let defaultFontSize: CGFloat = 13
    static let minimumFontSize: CGFloat = 8
    static let maximumFontSize: CGFloat = 32
    static let themePreferenceDefaultsKey = "previewThemePreference"

    private static let preciseScrollStep: CGFloat = 8
    private let userDefaults: UserDefaults
    private let controlsBar = NSView()
    private let separator = NSBox()
    private let scrollView = FontZoomScrollView()
    // Construct the text system explicitly with NSTextLayoutManager. Using the
    // frame initializer would silently create the TextKit 1 compatibility stack.
    private let textView = FontZoomTextView(usingTextLayoutManager: true)
    private let decreaseFontButton = NSButton(title: "−", target: nil, action: nil)
    private let increaseFontButton = NSButton(title: "+", target: nil, action: nil)
    private let automaticThemeButton = NSButton(title: "Auto", target: nil, action: nil)
    private let lightThemeButton = NSButton(title: "Light", target: nil, action: nil)
    private let darkThemeButton = NSButton(title: "Dark", target: nil, action: nil)
    private let tokenIndex = TokenSpanIndex()
    private(set) var fontSize = CodePreviewView.defaultFontSize
    private(set) var themePreference: PreviewThemePreference
    private var preciseScrollAccumulator: CGFloat = 0
    private var activeTheme: VSCode2026Theme = .light
    private var cachedRegularFont = NSFont.monospacedSystemFont(ofSize: CodePreviewView.defaultFontSize, weight: .regular)
    private var cachedHeadingFont = NSFont.monospacedSystemFont(ofSize: CodePreviewView.defaultFontSize, weight: .semibold)
    private var baseRenderingAttributes: [NSAttributedString.Key: Any] = [:]
    private var tokenRenderingAttributes: [TokenKind: [NSAttributedString.Key: Any]] = [:]
    private(set) var isSoftWrappingEnabled = false
    private var firstViewportValidationPending = false
    private var viewportRenderingRefreshScheduled = false
    private(set) var viewportRenderingRefreshCount = 0
    private var isApplyingTheme = false
    private let keyDownMonitor = EventMonitorToken()
    private lazy var systemHotKeyMonitor = FontSizeHotKeyMonitor { [weak self] action in
        switch action {
        case .decrease:
            self?.adjustFontSize(by: -1)
        case .increase:
            self?.adjustFontSize(by: 1)
        }
    }

    var isKeyboardMonitorInstalled: Bool {
        keyDownMonitor.value != nil
    }

    var isSystemHotKeyMonitorRunning: Bool {
        systemHotKeyMonitor.isRunning
    }

    override init(frame frameRect: NSRect) {
        let defaults = UserDefaults.standard
        userDefaults = defaults
        themePreference = Self.loadThemePreference(from: defaults)
        super.init(frame: frameRect)
        configure()
    }

    init(frame frameRect: NSRect, userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        themePreference = Self.loadThemePreference(from: userDefaults)
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        let defaults = UserDefaults.standard
        userDefaults = defaults
        themePreference = Self.loadThemePreference(from: defaults)
        super.init(coder: coder)
        configure()
    }

    private static func loadThemePreference(from defaults: UserDefaults) -> PreviewThemePreference {
        guard
            let rawValue = defaults.string(forKey: themePreferenceDefaultsKey),
            let preference = PreviewThemePreference(rawValue: rawValue)
        else { return .automatic }
        return preference
    }

    private func configure() {
        controlsBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controlsBar)

        configureFontButton(
            decreaseFontButton,
            identifier: "decreaseFontSize",
            accessibilityLabel: "Decrease font size",
            toolTip: "Decrease font size (⌘−)",
            keyEquivalent: "-",
            action: #selector(decreaseFontSize(_:))
        )
        configureFontButton(
            increaseFontButton,
            identifier: "increaseFontSize",
            accessibilityLabel: "Increase font size",
            toolTip: "Increase font size (⌘+)",
            keyEquivalent: "+",
            action: #selector(increaseFontSize(_:))
        )

        configureThemeButton(
            automaticThemeButton,
            identifier: "automaticTheme",
            accessibilityLabel: "Use automatic theme",
            toolTip: "Follow the system appearance",
            action: #selector(selectAutomaticTheme(_:))
        )
        configureThemeButton(
            lightThemeButton,
            identifier: "lightTheme",
            accessibilityLabel: "Use light theme",
            toolTip: "Always use the light theme",
            action: #selector(selectLightTheme(_:))
        )
        configureThemeButton(
            darkThemeButton,
            identifier: "darkTheme",
            accessibilityLabel: "Use dark theme",
            toolTip: "Always use the dark theme",
            action: #selector(selectDarkTheme(_:))
        )

        let themeControls = NSStackView(views: [automaticThemeButton, lightThemeButton, darkThemeButton])
        themeControls.orientation = .horizontal
        themeControls.alignment = .centerY
        themeControls.spacing = 4

        let fontControls = NSStackView(views: [decreaseFontButton, increaseFontButton])
        fontControls.orientation = .horizontal
        fontControls.alignment = .centerY
        fontControls.spacing = 6

        let controls = NSStackView(views: [themeControls, fontControls])
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 12
        controlsBar.addSubview(controls)

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        addSubview(separator)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            controlsBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsBar.topAnchor.constraint(equalTo: topAnchor),
            controlsBar.heightAnchor.constraint(equalToConstant: 38),
            controls.trailingAnchor.constraint(equalTo: controlsBar.trailingAnchor, constant: -12),
            controls.centerYAnchor.constraint(equalTo: controlsBar.centerYAnchor),
            decreaseFontButton.widthAnchor.constraint(equalToConstant: 30),
            decreaseFontButton.heightAnchor.constraint(equalToConstant: 24),
            increaseFontButton.widthAnchor.constraint(equalToConstant: 30),
            increaseFontButton.heightAnchor.constraint(equalToConstant: 24),
            automaticThemeButton.widthAnchor.constraint(equalToConstant: 48),
            automaticThemeButton.heightAnchor.constraint(equalToConstant: 24),
            lightThemeButton.widthAnchor.constraint(equalToConstant: 48),
            lightThemeButton.heightAnchor.constraint(equalToConstant: 24),
            darkThemeButton.widthAnchor.constraint(equalToConstant: 48),
            darkThemeButton.heightAnchor.constraint(equalToConstant: 24),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: controlsBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.drawsBackground = true
        configureSoftWrapping(false)
        textView.textLayoutManager?.limitsLayoutForSuspiciousContents = true
        textView.textLayoutManager?.renderingAttributesValidator = { [weak self] layoutManager, fragment in
            MainActor.assumeIsolated {
                self?.validateRenderingAttributes(layoutManager: layoutManager, fragment: fragment)
            }
        }
        scrollView.documentView = textView
        scrollView.controlScrollHandler = { [weak self] event in
            self?.handleControlScroll(event)
        }
        textView.keyEquivalentHandler = { [weak self] event in
            self?.handleFontSizeKeyEquivalent(event) ?? false
        }
        updateFontButtonState()
        updateThemeButtonState()
        applyCurrentTheme()
    }

    private func configureFontButton(
        _ button: NSButton,
        identifier: String,
        accessibilityLabel: String,
        toolTip: String,
        keyEquivalent: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        button.toolTip = toolTip
        button.keyEquivalent = keyEquivalent
        button.keyEquivalentModifierMask = [.command]
        // Keep AppKit's native tracking loop and allow repeated clicks to invoke
        // the button action independently.
        button.ignoresMultiClick = false
        button.setAccessibilityLabel(accessibilityLabel)
    }

    private func configureThemeButton(
        _ button: NSButton,
        identifier: String,
        accessibilityLabel: String,
        toolTip: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.target = self
        button.action = action
        button.setButtonType(.toggle)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        button.toolTip = toolTip
        button.setAccessibilityLabel(accessibilityLabel)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeKeyboardMonitor()
            systemHotKeyMonitor.stop()
        } else {
            installKeyboardMonitor()
            systemHotKeyMonitor.start()
        }
    }

    private func installKeyboardMonitor() {
        guard keyDownMonitor.value == nil else { return }
        keyDownMonitor.value = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local event monitors run on the main thread. The box makes that AppKit
            // guarantee explicit to Swift 6 without transferring NSEvent elsewhere.
            let eventBox = MainThreadEventBox(event)
            MainActor.assumeIsolated {
                guard let monitoredEvent = eventBox.event, let self else { return }
                eventBox.event = self.filterMonitoredKeyDown(monitoredEvent)
            }
            return eventBox.event
        }
    }

    private func removeKeyboardMonitor() {
        guard let token = keyDownMonitor.value else { return }
        NSEvent.removeMonitor(token)
        keyDownMonitor.value = nil
    }

    func filterMonitoredKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let window else { return event }
        let belongsToWindow = event.window === window ||
            event.windowNumber == window.windowNumber ||
            (event.windowNumber == 0 && window.isKeyWindow)
        guard belongsToWindow else { return event }
        return handleFontSizeKeyEquivalent(event) ? nil : event
    }

    func reset(message: String = "Loading preview…") {
        displayPlainText(message, requiresSoftWrap: false)
    }

    func replace(with first: HighlightedChunk) {
        displayPlainText(first.text, requiresSoftWrap: TextLayoutPolicy.requiresSoftWrap(first.text))
        appendHighlightBatch(HighlightedRangeBatch(
            range: NSRange(location: 0, length: (first.text as NSString).length),
            spans: first.spans
        ))
    }

    func append(_ chunk: HighlightedChunk) {
        guard let storage = textView.textStorage else { return }
        let offset = storage.length
        storage.append(NSAttributedString(string: chunk.text, attributes: storageBaseAttributes))
        let spans = chunk.spans.map {
            TokenSpan(offset + $0.range.location, $0.range.length, $0.kind)
        }
        appendHighlightBatch(HighlightedRangeBatch(
            range: NSRange(location: offset, length: (chunk.text as NSString).length),
            spans: spans
        ))
    }

    func appendTruncationNotice(fileSize: UInt64) {
        let size = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        let text = "\n\nPreview truncated for performance. File size: \(size).\n"
        append(HighlightedChunk(
            text: text,
            spans: [TokenSpan(0, (text as NSString).length, .comment)]
        ))
    }

    func displayPlainText(_ text: String, requiresSoftWrap: Bool) {
        tokenIndex.reset()
        configureSoftWrapping(requiresSoftWrap)
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: text,
            attributes: storageBaseAttributes
        ))
        firstViewportValidationPending = true
        invalidateAllRenderingAttributes()
    }

    func appendHighlightBatch(_ batch: HighlightedRangeBatch) {
        guard let storage = textView.textStorage else { return }
        let documentRange = NSRange(location: 0, length: storage.length)
        guard NSIntersectionRange(documentRange, batch.range) == batch.range else { return }
        tokenIndex.append(batch)
        applyHeadingFonts(in: batch.range)
        // TextKit 2 can cache the base attributes in fragments created before an
        // asynchronous highlight batch arrives. Invalidate that cache, then
        // reinstall the attributes synchronously so visible fragments recolor now
        // while the validator remains the lazy fallback for later fragments.
        applyRenderingAttributes(in: batch.range)
    }

    var highlightedTokenCount: Int { tokenIndex.count }
    var renderedFontSize: CGFloat { cachedRegularFont.pointSize }

    func foregroundColor(atUTF16Offset offset: Int) -> NSColor {
        foregroundAndFont(atUTF16Offset: offset).color
    }

    func foregroundAndFont(atUTF16Offset offset: Int) -> (color: NSColor, font: NSFont) {
        var color = baseRenderingAttributes[.foregroundColor] as? NSColor ?? activeTheme.foreground.nsColor
        let storageFont = textView.textStorage.flatMap { storage -> NSFont? in
            guard offset >= 0, offset < storage.length else { return nil }
            return storage.attribute(.font, at: offset, effectiveRange: nil) as? NSFont
        }
        let font = storageFont ?? cachedRegularFont
        tokenIndex.forEachSpan(intersecting: NSRange(location: offset, length: 1)) { span in
            if let tokenColor = tokenRenderingAttributes[span.kind]?[.foregroundColor] as? NSColor {
                color = tokenColor
            }
        }
        return (color, font)
    }

    @objc private func decreaseFontSize(_ sender: Any?) {
        adjustFontSize(by: -1)
    }

    @objc private func increaseFontSize(_ sender: Any?) {
        adjustFontSize(by: 1)
    }

    @objc private func selectAutomaticTheme(_ sender: Any?) {
        setThemePreference(.automatic)
    }

    @objc private func selectLightTheme(_ sender: Any?) {
        setThemePreference(.light)
    }

    @objc private func selectDarkTheme(_ sender: Any?) {
        setThemePreference(.dark)
    }

    func setThemePreference(_ preference: PreviewThemePreference, persist: Bool = true) {
        themePreference = preference
        if persist {
            userDefaults.set(preference.rawValue, forKey: Self.themePreferenceDefaultsKey)
        }
        updateThemeButtonState()
        applyCurrentTheme()
    }

    func adjustFontSize(by steps: Int) {
        guard steps != 0 else { return }
        let requestedSize = fontSize + CGFloat(steps)
        let boundedSize = min(max(requestedSize, Self.minimumFontSize), Self.maximumFontSize)
        guard boundedSize != fontSize else {
            updateFontButtonState()
            return
        }

        fontSize = boundedSize
        applyFontSize()
        updateFontButtonState()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleFontSizeKeyEquivalent(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleFontSizeKeyEquivalent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option) else {
            return false
        }

        let characters = event.characters ?? ""
        let charactersIgnoringModifiers = event.charactersIgnoringModifiers ?? ""
        if characters == "+" || charactersIgnoringModifiers == "+" || charactersIgnoringModifiers == "=" {
            adjustFontSize(by: 1)
            return true
        }
        if characters == "-" || charactersIgnoringModifiers == "-" {
            adjustFontSize(by: -1)
            return true
        }
        return false
    }

    private func handleControlScroll(_ event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else {
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                preciseScrollAccumulator = 0
            }
            return
        }

        if event.hasPreciseScrollingDeltas {
            if event.phase.contains(.began) { preciseScrollAccumulator = 0 }
            preciseScrollAccumulator += delta
            let steps = Int(abs(preciseScrollAccumulator) / Self.preciseScrollStep)
            if steps > 0 {
                let direction = preciseScrollAccumulator > 0 ? 1 : -1
                adjustFontSize(by: direction * steps)
                preciseScrollAccumulator -= CGFloat(direction * steps) * Self.preciseScrollStep
            }
        } else {
            adjustFontSize(by: delta > 0 ? 1 : -1)
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            preciseScrollAccumulator = 0
        }
    }

    private var storageBaseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: cachedRegularFont,
            .foregroundColor: activeTheme.foreground.nsColor
        ]
    }

    private func configureSoftWrapping(_ enabled: Bool) {
        isSoftWrappingEnabled = enabled
        textView.isHorizontallyResizable = !enabled
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = enabled
        textView.textContainer?.containerSize = NSSize(
            width: enabled ? max(1, scrollView.contentSize.width) : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.hasHorizontalScroller = !enabled
    }

    private func rebuildThemeCache() {
        activeTheme = currentTheme
        cachedRegularFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        cachedHeadingFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        baseRenderingAttributes = [
            .foregroundColor: activeTheme.foreground.nsColor
        ]
        tokenRenderingAttributes = Dictionary(uniqueKeysWithValues: TokenKind.allCases.map { kind in
            (kind, [.foregroundColor: activeTheme.color(for: kind).nsColor])
        })
    }

    private func applyStorageFonts() {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let documentRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.font, value: cachedRegularFont, range: documentRange)
        tokenIndex.forEachSpan(intersecting: documentRange) { span in
            guard span.kind == .heading else { return }
            storage.addAttribute(.font, value: cachedHeadingFont, range: span.range)
        }
        storage.endEditing()
    }

    private func applyHeadingFonts(in range: NSRange) {
        guard let storage = textView.textStorage, range.length > 0 else { return }
        var headingRanges: [NSRange] = []
        tokenIndex.forEachSpan(intersecting: range) { span in
            guard span.kind == .heading else { return }
            let intersection = NSIntersectionRange(span.range, range)
            guard intersection.length > 0 else { return }
            headingRanges.append(intersection)
        }
        guard !headingRanges.isEmpty else { return }
        storage.beginEditing()
        for headingRange in headingRanges {
            storage.addAttribute(.font, value: cachedHeadingFont, range: headingRange)
        }
        storage.endEditing()
    }

    private func validateRenderingAttributes(
        layoutManager: NSTextLayoutManager,
        fragment: NSTextLayoutFragment
    ) {
        guard
            let contentManager = layoutManager.textContentManager,
            let fragmentRange = nsRange(for: fragment.rangeInElement, contentManager: contentManager)
        else { return }

        applyRenderingAttributes(
            in: fragmentRange,
            layoutManager: layoutManager,
            contentManager: contentManager,
            schedulesViewportRefresh: false
        )

        if firstViewportValidationPending {
            firstViewportValidationPending = false
            PreviewPerformance.event("FirstViewportValidated")
        }
    }

    private func textRange(
        for range: NSRange,
        contentManager: NSTextContentManager
    ) -> NSTextRange? {
        let documentStart = contentManager.documentRange.location
        guard
            range.location >= 0,
            range.length >= 0,
            let start = contentManager.location(documentStart, offsetBy: range.location),
            let end = contentManager.location(start, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    private func nsRange(
        for textRange: NSTextRange,
        contentManager: NSTextContentManager
    ) -> NSRange? {
        let documentStart = contentManager.documentRange.location
        let location = contentManager.offset(from: documentStart, to: textRange.location)
        let length = contentManager.offset(from: textRange.location, to: textRange.endLocation)
        guard location >= 0, length >= 0 else { return nil }
        return NSRange(location: location, length: length)
    }

    private func applyRenderingAttributes(in range: NSRange) {
        guard
            let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager,
            let rangeToRender = textRange(for: range, contentManager: contentManager)
        else { return }
        layoutManager.invalidateRenderingAttributes(for: rangeToRender)
        applyRenderingAttributes(
            in: range,
            layoutManager: layoutManager,
            contentManager: contentManager,
            schedulesViewportRefresh: true
        )
    }

    private func applyRenderingAttributes(
        in range: NSRange,
        layoutManager: NSTextLayoutManager,
        contentManager: NSTextContentManager,
        schedulesViewportRefresh: Bool
    ) {
        guard
            range.length > 0,
            let rangeToRender = textRange(for: range, contentManager: contentManager)
        else { return }

        layoutManager.setRenderingAttributes(baseRenderingAttributes, for: rangeToRender)
        tokenIndex.forEachSpan(intersecting: range) { span in
            let intersection = NSIntersectionRange(span.range, range)
            guard
                intersection.length > 0,
                let tokenRange = textRange(for: intersection, contentManager: contentManager),
                let attributes = tokenRenderingAttributes[span.kind]
            else { return }
            layoutManager.setRenderingAttributes(attributes, for: tokenRange)
        }

        guard schedulesViewportRefresh else { return }

        let viewportController = layoutManager.textViewportLayoutController
        guard
            let viewport = viewportController.viewportRange,
            let viewportRange = nsRange(for: viewport, contentManager: contentManager)
        else {
            scheduleViewportRenderingRefresh()
            return
        }
        if NSIntersectionRange(viewportRange, range).length > 0 {
            scheduleViewportRenderingRefresh()
        }
    }

    private func invalidateAllRenderingAttributes() {
        guard
            let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager,
            let documentRange = nsRange(for: contentManager.documentRange, contentManager: contentManager),
            documentRange.length > 0
        else { return }
        layoutManager.invalidateRenderingAttributes(for: contentManager.documentRange)
        // Reinstall the attributes synchronously. This both refreshes fragments
        // that are already visible and leaves the validator as the lazy fallback
        // for fragments TextKit creates later.
        applyRenderingAttributes(
            in: documentRange,
            layoutManager: layoutManager,
            contentManager: contentManager,
            schedulesViewportRefresh: true
        )
    }

    private func scheduleViewportRenderingRefresh() {
        guard !viewportRenderingRefreshScheduled else { return }
        viewportRenderingRefreshScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.viewportRenderingRefreshScheduled = false
            self.viewportRenderingRefreshCount += 1
            if let layoutManager = self.textView.textLayoutManager {
                let viewportController = layoutManager.textViewportLayoutController
                if let viewportRange = viewportController.viewportRange {
                    layoutManager.ensureLayout(for: viewportRange)
                }
                viewportController.layoutViewport()
            }
            self.textView.needsDisplay = true
        }
    }

    private func applyFontSize() {
        let interval = PreviewPerformance.signposter.beginInterval("ApplyFontSize")
        defer {
            PreviewPerformance.signposter.endInterval("ApplyFontSize", interval)
        }
        rebuildThemeCache()
        // Font is a layout-affecting attribute. TextKit 2 intentionally ignores
        // it in rendering attributes, which are only for paint-time styling.
        // Update NSTextStorage so both glyph metrics and drawing use the new size.
        applyStorageFonts()
        invalidateAllRenderingAttributes()
    }

    private func updateFontButtonState() {
        decreaseFontButton.isEnabled = fontSize > Self.minimumFontSize
        increaseFontButton.isEnabled = fontSize < Self.maximumFontSize
    }

    private func updateThemeButtonState() {
        updateThemeButton(automaticThemeButton, isSelected: themePreference == .automatic)
        updateThemeButton(lightThemeButton, isSelected: themePreference == .light)
        updateThemeButton(darkThemeButton, isSelected: themePreference == .dark)
    }

    private func updateThemeButton(_ button: NSButton, isSelected: Bool) {
        button.state = isSelected ? .on : .off
        button.font = NSFont.systemFont(ofSize: 11, weight: isSelected ? .bold : .medium)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard !isApplyingTheme else { return }
        applyCurrentTheme()
    }

    private var currentTheme: VSCode2026Theme {
        switch themePreference {
        case .automatic:
            effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    private func applyCurrentTheme() {
        guard !isApplyingTheme else { return }
        isApplyingTheme = true
        defer { isApplyingTheme = false }

        let requestedAppearanceName: NSAppearance.Name?
        switch themePreference {
        case .automatic:
            requestedAppearanceName = nil
        case .light:
            requestedAppearanceName = .aqua
        case .dark:
            requestedAppearanceName = .darkAqua
        }
        if appearance?.name != requestedAppearanceName {
            appearance = requestedAppearanceName.flatMap(NSAppearance.init(named:))
        }

        rebuildThemeCache()
        textView.backgroundColor = activeTheme.background.nsColor
        scrollView.backgroundColor = activeTheme.background.nsColor
        controlsBar.wantsLayer = true
        controlsBar.layer?.backgroundColor = activeTheme.background.nsColor.cgColor
        invalidateAllRenderingAttributes()
    }

    deinit {
        if let token = keyDownMonitor.value {
            NSEvent.removeMonitor(token)
        }
    }
}

private extension ThemeRGBColor {
    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}
