import AppKit
import QuickLookUI
import QuickSourceCore

@MainActor
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {
    private let codeView = CodePreviewView()
    private var previewTask: Task<Void, Never>?

    override func loadView() {
        view = codeView
        preferredContentSize = NSSize(width: 900, height: 650)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        previewTask?.cancel()
        codeView.reset()
        previewTask = Task { [weak self] in
            var completionSent = false
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    return try PreviewFileLoader.load(url: url)
                }.value
                try Task.checkCancellation()
                let textChunks = await Task.detached(priority: .userInitiated) {
                    TextChunker.split(text: document.text)
                }.value
                try Task.checkCancellation()
                guard let self else { handler(CancellationError()); return }
                let highlighter = HighlighterFactory.make(for: document.language)
                var state = LexerState.normal
                for (index, textChunk) in textChunks.enumerated() {
                    try Task.checkCancellation()
                    let inputState = state
                    let result = await Task.detached(priority: .userInitiated) {
                        highlighter.highlight(textChunk, state: inputState)
                    }.value
                    state = result.state
                    let chunk = HighlightedChunk(text: textChunk, spans: result.spans)
                    if index == 0 {
                        self.codeView.replace(with: chunk)
                        handler(nil)
                        completionSent = true
                    } else {
                        self.codeView.append(chunk)
                    }
                    await Task.yield()
                }
                if document.isTruncated { self.codeView.appendTruncationNotice(fileSize: document.fileSize) }
            } catch is CancellationError {
                if !completionSent { handler(CancellationError()) }
            } catch TextDecodeError.binary {
                self?.codeView.reset(message: "This file appears to contain binary data and cannot be previewed as source text.")
                if !completionSent { handler(nil) }
            } catch TextDecodeError.unsupportedEncoding {
                self?.codeView.reset(message: "This file uses an unsupported or malformed text encoding.")
                if !completionSent { handler(nil) }
            } catch {
                self?.codeView.reset(message: "The file could not be read.")
                if !completionSent { handler(error) }
            }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        previewTask?.cancel()
    }

    deinit { previewTask?.cancel() }
}
