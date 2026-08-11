# LightQuickLook implementation plan

- [x] Milestone 0 — inspect environment, research UTIs, document registration design
- [x] Milestone 1 — host/extension skeleton implemented, built, registered, and invoked through Quick Look
- [x] Milestone 2 — implement cancellable loader, decoder, size policy, binary guard, native viewer
- [x] Milestone 3 — implement token core and JSON highlighting with tests
- [x] Milestone 4 — implement YAML highlighting with tests
- [x] Milestone 5 — implement PowerShell highlighting with tests
- [x] Milestone 6 — implement Bash highlighting with tests
- [x] Milestone 7 — implement Terraform/HCL highlighting with tests
- [x] Milestone 8 — implement source-oriented Markdown highlighting with tests
- [x] Milestone 9 — UTI declarations verified with Launch Services, `mdls`, and PlugInKit
- [x] Milestone 10 — security audit, static analysis, XCTest, sanitizers, benchmark, signing/linkage audit, and size measurement complete
- [x] Milestone 11 — documentation and final Universal Xcode Release `.app`/`.appex` complete

All implementation milestones are complete. The local artifact is ad-hoc signed because this Mac has no Developer ID identity; public distribution signing and notarization remain separate release operations.
