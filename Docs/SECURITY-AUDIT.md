# Security audit — 2026-08-11

## Scope and threat model

The audit covers all production Swift sources, the Xcode project and schemes, Info.plist files, entitlements, UTI declarations, the SwiftPM test harness, and the final Universal Release `.app`/`.appex`. Previewed files are treated as fully untrusted. The primary risks are unwanted code or resource execution, sandbox escape-enabling capabilities, filesystem races, malformed-input crashes, excessive CPU or memory use, range/Unicode errors, and overly broad Quick Look registration.

## Checks performed

1. Traced the complete untrusted-file data flow from the Quick Look URL through file opening, bounded reads, decoding, language selection, lexing, attributed-string construction, and UI display.
2. Reviewed filesystem operations for non-file URLs, symbolic links, special files, path races, descriptor leaks, file growth/shrink races, and cancellation.
3. Reviewed all byte, string, UTF-16, `Int`, `UInt64`, and `NSRange` arithmetic for overflow, out-of-bounds access, split surrogate pairs, and forward-progress failures.
4. Exercised malformed Unicode and adversarial token runs in every lexer, including long unmatched Markdown links/comments/quotes/interpolations.
5. Reviewed algorithmic complexity and allocation behavior for file-size-driven CPU or memory denial of service.
6. Verified the 8 MiB hard read cap, binary-data rejection, BOM ordering, supported encodings, and neutral errors for malformed data.
7. Reviewed task isolation, cancellation, stale-preview replacement, completion-handler cardinality, main-actor UI access, and Swift 6 strict concurrency.
8. Verified that source is displayed only as native attributed text: no HTML, JavaScript, WebKit, interpolation evaluation, automatic link detection, external resource loading, or source execution.
9. Scanned production sources for networking, process execution, dynamic loading, AppleScript, unsafe Swift annotations, credential storage, and dangerous force operations.
10. Scanned the repository for embedded credentials/private keys and verified that SwiftPM and Xcode production targets have no third-party dependencies.
11. Reviewed App Sandbox entitlements and build settings for Hardened Runtime, extension-safe APIs, dead-code stripping, script sandboxing, and complete concurrency checking.
12. Reviewed every registered UTI for stable identifiers, ownership, conformance, extension scope, and broad parent-type side effects.
13. Ran Xcode static analysis and compiled/tests with compiler warnings treated as errors.
14. Ran XCTest normally and with UndefinedBehaviorSanitizer; ran the standalone adversarial self-test under AddressSanitizer and ThreadSanitizer.
15. Inspected the final Mach-O architectures, dynamic linkage, bundle plists, signatures, entitlements, CodeDirectory flags, and Gatekeeper result.
16. Registered and enabled the final extension, verified Launch Services content types, launched the host, and visually tested real YAML and JSON Quick Look windows.

## Findings and remediation

### S-01 — race-prone file validation and symlink following (medium, fixed)

The loader originally queried URL metadata and then opened the path in a separate operation. An attacker able to replace that path between the two operations could change the object being read, and final-component symbolic links were accepted.

The loader now opens once with `O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK`, validates the resulting descriptor with `fstat`, accepts only a regular file, derives the size from that same descriptor, reads at most 8 MiB, and closes the handle deterministically. Regression tests reject non-file URLs, directories, and symbolic links.

### S-02 — quadratic Markdown behavior on unmatched `[` runs (medium, fixed)

For a long line containing many unmatched opening brackets, the scanner repeatedly searched the rest of the line, producing quadratic work. A failed link candidate now advances directly to the line end. A 100,000-character regression input is exercised for every lexer.

### S-03 — overflow-prone range validation (medium, fixed)

Using `NSMaxRange` on an attacker-influenced invalid range can overflow before the bounds comparison. Core and UI validation now separately check nonnegative location/length and use `length <= total - location` only after proving `location <= total`. JSON spans use the same validator, and a regression test supplies `Int.max` and negative ranges.

### S-04 — non-positive chunk target and surrogate-boundary progress (low, fixed)

The public chunk helper did not defend against a zero or negative target and could fail to make safe progress around a surrogate pair. Targets are clamped to at least one UTF-16 unit; a pair is kept intact even when the requested chunk size is one. Zero and negative regression cases preserve the exact original text.

### S-05 — avoidable lexer allocation amplification (low, fixed)

Constant-prefix and heredoc comparisons allocated temporary UTF-16 arrays inside hot scanner loops. Prefix comparison now iterates the literal view, and heredoc comparison uses a bounded slice comparator. This reduces allocation-based pressure from adversarial files without changing syntax behavior.

### S-06 — release hardening and placeholder identity (low, fixed)

Production targets now enable Hardened Runtime and user-script sandboxing; Release also enables dead-code stripping/product stripping. Placeholder bundle and UTI identifiers were replaced with identifiers owned by this repository/account. Both host and extension retain only the App Sandbox entitlement.

### S-07 — custom UTIs declared as imported (functional/security boundary, fixed)

The application-owned PowerShell and HCL identifiers were initially listed under `UTImportedTypeDeclarations`, so Launch Services continued assigning machine-specific `dyn.*` types. They are now under `UTExportedTypeDeclarations`; only the externally owned Markdown identifier remains imported. Fresh `.ps1` and `.tf` files resolve to the expected narrow custom types after registration.

### Q-01 — YAML mapping key not highlighted (quality, fixed)

The shared identifier predicate includes `:` for PowerShell variables, which caused the YAML scanner to consume `name:` as one word. YAML now stops a plain key at the colon without weakening PowerShell handling. The previously failing YAML test passes.

No unresolved code security issue of low, medium, high, or critical severity was found after remediation.

## Verification results

- Xcode 26.6 first-launch status and macOS SDK/toolchain selection: pass.
- Xcode static analyzer, Release: pass.
- Swift 6 strict concurrency and warnings-as-errors build: pass.
- XCTest on macOS 26.6.1, arm64: **18 passed, 0 failed, 0 skipped**.
- XCTest with UndefinedBehaviorSanitizer: pass.
- AddressSanitizer standalone adversarial self-test: pass.
- ThreadSanitizer standalone adversarial self-test: pass.
- Xcode's ASan/TSan `xctest` runner itself aborted during sanitizer runtime bootstrap before loading tests; direct sanitized executables were used to test project code independently of that runner failure.
- Source capability scan: no production network, subprocess, WebKit/JavaScript, dynamic-loading, credential-storage, or unsafe-concurrency annotations found.
- Secret scan: no credential or private-key patterns found.
- Dependencies: zero third-party SwiftPM or Xcode production dependencies.
- Final signature verification: `codesign --verify --deep --strict` passed.
- Final CodeDirectory flags: `adhoc,runtime` for host and extension.
- Final entitlements: App Sandbox only for host and extension.
- Final linkage: Apple system frameworks and `/usr/lib` Swift/system libraries only.
- Final architecture: Universal `arm64 + x86_64` for host and extension.
- Launch Services/PlugInKit: extension registered, enabled, and allowed.
- Real Quick Look UI: YAML and JSON source displayed with expected highlighting.

## Distribution limitation

The machine has no valid Apple Development or Developer ID Application signing identity. The final local artifact is therefore ad-hoc signed with Hardened Runtime and is intentionally rejected by Gatekeeper for distribution. Public distribution still requires signing with a Developer ID certificate and Apple notarization; this is an operational release step, not an unresolved vulnerability in the source.

The `public.shell-script` registration needed for `.sh` is intentionally broader than Bash and can make the extension a candidate for other script subtypes. Unsupported extensions remain plain text and are never executed.
