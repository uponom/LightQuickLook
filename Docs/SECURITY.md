# Security and privacy

QuickSourceLook treats every previewed file as untrusted bytes.

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

Reads are capped at 8 MiB, handles close immediately after loading, BOM checks precede binary heuristics, malformed/unsupported encodings produce a neutral message, and all token ranges are bounded before attribution. Cancellation is checked between expensive stages and chunks.

## Audit commands

After a full Xcode Release build:

```sh
codesign -d --entitlements :- <app>
codesign -dv --verbose=4 <app>
otool -L <app>/Contents/MacOS/QuickSourceLook
otool -L <app>/Contents/PlugIns/QuickSourcePreview.appex/Contents/MacOS/QuickSourcePreview
rg -n 'URLSession|NWConnection|Process\(|NSTask|system\(|popen\(|WKWebView|JavaScript' QuickSourceLook QuickSourcePreview QuickSourceCore
```

The source scan currently finds no production networking, process execution, WebKit, or JavaScript API use. Binary linkage/signing inspection remains pending because full Xcode is not installed in the present environment.
