import AppKit
import QuickSourceCore

@MainActor
final class CodePreviewView: NSView {
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
        textView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
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
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.textColor]
    }

    private func attributed(_ chunk: HighlightedChunk) -> NSAttributedString {
        let value = NSMutableAttributedString(string: chunk.text, attributes: baseAttributes)
        for span in chunk.spans where isValid(span.range, forLength: value.length) {
            value.addAttribute(.foregroundColor, value: color(for: span.kind), range: span.range)
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

    private func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .plain: .textColor
        case .comment: .secondaryLabelColor
        case .string: .systemRed
        case .number: .systemBlue
        case .keyword: .systemPurple
        case .literal: .systemIndigo
        case .variable: .systemTeal
        case .property: .systemBrown
        case .operator, .punctuation: .tertiaryLabelColor
        case .directive: .systemOrange
        case .heading: .labelColor
        case .link: .linkColor
        case .code: .systemGreen
        }
    }
}
