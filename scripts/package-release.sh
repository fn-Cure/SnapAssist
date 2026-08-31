#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
release_dir="${SNAPASSIST_RELEASE_DIR:-$project_root/outputs/release}"
app_dir="$release_dir/app"
app_path="$app_dir/SnapAssist.app"
dmg_path="$release_dir/SnapAssist.dmg"
notary_profile="${SNAPASSIST_NOTARY_PROFILE:-}"

mkdir -p "$release_dir"
SNAPASSIST_DISTRIBUTION=direct \
SNAPASSIST_OUTPUT_DIR="$app_dir" \
  "$script_dir/build-app.sh"

staging_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT

ditto "$app_path" "$staging_dir/SnapAssist.app"
ln -s /Applications "$staging_dir/Applications"
rm -f "$dmg_path"
hdiutil create \
  -volname "SnapAssist" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -ov \
  "$dmg_path"

if [[ -z "$notary_profile" ]]; then
  echo "SNAPASSIST_NOTARY_PROFILE is required for a public release." >&2
  echo "Create one with: xcrun notarytool store-credentials <profile>" >&2
  exit 1
fi

xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"

echo "$dmg_path"
