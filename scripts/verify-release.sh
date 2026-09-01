#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/SnapAssist.app-or.dmg" >&2
  exit 64
fi

artifact="$1"
if [[ ! -e "$artifact" ]]; then
  echo "Artifact does not exist: $artifact" >&2
  exit 66
fi

verify_app() {
  local app="$1"
  local executable="$app/Contents/MacOS/SnapAssist"

  codesign --verify --deep --strict --verbose=2 "$app"
  codesign -dvvv "$app" 2>&1 | grep 'flags=.*runtime' >/dev/null
  codesign -d --entitlements :- "$app"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "com.caner.snapassist" ]]
  [[ -n "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" ]]
  architectures="$(lipo -archs "$executable")"
  [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
  spctl --assess --type execute --verbose=4 "$app"
  xcrun stapler validate "$app"
}

case "$artifact" in
  *.app)
    verify_app "$artifact"
    ;;
  *.dmg)
    hdiutil verify "$artifact"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$artifact"
    xcrun stapler validate "$artifact"
    mount_dir="$(mktemp -d)"
    cleanup_mount() {
      hdiutil detach "$mount_dir" -quiet || true
      rmdir "$mount_dir" 2>/dev/null || true
    }
    trap cleanup_mount EXIT
    hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" "$artifact" >/dev/null
    verify_app "$mount_dir/SnapAssist.app"
    cleanup_mount
    trap - EXIT
    ;;
  *)
    echo "Expected a .app or .dmg artifact." >&2
    exit 65
    ;;
esac
