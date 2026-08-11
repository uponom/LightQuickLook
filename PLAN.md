# QuickSourceLook implementation plan

- [x] Milestone 0 — inspect environment, research UTIs, document registration design
- [ ] Milestone 1 — host/extension skeleton implemented and type-checked; full Xcode build and Finder invocation pending Xcode installation
- [x] Milestone 2 — implement cancellable loader, decoder, size policy, binary guard, native viewer
- [x] Milestone 3 — implement token core and JSON highlighting with tests
- [x] Milestone 4 — implement YAML highlighting with tests
- [x] Milestone 5 — implement PowerShell highlighting with tests
- [x] Milestone 6 — implement Bash highlighting with tests
- [x] Milestone 7 — implement Terraform/HCL highlighting with tests
- [x] Milestone 8 — implement source-oriented Markdown highlighting with tests
- [ ] Milestone 9 — UTI declarations and diagnostics implemented; installed-bundle `pluginkit` validation pending Xcode
- [ ] Milestone 10 — source/type-check/audit/benchmark complete; Xcode XCTest, signed Release bundle audit, and size measurement pending Xcode
- [ ] Milestone 11 — documentation complete; final clean Xcode Release build pending Xcode

The unchecked items share one external blocker: this machine currently has Command Line Tools only, not the full Xcode application required to build an `.app` containing an `.appex`.
