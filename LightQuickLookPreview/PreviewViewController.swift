import AppKit
import QuickLookUI
import LightQuickLookCore

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
            let preparation = PreviewPerformance.signposter.beginInterval("PreparePreview")
            var preparationEnded = false
            defer {
                if !preparationEnded {
                    PreviewPerformance.signposter.endInterval("PreparePreview", preparation)
                }
            }
            do {
                let loading = PreviewPerformance.signposter.beginInterval("LoadAndDecode")
                let document: PreviewDocument
                let initialHighlight: HighlightedBatchProgress?
                do {
                    (document, initialHighlight) = try await Task.detached(priority: .userInitiated) {
                        try Task.checkCancellation()
                        let loadedDocument = try PreviewFileLoader.load(url: url)
                        let firstBatch = try HighlightPipeline.initialBatch(
                            text: loadedDocument.text,
                            language: loadedDocument.language,
                            cancellation: .currentTask
                        )
                        return (loadedDocument, firstBatch)
                    }.value
                } catch {
                    PreviewPerformance.signposter.endInterval("LoadAndDecode", loading)
                    throw error
                }
                PreviewPerformance.signposter.endInterval("LoadAndDecode", loading)
                try Task.checkCancellation()
                guard let self else { handler(CancellationError()); return }

                let sourceUTF16Length = (document.text as NSString).length
                var displayText = document.text
                var truncationBatch: HighlightedRangeBatch?
                if document.isTruncated {
                    let size = ByteCountFormatter.string(fromByteCount: Int64(document.fileSize), countStyle: .file)
                    let notice = "\n\nPreview truncated for performance. File size: \(size).\n"
                    let noticeRange = NSRange(location: sourceUTF16Length, length: (notice as NSString).length)
                    displayText.append(notice)
                    truncationBatch = HighlightedRangeBatch(
                        range: noticeRange,
                        spans: [TokenSpan(noticeRange.location, noticeRange.length, .comment)]
                    )
                }

                let installingText = PreviewPerformance.signposter.beginInterval("InstallPlainText")
                self.codeView.displayPlainText(
                    displayText,
                    requiresSoftWrap: document.requiresSoftWrap
                )
                if let initialHighlight {
                    self.codeView.appendHighlightBatch(initialHighlight.batch)
                    PreviewPerformance.event("InitialHighlightInstalled")
                }
                if let truncationBatch { self.codeView.appendHighlightBatch(truncationBatch) }
                PreviewPerformance.signposter.endInterval("InstallPlainText", installingText)
                PreviewPerformance.event("PlainTextInstalled")

                // Present the preview only after the small first highlight batch is
                // installed. Remaining colors continue to arrive incrementally.
                handler(nil)
                completionSent = true
                PreviewPerformance.event("CompletionHandlerCalled")
                PreviewPerformance.signposter.endInterval("PreparePreview", preparation)
                preparationEnded = true

                let continuationLocation = initialHighlight.map { NSMaxRange($0.batch.range) } ?? 0
                let continuationState = initialHighlight?.stateAfter ?? .normal
                guard continuationLocation < sourceUTF16Length else { return }

                let highlighting = PreviewPerformance.signposter.beginInterval("BackgroundHighlighting")
                let worker = Task.detached(priority: .userInitiated) { [self] in
                    try await HighlightPipeline.enumerateBatchesAsync(
                        text: document.text,
                        language: document.language,
                        startingAtUTF16Location: continuationLocation,
                        initialState: continuationState,
                        initialTargetUTF16Length: PreviewPolicy.highlightChunkUTF16Length,
                        cancellation: .currentTask
                    ) { batch in
                        try Task.checkCancellation()
                        await self.appendHighlightBatch(batch)
                    }
                }
                do {
                    try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                } catch {
                    worker.cancel()
                    PreviewPerformance.signposter.endInterval("BackgroundHighlighting", highlighting)
                    throw error
                }
                PreviewPerformance.signposter.endInterval("BackgroundHighlighting", highlighting)
            } catch is CancellationError {
                if !completionSent { handler(CancellationError()) }
            } catch TextDecodeError.binary {
                self?.codeView.reset(message: "This file appears to contain binary data and cannot be previewed as source text.")
                if !completionSent { handler(nil) }
            } catch TextDecodeError.unsupportedEncoding {
                self?.codeView.reset(message: "This file uses an unsupported or malformed text encoding.")
                if !completionSent { handler(nil) }
            } catch {
                if !completionSent {
                    self?.codeView.reset(message: "The file could not be read.")
                    handler(error)
                } else {
                    PreviewPerformance.event("BackgroundHighlightingFailed")
                }
            }
        }
    }

    private func appendHighlightBatch(_ batch: HighlightedRangeBatch) {
        codeView.appendHighlightBatch(batch)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        previewTask?.cancel()
    }

    deinit { previewTask?.cancel() }
}
