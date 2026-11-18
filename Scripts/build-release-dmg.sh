#!/bin/zsh
set -euo pipefail

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
project_path="$repository_root/LightQuickLook.xcodeproj"
host_info_plist="$repository_root/LightQuickLook/Info.plist"
preview_info_plist="$repository_root/LightQuickLookPreview/Info.plist"
version="$(plutil -extract CFBundleShortVersionString raw "$host_info_plist")"
preview_version="$(plutil -extract CFBundleShortVersionString raw "$preview_info_plist")"
artifact_base="LightQuickLook-${version}-unnotarized"
output_directory="$repository_root/dist"
dmg_path="$output_directory/${artifact_base}.dmg"
checksum_path="$output_directory/${artifact_base}-SHA256.txt"
release_build_directory="$repository_root/build/Release"
derived_data_directory="$(mktemp -d /private/tmp/LightQuickLook-release-derived.XXXXXX)"
dmg_staging_directory="$(mktemp -d /private/tmp/LightQuickLook-release-dmg.XXXXXX)"
lsregister_path="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

unregister_build_application() {
  local application_path="$1"
  local extension_path="$application_path/Contents/PlugIns/LightQuickLookPreview.appex"

  if [[ -d "$extension_path" ]]; then
    /usr/bin/pluginkit -r "$extension_path" >/dev/null 2>&1 || true
  fi
  if [[ -d "$application_path" ]]; then
    "$lsregister_path" -u "$application_path" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  local exit_status=$?
  set +e
  unregister_build_application "$derived_data_directory/Build/Products/Debug/LightQuickLook.app"
  unregister_build_application "$derived_data_directory/Build/Products/Release/LightQuickLook.app"
  unregister_build_application "$release_build_directory/LightQuickLook.app"
  rm -rf "$derived_data_directory" "$dmg_staging_directory"
  return "$exit_status"
}
trap cleanup EXIT

verify_entitlements() {
  local code_path="$1"
  local label="$2"
  local entitlements_path="$derived_data_directory/${label}-entitlements.plist"
  local remaining_entitlements_path="$derived_data_directory/${label}-remaining-entitlements.plist"
  local sandbox_value
  local remaining_entitlements

  codesign -d --entitlements :- "$code_path" > "$entitlements_path" 2>/dev/null
  plutil -lint "$entitlements_path" >/dev/null

  if ! sandbox_value="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements_path" 2>/dev/null)"; then
    print -u2 "$label is missing the required App Sandbox entitlement"
    exit 65
  fi
  if [[ "$sandbox_value" != "true" ]]; then
    print -u2 "$label is missing the required App Sandbox entitlement"
    exit 65
  fi

  cp "$entitlements_path" "$remaining_entitlements_path"
  /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.app-sandbox' "$remaining_entitlements_path"
  remaining_entitlements="$(plutil -convert json -o - "$remaining_entitlements_path")"
  if [[ "$remaining_entitlements" != "{}" ]]; then
    print -u2 "$label contains unexpected entitlements: $remaining_entitlements"
    exit 65
  fi
}

verify_hardened_runtime() {
  local code_path="$1"
  local label="$2"
  local signature_details

  signature_details="$(codesign -dv --verbose=4 "$code_path" 2>&1)"
  if ! print -r -- "$signature_details" | grep -Eq '^CodeDirectory .*flags=.*runtime'; then
    print -u2 "$label is not signed with Hardened Runtime enabled"
    exit 65
  fi
}

if [[ "$version" != "$preview_version" ]]; then
  print -u2 "version mismatch: host=$version preview=$preview_version"
  exit 65
fi

mkdir -p "$output_directory"

xcodebuild test \
  -project "$project_path" \
  -scheme LightQuickLook \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data_directory" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  CODE_SIGNING_ALLOWED=NO

xcodebuild analyze \
  -project "$project_path" \
  -scheme LightQuickLook \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data_directory" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project "$project_path" \
  -scheme LightQuickLook \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data_directory" \
  CONFIGURATION_BUILD_DIR="$release_build_directory" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  CODE_SIGN_IDENTITY=-

app_path="$release_build_directory/LightQuickLook.app"
preview_path="$app_path/Contents/PlugIns/LightQuickLookPreview.appex"

codesign --verify --strict --verbose=2 "$preview_path"
codesign --verify --strict --verbose=2 "$app_path"
verify_entitlements "$app_path" "host-app"
verify_entitlements "$preview_path" "preview-extension"
verify_hardened_runtime "$app_path" "host app"
verify_hardened_runtime "$preview_path" "preview extension"

host_architectures="$(lipo -archs "$app_path/Contents/MacOS/LightQuickLook")"
preview_architectures="$(lipo -archs "$preview_path/Contents/MacOS/LightQuickLookPreview")"
if [[ "$host_architectures" != "arm64" || "$preview_architectures" != "arm64" ]]; then
  print -u2 "unexpected architectures: host=$host_architectures preview=$preview_architectures"
  exit 65
fi

built_version="$(plutil -extract CFBundleShortVersionString raw "$app_path/Contents/Info.plist")"
built_preview_version="$(plutil -extract CFBundleShortVersionString raw "$preview_path/Contents/Info.plist")"
if [[ "$built_version" != "$version" || "$built_preview_version" != "$version" ]]; then
  print -u2 "built version mismatch: expected=$version host=$built_version preview=$built_preview_version"
  exit 65
fi

ditto "$app_path" "$dmg_staging_directory/LightQuickLook.app"
ln -s /Applications "$dmg_staging_directory/Applications"

hdiutil create \
  -volname LightQuickLook \
  -srcfolder "$dmg_staging_directory" \
  -format UDZO \
  -ov \
  "$dmg_path"
hdiutil verify "$dmg_path"

checksum="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
print "$checksum  ${dmg_path:t}" > "$checksum_path"

print "Created release artifacts:"
print "  $dmg_path"
print "  $checksum_path"
print "Architecture: arm64"
print "Version: $version"
print "Signing: ad hoc (not Developer ID, not notarized)"
print "Entitlements: App Sandbox only"
print "Hardened Runtime: enabled"
