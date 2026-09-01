#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
release_dir="${SNAPASSIST_RELEASE_DIR:-$project_root/outputs/release}"
app_dir="$release_dir/app"
app_path="$app_dir/SnapAssist.app"
dmg_path="$release_dir/SnapAssist.dmg"
notary_zip="$release_dir/SnapAssist-notary.zip"
notary_profile="${SNAPASSIST_NOTARY_PROFILE:-}"

if [[ -z "$notary_profile" ]]; then
  echo "SNAPASSIST_NOTARY_PROFILE is required for a public release." >&2
  echo "Create one with: xcrun notarytool store-credentials <profile>" >&2
  exit 1
fi

staging_dir=""
cleanup() {
  rm -f "$notary_zip"
  [[ -z "$staging_dir" ]] || rm -rf "$staging_dir"
}
trap cleanup EXIT

submit_for_notarization() {
  local artifact="$1"
  local result_path="$2"
  local submission_id=""
  local status=""

  if ! xcrun notarytool submit "$artifact" \
      --keychain-profile "$notary_profile" \
      --wait \
      --output-format json >"$result_path"; then
    if [[ -s "$result_path" ]]; then
      submission_id="$(/usr/bin/plutil -extract id raw -o - "$result_path" 2>/dev/null || true)"
      [[ -n "$submission_id" ]] && xcrun notarytool log "$submission_id" --keychain-profile "$notary_profile" || true
    fi
    return 1
  fi

  status="$(/usr/bin/plutil -extract status raw -o - "$result_path")"
  submission_id="$(/usr/bin/plutil -extract id raw -o - "$result_path")"
  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization failed for $artifact with status: $status" >&2
    xcrun notarytool log "$submission_id" --keychain-profile "$notary_profile" || true
    return 1
  fi
}

mkdir -p "$release_dir"
SNAPASSIST_DISTRIBUTION=direct \
SNAPASSIST_OUTPUT_DIR="$app_dir" \
  "$script_dir/build-app.sh"

rm -f "$notary_zip"
ditto -c -k --keepParent "$app_path" "$notary_zip"
submit_for_notarization "$notary_zip" "$release_dir/SnapAssist-app-notary-result.json"
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"
rm -f "$notary_zip"

staging_dir="$(mktemp -d)"

ditto "$app_path" "$staging_dir/SnapAssist.app"
ln -s /Applications "$staging_dir/Applications"
rm -f "$dmg_path"
hdiutil create \
  -volname "SnapAssist" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -ov \
  "$dmg_path"

submit_for_notarization "$dmg_path" "$release_dir/SnapAssist-dmg-notary-result.json"
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"

echo "$dmg_path"
