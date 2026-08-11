import AppKit
import LightQuickLookCore

@MainActor
final class CodePreviewView: NSView {
    private static let tokenKindAttribute = NSAttributedString.Key("io.github.uponom.LightQuickLook.tokenKind")
    private let scrollView = NSScrollView()
    private let textView = NSTextView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
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
        applyCurrentTheme()
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
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: currentTheme.color(for: .comment).nsColor,
            Self.tokenKindAttribute: TokenKind.comment.rawValue
        ]))
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: currentTheme.foreground.nsColor
        ]
    }

    private func attributed(_ chunk: HighlightedChunk) -> NSAttributedString {
        let value = NSMutableAttributedString(string: chunk.text, attributes: baseAttributes)
        for span in chunk.spans where isValid(span.range, forLength: value.length) {
            value.addAttributes([
                .foregroundColor: currentTheme.color(for: span.kind).nsColor,
                Self.tokenKindAttribute: span.kind.rawValue
            ], range: span.range)
            if span.kind == .heading { value.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold), range: span.range) }
        }
        return value
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
