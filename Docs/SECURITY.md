# Security and privacy

LightQuickLook treats every previewed file as untrusted bytes.

## Data flow

The only production data flow is local file bytes → bounded decoding → lexical token classification → native attributed text. The app never executes source, evaluates interpolation, follows file references, resolves Terraform modules, loads Markdown resources, or invokes a shell/interpreter.

## Sandbox and entitlements

Both the host and extension entitlements contain only:

```xml
<key>com.apple.security.app-sandbox</key><true/>
```

There is no network client/server, automation, camera, microphone, location, contacts, calendar, accessibility, screen recording, hardware, App Group, or background entitlement. Quick Look grants the extension access to the file being previewed.

## Privacy properties

- network requests: none;
- telemetry, analytics, advertisements, crash-reporting SDKs: none;
- accounts and identifiers: none;
- update checks and background services: none;
- third-party runtime dependencies: zero;
- third-party build dependencies: zero;
- copied external source files: zero.

## Defensive behavior

Reads are capped at 8 MiB. The loader opens the final path without following symbolic links, validates the same descriptor as a regular file, and closes it immediately after loading. BOM checks precede binary heuristics, malformed/unsupported encodings produce a neutral message, and token ranges use overflow-safe bounds checks before attribution. Cancellation is checked during reads and between expensive stages and chunks.

Syntax highlighting retains at most 250,000 token spans per preview. The highlighter stops producing additional spans when that budget is exhausted; the complete decoded text remains readable, while the remainder is displayed with the base text color. This bounds retained token metadata independently of the byte limit.

The Carbon registrations used for Command-minus and Command-plus exist only while the preview window is the key window. They are removed when that window resigns key status, closes, or the preview view leaves its window, and the action handler independently verifies that the preview window is still active before changing its font size.

## Release validation and CI

[`Scripts/build-release-dmg.sh`](../Scripts/build-release-dmg.sh) is the canonical release gate. It treats compiler warnings as errors, runs all tests and the Xcode Release static analyzer, builds an arm64 release, and rejects the result unless both the host app and preview extension:

- pass strict code-signature verification;
- contain exactly one entitlement: App Sandbox;
- have Hardened Runtime in their CodeDirectory flags;
- have matching bundle versions and arm64-only executables.

The script also creates the unnotarized DMG, verifies the disk image, and writes its SHA-256 checksum. [The GitHub Actions workflow](../.github/workflows/security.yml) runs this same complete gate on every pull request and every push to `main` using an Apple-silicon macOS 26 runner. Remote CI status is authoritative only after the workflow has run on GitHub.

## Audit commands

After a full Xcode Release build:

```sh
codesign -d --entitlements :- <app>
codesign -d --entitlements :- <app>/Contents/PlugIns/LightQuickLookPreview.appex
codesign -dv --verbose=4 <app>
codesign -dv --verbose=4 <app>/Contents/PlugIns/LightQuickLookPreview.appex
otool -L <app>/Contents/MacOS/LightQuickLook
otool -L <app>/Contents/PlugIns/LightQuickLookPreview.appex/Contents/MacOS/LightQuickLookPreview
rg -n 'URLSession|NWConnection|Process\(|NSTask|system\(|popen\(|WKWebView|JavaScript' LightQuickLook LightQuickLookPreview LightQuickLookCore
```

The source scan finds no production networking, process execution, WebKit, or JavaScript API use. The final binary/signing inspection passed for an ad-hoc Hardened Runtime build. See [the security audit history](SECURITY-AUDIT.md) for the full checklist, findings, sanitizer results, and the Developer ID/notarization limitation.
