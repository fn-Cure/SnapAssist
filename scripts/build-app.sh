#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
output_dir="${SNAPASSIST_OUTPUT_DIR:-$project_root/outputs/SnapAssist}"
app_path="$output_dir/SnapAssist.app"
distribution="${SNAPASSIST_DISTRIBUTION:-development}"
architectures="${SNAPASSIST_ARCHS:-arm64 x86_64}"
arch_args=()
for architecture in ${(z)architectures}; do
  arch_args+=(--arch "$architecture")
done

swift build \
  --package-path "$project_root" \
  --configuration release \
  "${arch_args[@]}"

binary_dir="$(swift build \
  --package-path "$project_root" \
  --configuration release \
  "${arch_args[@]}" \
  --show-bin-path)"

if [[ -e "$app_path" ]]; then
  rm -rf "$app_path"
fi

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/SnapAssist" "$app_path/Contents/MacOS/SnapAssist"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
cp "$project_root/Resources/PrivacyInfo.xcprivacy" "$app_path/Contents/Resources/PrivacyInfo.xcprivacy"
for localization in "$project_root"/Resources/*.lproj; do
  [[ -d "$localization" ]] || continue
  ditto "$localization" "$app_path/Contents/Resources/$(basename "$localization")"
done
chmod 755 "$app_path/Contents/MacOS/SnapAssist"

plutil -lint "$app_path/Contents/Info.plist"

signing_identity="${SNAPASSIST_CODE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  case "$distribution" in
    development)
      signing_identity="$(security find-identity -v -p codesigning \
        | awk -F '"' '/Apple Development/ { print $2; exit }')"
      ;;
    direct)
      signing_identity="$(security find-identity -v -p codesigning \
        | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
      ;;
    *)
      echo "Unknown SNAPASSIST_DISTRIBUTION '$distribution'. Use development or direct." >&2
      exit 1
      ;;
  esac
fi
if [[ -z "$signing_identity" ]]; then
  if [[ "$distribution" == "development" && "${SNAPASSIST_ALLOW_ADHOC:-0}" == "1" ]]; then
    signing_identity="-"
  else
    echo "No valid signing identity found for '$distribution' distribution." >&2
    echo "Set SNAPASSIST_CODE_SIGN_IDENTITY. Direct releases require Developer ID Application." >&2
    exit 1
  fi
fi

signing_args=(
  --force
  --options runtime
  --entitlements "$project_root/Resources/SnapAssist.entitlements"
  --sign "$signing_identity"
  --identifier com.caner.snapassist
)
if [[ "$distribution" == "direct" ]]; then
  signing_args+=(--timestamp)
fi

codesign \
  "${signing_args[@]}" \
  "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

designated_requirement="$(codesign -d -r- "$app_path" 2>&1 | sed -n 's/^designated => //p')"
cdhash="$(codesign -dvvv "$app_path" 2>&1 | sed -n 's/^CDHash=//p' | head -n 1)"

echo "Signed with: $signing_identity"
echo "Distribution: $distribution"
echo "Architectures: $(lipo -archs "$app_path/Contents/MacOS/SnapAssist")"
echo "Designated requirement: $designated_requirement"
echo "CDHash: $cdhash"
echo "$app_path"
