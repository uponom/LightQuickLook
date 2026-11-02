# UTI research (macOS 26)

## Environment and method

Research was run on Apple Silicon, macOS 26.6.1 (25G76), using non-empty files in `Samples/` and:

```sh
mdls -name kMDItemContentType -name kMDItemContentTypeTree <absolute-file-path>
```

Results reflect this machine's current Launch Services database and installed applications. Dynamic `dyn.*` values are machine-derived and must never be shipped in `QLSupportedContentTypes`.

## Observed results

| Extension | Observed content type | Classification |
|---|---|---|
| `.yaml`, `.yml` | `public.yaml` | stable Apple-declared type |
| `.json` | `public.json` | stable Apple-declared type |
| `.jsonl` | `dyn.ah62d4rv4ge80y65tr30a` | dynamic and unsuitable for registration |
| `.md`, `.markdown` | `net.daringfireball.markdown` | established imported type; conforms to `public.plain-text` here |
| `.sh` | `public.shell-script` | stable Apple type, but broad within the script hierarchy |
| `.bash` | `public.bash-script` | stable Apple type, conforms to `public.shell-script` |
| `.ps1` | `dyn.ah62d4rv4ge81a63v` | dynamic and unsuitable for registration |
| `.psm1` | `dyn.ah62d4rv4ge81a65rge` | dynamic and unsuitable for registration |
| `.psd1` | `dyn.ah62d4rv4ge81a65ege` | dynamic and unsuitable for registration |
| `.tf` | `dyn.ah62d4rv4ge81k3u` | dynamic and unsuitable for registration |
| `.tfvars` | `dyn.ah62d4rv4ge81k3x0qf3hg` | dynamic and unsuitable for registration |
| `.hcl` | `dyn.ah62d4rv4ge80u25q` | dynamic and unsuitable for registration |

`UTType.markdown` is intentionally not referenced: it is a macOS 27 API, while this project targets macOS 26.

## Registration decision

The host does not import or claim Markdown. `.md` and `.markdown` are intentionally left to dedicated extensions such as Markdown Preview.

The host exports the application-owned narrow types:

- `io.github.uponom.lightquicklook.powershell-source` → `.ps1`, `.psm1`, `.psd1`, conforms to `public.source-code`;
- `io.github.uponom.lightquicklook.hcl-source` → `.tf`, `.tfvars`, `.hcl`, conforms to `public.source-code`;
- `io.github.uponom.lightquicklook.json-lines` → `.jsonl`, conforms to `public.json` and reuses the JSON lexer.

The preview extension registers exactly:

```text
public.yaml
public.json
public.shell-script
public.bash-script
io.github.uponom.lightquicklook.powershell-source
io.github.uponom.lightquicklook.hcl-source
io.github.uponom.lightquicklook.json-lines
```

It does not register `public.data`, `public.item`, `public.content`, `public.text`, `public.plain-text`, or `public.source-code`.

## The `.sh` compromise

On this system `.sh` resolves to `public.shell-script`; a custom imported extension-only type does not appear in that type's conformance tree and therefore cannot reliably receive Finder dispatch. Registering `public.shell-script` is necessary to support `.sh`.

This is broader than Bash. Empirical checks show these types also conform to `public.shell-script`:

- `.rb` → `public.ruby-script`;
- `.pl` → `public.perl-script`;
- `.php` → `public.php-script`;
- `.zsh` → `public.zsh-script`.

Consequently LightQuickLook may be offered as a handler for those scripts. The extension does not claim their syntax: extension-first language detection falls back to safe plain monospaced text. This compromise must be rechecked after installation because Quick Look handler precedence can also depend on other installed applications.

## Post-build verification

The final Release bundle was registered from `build/Release`. PlugInKit reported `io.github.uponom.LightQuickLook.Preview` at the expected embedded path and the extension was enabled. Fresh files resolved as follows:

- `.yaml` → `public.yaml`;
- `.json` → `public.json`;
- `.jsonl` → `io.github.uponom.lightquicklook.json-lines`;
- `.sh` → `public.shell-script`;
- `.ps1` → `io.github.uponom.lightquicklook.powershell-source`;
- `.tf` → `io.github.uponom.lightquicklook.hcl-source`.

Real view-based Quick Look windows were opened for YAML and JSON and displayed the expected source and highlighting. Existing files can retain cached `dyn.*` Spotlight metadata until reindexed; fresh-file checks avoid mistaking that cache for current Launch Services registration.
