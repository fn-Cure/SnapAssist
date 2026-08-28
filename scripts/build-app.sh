#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
output_dir="${SNAPASSIST_OUTPUT_DIR:-$project_root/outputs/SnapAssist}"
app_path="$output_dir/SnapAssist.app"

swift build \
  --package-path "$project_root" \
  --configuration release \
  --arch arm64

binary_dir="$(swift build \
  --package-path "$project_root" \
  --configuration release \
  --arch arm64 \
  --show-bin-path)"

if [[ -e "$app_path" ]]; then
  rm -rf "$app_path"
fi

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/SnapAssist" "$app_path/Contents/MacOS/SnapAssist"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
chmod 755 "$app_path/Contents/MacOS/SnapAssist"

plutil -lint "$app_path/Contents/Info.plist"

signing_identity="${SNAPASSIST_CODE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  signing_identity="$(security find-identity -v -p codesigning \
    | awk -F '"' '/Apple Development/ { print $2; exit }')"
fi
if [[ -z "$signing_identity" ]]; then
  signing_identity="-"
fi

codesign \
  --force \
  --deep \
  --sign "$signing_identity" \
  --identifier com.caner.snapassist \
  "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

echo "Signed with: $signing_identity"
echo "$app_path"
