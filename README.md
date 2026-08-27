# LightQuickLook

LightQuickLook is a minimal native macOS Quick Look viewer for source and configuration files. Select a supported file in Finder and press Space to see selectable, copyable, scrollable source with lightweight syntax highlighting.

## Supported formats

- YAML: `.yaml`, `.yml`
- JSON: `.json`
- PowerShell: `.ps1`, `.psm1`, `.psd1`
- Bash/shell: `.sh`, `.bash`
- Terraform/HCL: `.tf`, `.tfvars`, `.hcl`

Markdown (`.md`, `.markdown`) is intentionally not registered. It remains available to dedicated preview extensions such as Markdown Preview.

## Platform

- macOS 26.0 or newer
- Apple Silicon (`arm64`) only

Intel Macs (`x86_64`) and older macOS releases are not supported.

## Prebuilt release

Prebuilt versions are published on the [GitHub Releases](https://github.com/uponom/LightQuickLook/releases) page as:

```text
LightQuickLook-1.0.0-unnotarized.dmg
LightQuickLook-1.0.0-unnotarized-SHA256.txt
```

LightQuickLook is free, open-source software and the project does not purchase an Apple Developer Program membership. The prebuilt application therefore has a consistent ad hoc code signature, but it is **not signed with an Apple Developer ID certificate and is not notarized by Apple**. macOS cannot verify the developer or confirm that Apple scanned the downloaded application, so Gatekeeper will warn or block the first launch.

The source for every release is available under its version tag. The accompanying SHA-256 file lets you verify that the downloaded DMG matches the release asset, but it does not replace Developer ID verification or Apple notarization.

### Install the prebuilt application

1. Download `LightQuickLook-1.0.0-unnotarized.dmg` and its SHA-256 file from GitHub Releases.
2. Optionally verify the download from Terminal:

   ```sh
   cd ~/Downloads
   shasum -a 256 LightQuickLook-1.0.0-unnotarized.dmg
   cat LightQuickLook-1.0.0-unnotarized-SHA256.txt
   ```

   The two hashes must match.
3. Open the DMG and drag `LightQuickLook.app` onto the `Applications` shortcut.
4. Open `/Applications/LightQuickLook.app`. Gatekeeper may block the first attempt because the app is not Developer ID-signed or notarized.
5. If it is blocked, open System Settings → Privacy & Security, scroll to Security, click **Open Anyway**, then confirm **Open**. Only bypass this warning if you downloaded the app from this repository and accept the unnotarized-build limitation.
6. Launch LightQuickLook once so Launch Services discovers its embedded extension.
7. Open System Settings → General → Login Items & Extensions → Quick Look and enable LightQuickLook.
8. Select a supported file in Finder and press Space.

The **Open Anyway** option appears only after a blocked launch attempt. A managed Mac may prevent users from overriding Gatekeeper policy.

## Design

The app embeds a modern view-based Quick Look Preview Extension. Preview rendering uses only `NSScrollView`, `NSTextView`, and attributed source text. The Foundation core performs bounded decoding and deterministic lexical highlighting in cancellable background tasks. The original source is not parsed into objects, reformatted, rendered as HTML, or executed.

Shipping dependencies are Apple system frameworks only. There are no Swift packages, CocoaPods, grammar databases, JavaScript runtimes, network calls, telemetry, helper processes, or copied third-party source.

The preview follows the system appearance using palettes based on VS Code Dark 2026 and Light 2026, including relevant inherited Dark+/Light+ scope precedence. Operators and brackets deliberately use the full editor foreground color for reliable contrast.

Font size can be changed for the current preview with the `−` and `+` controls above the source, with `⌘−` and `⌘+`, or by scrolling while holding Control. The supported range is 8–32 pt. Scaling uses native `NSScrollView` magnification, so changing the size does not rebuild the highlighted text even for large previews.

See [Architecture](Docs/ARCHITECTURE.md), [Theming](Docs/THEMING.md), [UTI research](Docs/UTI-Research.md), [Security](Docs/SECURITY.md), the [2026-08-11 security audit](Docs/SECURITY-AUDIT.md), and [Performance](Docs/PERFORMANCE.md).

## Build from source

Building from source avoids relying on the downloadable binary, but requires Xcode 26 or newer. Clone the repository and run the tests:

```sh
git clone https://github.com/uponom/LightQuickLook.git
cd LightQuickLook
xcodebuild -list -project LightQuickLook.xcodeproj
xcodebuild test -project LightQuickLook.xcodeproj -scheme LightQuickLook -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

Then open `LightQuickLook.xcodeproj` in Xcode, select the `LightQuickLook` scheme, and build it. Xcode can use **Sign to Run Locally** without a paid Developer ID certificate. Copy the resulting `LightQuickLook.app` to `/Applications`, launch it once, and enable the extension as described above.

To reproduce the ad hoc-signed DMG used by GitHub Releases:

```sh
Scripts/build-release-dmg.sh
```

The script runs the complete test suite, builds an optimized `arm64` Release, verifies the host and extension signatures and architectures, and writes the DMG plus SHA-256 file to `dist/`.

The pure Swift core can also be compiled and smoke-tested without third-party tools:

```sh
swift run LightQuickLookSelfTest
swift run -c release LightQuickLookBenchmark
```

`Package.swift` is a local testing/benchmark harness only; the Xcode production targets have no package dependency.

## Install a local Xcode build

1. Open `LightQuickLook.xcodeproj` in Xcode and select “Sign to Run Locally” or your development team for both the app and extension.
2. Build the `LightQuickLook` scheme.
3. Copy `LightQuickLook.app` to `/Applications` (or run it once from Xcode) and launch it once so Launch Services discovers the embedded extension.
4. Open System Settings → General → Login Items & Extensions → Quick Look and enable LightQuickLook if it is listed but disabled.
5. Select a sample file in Finder and press Space.

Verify registration with:

```sh
Scripts/diagnose-quicklook.sh /Applications/LightQuickLook.app
```

## Troubleshooting

- If previews do not appear, confirm the extension is enabled, move/relaunch the app, and inspect `pluginkit -mAvvv -p com.apple.quicklook.preview`.
- macOS tracks extension-bearing app bundles by both identity and path. Building the same app into many `DerivedData` or temporary product directories can therefore create duplicate entries in System Settings. Keep one installed/registered copy, remove obsolete build products, and reopen System Settings after cleanup.
- Finder handler precedence can change when other preview applications are installed. Restart Finder or log out/in after changing competing extensions.
- PowerShell and HCL use application-owned exported UTIs declared by the host because macOS otherwise assigns machine-specific `dyn.*` types.
- Supporting `.sh` requires `public.shell-script`. This may also make LightQuickLook a candidate for Ruby, Perl, PHP, and zsh files; those unsupported extensions safely fall back to plain text. Details and evidence are in `Docs/UTI-Research.md`.

## Current limitations

- Lexical highlighting is intentionally incomplete and does not validate syntax.
- Files larger than 8 MiB are truncated in the preview.
- UTF-8, UTF-8 BOM, UTF-16 LE BOM, UTF-16 BE BOM, and a Windows-1252 fallback are supported; there is no general encoding detector.
- No line numbers, folding, user-selectable themes, editing, nested fenced-language highlighting, or extensionless-file registration.

## Uninstall

Delete `LightQuickLook.app`. There is no background service, login item, preferences database, or helper to remove.

## License

MIT — see [LICENSE](LICENSE).
