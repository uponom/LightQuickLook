# Architecture

LightQuickLook consists of three production targets:

1. `LightQuickLook`, a tiny SwiftUI host that explains extension activation and exports narrow application-owned PowerShell, HCL, and JSON Lines UTIs.
2. `LightQuickLookPreview`, a view-based Quick Look Preview Extension implementing `QLPreviewingController`.
3. `LightQuickLookCore`, a statically linked pure-Foundation library containing decoding, language detection, chunking, and lexical highlighting.

The extension UI is native AppKit: a compact theme and font-size control bar sits above an `NSScrollView` containing a non-editable, selectable `NSTextView`. The text view is explicitly initialized with TextKit 2 (`NSTextLayoutManager`); the legacy frame initializer and TextKit 1 compatibility layout manager are not used. Buttons, native Carbon hotkeys registered only while the preview view is attached to a window, and Control-scroll events share one bounded 8–32 pt font-size state. The hotkeys are necessary because Finder owns the Quick Look window and consumes its Command key equivalents before ordinary AppKit events reach the extension process. Font changes update the layout-affecting font attributes in `NSTextStorage` while retaining the compact syntax-token index, so syntax scanning is not repeated. The buttons use AppKit's native mouse-tracking loop and treat repeated clicks as separate font-size actions. Long pathological lines switch to soft wrapping and TextKit 2 suspicious-content layout protection. No HTML, WebKit, temporary rendered files, or subprocesses are involved.

`CodePreviewView` selects the VS Code 2026 light or dark palette from the persisted automatic/light/dark preference. Token identity is retained in a compact range index, allowing an already open preview to be recolored when the system appearance or explicit theme changes without re-reading or re-highlighting the file.

## Preview pipeline

```text
untrusted URL
  → bounded read (maximum 8 MiB)
  → BOM-aware decoding and binary guard
  → extension-first language detection
  → stateful lexer for the first UTF-16-safe 32 KiB batch off the main actor
  → full plain text plus the first token batch installed on the main actor
  → Quick Look completion handler
  → remaining UTF-16-safe 128 KiB lexer batches on a background task
  → compact TokenSpan values
  → targeted TextKit 2 rendering-attribute invalidation on the main actor
```

The first highlighted chunk completes preparation and becomes visible before Quick Look can materialize the initial viewport with base colors. Later batches invalidate only their affected rendering-attribute ranges before synchronously installing new colors; this refreshes already cached TextKit 2 fragments without rebuilding the document. The controller owns one cancellable `Task`; starting a new preview, closing the view, or deallocation cancels it. File handles are scoped to the bounded load only.

## Syntax model and extension points

`SyntaxHighlighter` accepts source plus a small `LexerState` and returns UTF-16 `NSRange` token spans. Implementations exist for JSON/JSON Lines, YAML, PowerShell, Bash, Terraform/HCL, and source-oriented Markdown. JSON Lines uses the JSON scanner line by line without introducing a separate language mode. They are scanners, not parsers, and do not validate or evaluate input.

Adding a future language requires a new `SourceLanguage` case, extension mapping, lexer, factory branch, tests, and justified UTI declaration. UI and loading code remain unchanged. This is the intended path for adding formats such as additional shell dialects without introducing a grammar runtime.

## Limits

- initial highlight batch: 32 Ki UTF-16 code units;
- subsequent highlight batches: 128 Ki UTF-16 code units;
- bounded file-reading unit: 256 KiB;
- maximum bytes previewed: 8 MiB;
- files larger than the limit receive a neutral truncation notice.

Text is preserved exactly within the byte limit. Registered formats are not reformatted or executed.
