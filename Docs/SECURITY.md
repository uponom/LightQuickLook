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

## Audit commands

After a full Xcode Release build:

```sh
codesign -d --entitlements :- <app>
codesign -dv --verbose=4 <app>
otool -L <app>/Contents/MacOS/LightQuickLook
otool -L <app>/Contents/PlugIns/LightQuickLookPreview.appex/Contents/MacOS/LightQuickLookPreview
rg -n 'URLSession|NWConnection|Process\(|NSTask|system\(|popen\(|WKWebView|JavaScript' LightQuickLook LightQuickLookPreview LightQuickLookCore
```

The source scan finds no production networking, process execution, WebKit, or JavaScript API use. The final binary/signing inspection passed for an ad-hoc Hardened Runtime build. See [the dated security audit](SECURITY-AUDIT.md) for the full checklist, findings, sanitizer results, and the Developer ID/notarization limitation.
