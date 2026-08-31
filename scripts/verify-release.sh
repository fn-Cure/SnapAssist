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

case "$artifact" in
  *.app)
    codesign --verify --deep --strict --verbose=2 "$artifact"
    codesign -dvvv "$artifact" 2>&1 | grep 'flags=.*runtime' >/dev/null
    codesign -d --entitlements :- "$artifact"
    architectures="$(lipo -archs "$artifact/Contents/MacOS/SnapAssist")"
    [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
    spctl --assess --type execute --verbose=4 "$artifact"
    xcrun stapler validate "$artifact"
    ;;
  *.dmg)
    hdiutil verify "$artifact"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$artifact"
    xcrun stapler validate "$artifact"
    ;;
  *)
    echo "Expected a .app or .dmg artifact." >&2
    exit 65
    ;;
esac
