# Theming

LightQuickLook maps its compact lexer token model onto Microsoft Visual Studio Code's built-in **Dark 2026** and **Light 2026** palettes. The authoritative upstream files are:

- [`2026-dark.json`](https://github.com/microsoft/vscode/blob/main/extensions/theme-defaults/themes/2026-dark.json)
- [`2026-light.json`](https://github.com/microsoft/vscode/blob/main/extensions/theme-defaults/themes/2026-light.json)

The mapping uses the upstream editor backgrounds and foregrounds exactly. Comments, strings, constants, keywords, property names, variables, headings, links, and inline code use the closest corresponding upstream token color.

VS Code resolves a stack of TextMate scopes, including rules inherited by the 2026 themes from Dark Modern/Dark+ and Light Modern/Light+. LightQuickLook does not embed VS Code's grammar runtime, but its compact token model preserves scope distinctions that materially change the final color. For example, PowerShell `keyword.control`, `storage.type`, `support.function`, `variable.other`, and variables embedded in strings are represented separately. This makes `param([string]$Name)`, `Write-Output`, and `"Hello $Name"` follow the same inherited-rule precedence as VS Code 2026 instead of applying one generic color to every keyword or variable.

Operators and punctuation—including HCL `=`, `{`, and `}`—use the full editor foreground (`#BBBEBF` on `#121314` in Dark 2026; `#202020` on `#FFFFFF` in Light 2026). VS Code normally leaves operators at the editor foreground, and this avoids the low contrast caused by the previous macOS tertiary-label color.

Every LightQuickLook token/background pair is covered by an automated WCAG contrast test with a minimum threshold of 4.5:1. The preview follows the effective macOS appearance and recolors existing attributed text if the appearance changes while the window is open.
