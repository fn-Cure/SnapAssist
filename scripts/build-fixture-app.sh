#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
output_dir="${SNAPASSIST_FIXTURE_OUTPUT_DIR:-$project_root/outputs/fixture}"
app_path="$output_dir/SnapAssistFixture.app"

swift build --package-path "$project_root" --configuration release --product SnapAssistFixture --arch arm64
binary_dir="$(swift build --package-path "$project_root" --configuration release --product SnapAssistFixture --arch arm64 --show-bin-path)"

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_dir/SnapAssistFixture" "$app_path/Contents/MacOS/SnapAssistFixture"
cp "$project_root/Resources/FixtureInfo.plist" "$app_path/Contents/Info.plist"
chmod 755 "$app_path/Contents/MacOS/SnapAssistFixture"

identity="$(security find-identity -v -p codesigning | awk -F '"' '/Apple Development/ { print $2; exit }')"
codesign --force --options runtime --sign "${identity:--}" "$app_path"
codesign --verify --deep --strict "$app_path"
echo "$app_path"
