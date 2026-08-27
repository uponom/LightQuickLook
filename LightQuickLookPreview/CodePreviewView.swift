import AppKit
import LightQuickLookCore

private final class MainThreadEventBox: @unchecked Sendable {
    var event: NSEvent?

    init(_ event: NSEvent) {
        self.event = event
    }
}

private final class EventMonitorToken: @unchecked Sendable {
    var value: Any?
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

    private static let tokenKindAttribute = NSAttributedString.Key("io.github.uponom.LightQuickLook.tokenKind")
    private static let preciseScrollStep: CGFloat = 8
    private let controlsBar = NSView()
    private let separator = NSBox()
    private let scrollView = FontZoomScrollView()
    // Construct the text system explicitly with NSTextLayoutManager. Using the
    // frame initializer would silently create the TextKit 1 compatibility stack.
    private let textView = FontZoomTextView(usingTextLayoutManager: true)
    private let decreaseFontButton = NSButton(title: "−", target: nil, action: nil)
    private let increaseFontButton = NSButton(title: "+", target: nil, action: nil)
    private(set) var fontSize = CodePreviewView.defaultFontSize
    private var preciseScrollAccumulator: CGFloat = 0
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
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
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

        let controls = NSStackView(views: [decreaseFontButton, increaseFontButton])
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 6
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
        scrollView.minMagnification = Self.minimumFontSize / Self.defaultFontSize
        scrollView.maxMagnification = Self.maximumFontSize / Self.defaultFontSize
        scrollView.magnification = 1
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
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = true
        scrollView.documentView = textView
        scrollView.controlScrollHandler = { [weak self] event in
            self?.handleControlScroll(event)
        }
        textView.keyEquivalentHandler = { [weak self] event in
            self?.handleFontSizeKeyEquivalent(event) ?? false
        }
        updateFontButtonState()
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
        textView.textStorage?.setAttributedString(NSAttributedString(string: message, attributes: baseAttributes))
    }

    func replace(with first: HighlightedChunk) {
        textView.textStorage?.setAttributedString(attributed(first))
    }

    func append(_ chunk: HighlightedChunk) {
        textView.textStorage?.append(attributed(chunk))
    }

    func appendTruncationNotice(fileSize: UInt64) {
        let size = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        let text = "\n\nPreview truncated for performance. File size: \(size).\n"
        textView.textStorage?.append(NSAttributedString(string: text, attributes: [
            .font: regularFont,
            .foregroundColor: currentTheme.color(for: .comment).nsColor,
            Self.tokenKindAttribute: TokenKind.comment.rawValue
        ]))
    }

    @objc private func decreaseFontSize(_ sender: Any?) {
        adjustFontSize(by: -1)
    }

    @objc private func increaseFontSize(_ sender: Any?) {
        adjustFontSize(by: 1)
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
        applyFontMagnification()
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

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: regularFont,
            .foregroundColor: currentTheme.foreground.nsColor
        ]
    }

    private var regularFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: Self.defaultFontSize, weight: .regular)
    }

    private var headingFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: Self.defaultFontSize, weight: .semibold)
    }

    private func attributed(_ chunk: HighlightedChunk) -> NSAttributedString {
        let value = NSMutableAttributedString(string: chunk.text, attributes: baseAttributes)
        for span in chunk.spans where isValid(span.range, forLength: value.length) {
            value.addAttributes([
                .foregroundColor: currentTheme.color(for: span.kind).nsColor,
                Self.tokenKindAttribute: span.kind.rawValue
            ], range: span.range)
            if span.kind == .heading { value.addAttribute(.font, value: headingFont, range: span.range) }
        }
        return value
    }

    private func applyFontMagnification() {
        let visibleCenter = NSPoint(
            x: scrollView.contentView.bounds.midX,
            y: scrollView.contentView.bounds.midY
        )
        scrollView.setMagnification(
            fontSize / Self.defaultFontSize,
            centeredAt: visibleCenter
        )
    }

    private func updateFontButtonState() {
        decreaseFontButton.isEnabled = fontSize > Self.minimumFontSize
        increaseFontButton.isEnabled = fontSize < Self.maximumFontSize
    }

    private func isValid(_ range: NSRange, forLength length: Int) -> Bool {
        range.location >= 0 &&
        range.length >= 0 &&
        range.location <= length &&
        range.length <= length - range.location
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyCurrentTheme()
    }

    private var currentTheme: VSCode2026Theme {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private func applyCurrentTheme() {
        let theme = currentTheme
        textView.backgroundColor = theme.background.nsColor
        scrollView.backgroundColor = theme.background.nsColor
        controlsBar.wantsLayer = true
        controlsBar.layer?.backgroundColor = theme.background.nsColor.cgColor

        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: theme.foreground.nsColor, range: fullRange)
        storage.enumerateAttribute(Self.tokenKindAttribute, in: fullRange) { value, range, _ in
            guard let rawValue = value as? String, let kind = TokenKind(rawValue: rawValue) else { return }
            storage.addAttribute(.foregroundColor, value: theme.color(for: kind).nsColor, range: range)
        }
        storage.endEditing()
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
