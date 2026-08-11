# Architecture

LightQuickLook consists of three production targets:

1. `LightQuickLook`, a tiny SwiftUI host that explains extension activation and exports narrow application-owned PowerShell/HCL UTIs.
2. `LightQuickLookPreview`, a view-based Quick Look Preview Extension implementing `QLPreviewingController`.
3. `LightQuickLookCore`, a statically linked pure-Foundation library containing decoding, language detection, chunking, and lexical highlighting.

The extension UI is native AppKit: `NSScrollView` contains a non-editable, selectable, no-wrap `NSTextView`. No HTML, WebKit, temporary rendered files, or subprocesses are involved.

## Preview pipeline

```text
untrusted URL
  → bounded read (maximum 8 MiB)
  → BOM-aware decoding and binary guard
  → extension-first language detection
  → UTF-16-safe ~256 KiB text chunks
  → stateful language lexer on a background task
  → compact TokenSpan values
  → attributed NSTextView chunks on the main actor
```

The first highlighted chunk completes preparation and becomes visible before later chunks are processed. The controller owns one cancellable `Task`; starting a new preview, closing the view, or deallocation cancels it. File handles are scoped to the bounded load only.

## Syntax model and extension points

`SyntaxHighlighter` accepts source plus a small `LexerState` and returns UTF-16 `NSRange` token spans. Implementations exist for JSON, YAML, PowerShell, Bash, Terraform/HCL, and source-oriented Markdown. They are scanners, not parsers, and do not validate or evaluate input.

Adding a future language requires a new `SourceLanguage` case, extension mapping, lexer, factory branch, tests, and justified UTI declaration. UI and loading code remain unchanged. This is the intended path for adding formats such as additional shell dialects without introducing a grammar runtime.

## Limits

- eager/initial and processing unit: 256 KiB;
- small-file threshold: 2 MiB;
- maximum bytes previewed: 8 MiB;
- files larger than the limit receive a neutral truncation notice.

Text is preserved exactly within the byte limit. Registered formats are not reformatted or executed.
