# QuickSourceLook

QuickSourceLook is a minimal native macOS Quick Look viewer for source and configuration files. Select a supported file in Finder and press Space to see selectable, copyable, scrollable source with lightweight syntax highlighting.

## Supported formats

- YAML: `.yaml`, `.yml`
- JSON: `.json`
- PowerShell: `.ps1`, `.psm1`, `.psd1`
- Bash/shell: `.sh`, `.bash`
- Terraform/HCL: `.tf`, `.tfvars`, `.hcl`
- Markdown source: `.md`, `.markdown`

Minimum system: macOS 26.0. Apple Silicon is the primary target; the project does not hard-code an architecture and can be configured for a future Universal build.

## Design

The app embeds a modern view-based Quick Look Preview Extension. Preview rendering uses only `NSScrollView`, `NSTextView`, and attributed source text. The Foundation core performs bounded decoding and deterministic lexical highlighting in cancellable background tasks. The original source is not parsed into objects, reformatted, rendered as HTML, or executed.

Shipping dependencies are Apple system frameworks only. There are no Swift packages, CocoaPods, grammar databases, JavaScript runtimes, network calls, telemetry, helper processes, or copied third-party source.

See [Architecture](Docs/ARCHITECTURE.md), [UTI research](Docs/UTI-Research.md), [Security](Docs/SECURITY.md), the [2026-08-11 security audit](Docs/SECURITY-AUDIT.md), and [Performance](Docs/PERFORMANCE.md).

## Build and test

Full app/extension builds require Xcode 26 or newer:

```sh
xcodebuild -list -project QuickSourceLook.xcodeproj
xcodebuild test -project QuickSourceLook.xcodeproj -scheme QuickSourceLook -destination 'platform=macOS'
xcodebuild build -project QuickSourceLook.xcodeproj -scheme QuickSourceLook -configuration Release -destination 'platform=macOS' CODE_SIGN_IDENTITY=-
```

The pure Swift core can also be compiled and smoke-tested without third-party tools:

```sh
swift run QuickSourceSelfTest
swift run -c release QuickSourceBenchmark
```

`Package.swift` is a local testing/benchmark harness only; the Xcode production targets have no package dependency.

## Install and enable locally

1. Open `QuickSourceLook.xcodeproj` in Xcode and select “Sign to Run Locally” or your development team for both the app and extension.
2. Build the `QuickSourceLook` scheme.
3. Copy `QuickSourceLook.app` to `/Applications` (or run it once from Xcode) and launch it once so Launch Services discovers the embedded extension.
4. Open System Settings → General → Login Items & Extensions → Quick Look and enable QuickSourceLook if it is listed but disabled.
5. Select a sample file in Finder and press Space.

Verify registration with:

```sh
Scripts/diagnose-quicklook.sh /Applications/QuickSourceLook.app
```

## Troubleshooting

- If previews do not appear, confirm the extension is enabled, move/relaunch the app, and inspect `pluginkit -mAvvv -p com.apple.quicklook.preview`.
- Finder handler precedence can change when other preview applications are installed. Restart Finder or log out/in after changing competing extensions.
- PowerShell and HCL use imported UTIs declared by the host because macOS otherwise assigns machine-specific `dyn.*` types.
- Supporting `.sh` requires `public.shell-script`. This may also make QuickSourceLook a candidate for Ruby, Perl, PHP, and zsh files; those unsupported extensions safely fall back to plain text. Details and evidence are in `Docs/UTI-Research.md`.

## Current limitations

- Lexical highlighting is intentionally incomplete and does not validate syntax.
- Markdown is shown as source, not rendered HTML.
- Files larger than 8 MiB are truncated in the preview.
- UTF-8, UTF-8 BOM, UTF-16 LE BOM, UTF-16 BE BOM, and a Windows-1252 fallback are supported; there is no general encoding detector.
- No line numbers, folding, themes, editing, nested fenced-language highlighting, or extensionless-file registration.

## Uninstall

Delete `QuickSourceLook.app`. There is no background service, login item, preferences database, or helper to remove.

## License

MIT — see [LICENSE](LICENSE).
