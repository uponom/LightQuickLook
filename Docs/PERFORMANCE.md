# Performance

## Configuration

- machine: Apple Silicon (`arm64`)
- macOS: 26.6.1 (25G76)
- compiler: Apple Swift 6.3.3
- Xcode: 26.6 (17F113)
- SDK: macOS 26.5
- build: SwiftPM Release (`-O`)
- input: synthetic JSON containing ASCII, Cyrillic, umlauts, and emoji
- command: `swift run -c release LightQuickLookBenchmark`

These are lexer/attributed-string measurements, not complete Finder Space-bar latency. Real Quick Look YAML and JSON previews were also opened successfully from the final Release bundle.

| Input bytes | Decode | Highlight/chunk | Attributed construction |
|---:|---:|---:|---:|
| 100 KiB | 0.160 ms | 0.932 ms | 54.415 ms (cold AppKit start) |
| 256 KiB | 0.230 ms | 2.436 ms | 11.107 ms |
| 1 MiB | 0.627 ms | 15.829 ms | 27.338 ms |
| 8 MiB | 3.046 ms | 83.416 ms | 216.747 ms |

Peak RSS for the benchmark process at the 8 MiB case was 135.1 MiB. The benchmark intentionally retains all highlighted chunks to measure complete attribution; the extension processes and appends one chunk at a time, so its token-span lifetime is shorter.

The measured 256 KiB and 1 MiB lexer times are comfortably below the initial 100 ms goals, and the 8 MiB decode + lexical + attribution work totals about 303 ms. AppKit cold-start cost and Finder/Quick Look overhead are separate.

Interactive font scaling uses `NSScrollView` magnification. It does not rewrite the attributed text storage or re-run syntax highlighting. A regression test loads a source buffer larger than 200 KiB, performs 20 alternating zoom operations, and verifies that the text storage emits no edit notifications.

The preview text view is explicitly constructed with TextKit 2 (`NSTextLayoutManager`) on macOS 26. Automated coverage verifies that loading attributed content does not fall back to the TextKit 1 compatibility stack. End-to-end viewport and first-frame measurements are tracked separately from the lexer benchmark above.

## Bundle size

The final ad-hoc-signed `arm64` Release product is approximately 484 KiB; its embedded preview extension is approximately 376 KiB, and the compressed DMG is approximately 140 KiB. The project embeds no fonts, grammar databases, JavaScript, third-party frameworks, or image collections, and statically links its own small core.
