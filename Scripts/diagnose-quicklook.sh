#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "usage: $0 /path/to/LightQuickLook.app"
  exit 64
fi

app_path="$1"
if [[ ! -d "$app_path" ]]; then
  print -u2 "app bundle not found: $app_path"
  exit 66
fi

print "Extension registrations:"
pluginkit -mAvvv -p com.apple.quicklook.preview | grep -A4 -B2 'LightQuickLookPreview' || true

print "Sample UTIs:"
for file_path in "${0:A:h:h}"/Samples/*; do
  [[ -f "$file_path" ]] || continue
  print "${file_path:t}"
  mdls -name kMDItemContentType -name kMDItemContentTypeTree "$file_path"
done

print "Signing:"
codesign -dv --verbose=4 "$app_path"
codesign -d --entitlements :- "$app_path"
