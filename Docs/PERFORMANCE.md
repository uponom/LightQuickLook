# Performance

## Configuration

- machine: Apple Silicon (`arm64`)
- macOS: 26.6.1 (25G76)
- compiler: Apple Swift 6.3.3
- benchmark SDK: macOS 15.4 compatibility SDK (the installed 26.5 SDK and compiler are mismatched)
- build: SwiftPM Release (`-O`)
- input: synthetic JSON containing ASCII, Cyrillic, umlauts, and emoji
- command: `swift run -c release QuickSourceBenchmark`

These are lexer/attributed-string measurements, not complete Finder Space-bar latency. Full app Release measurement using Xcode 26 remains pending because only Command Line Tools are installed.

| Input bytes | Decode | Highlight/chunk | Attributed construction |
|---:|---:|---:|---:|
| 100 KiB | 0.126 ms | 0.972 ms | 19.607 ms (cold AppKit start) |
| 256 KiB | 0.208 ms | 2.206 ms | 9.900 ms |
| 1 MiB | 0.572 ms | 14.909 ms | 25.800 ms |
| 8 MiB | 3.159 ms | 84.289 ms | 177.425 ms |

Peak RSS for the benchmark process at the 8 MiB case was 135.3 MiB. The benchmark intentionally retains all highlighted chunks to measure complete attribution; the extension processes and appends one chunk at a time, so its token-span lifetime is shorter.

The measured 256 KiB and 1 MiB lexer times are comfortably below the initial 100 ms goals, and the 8 MiB decode + lexical + attribution work totals about 267 ms. AppKit cold-start cost and Finder/Quick Look overhead are separate.

## Bundle size

Not yet measurable without a full Xcode Release product. The project embeds no fonts, grammar databases, JavaScript, third-party frameworks, or image collections, and statically links its own small core.
