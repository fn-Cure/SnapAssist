#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
build_output="$project_root/outputs/install"
source_app="$build_output/SnapAssist.app"
destination_app="/Applications/SnapAssist.app"

SNAPASSIST_OUTPUT_DIR="$build_output" "$script_dir/build-app.sh"
pkill -x SnapAssist 2>/dev/null || true

if [[ -e "$destination_app" ]]; then
  installed_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination_app/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$installed_identifier" != "com.caner.snapassist" ]]; then
    echo "Refusing to replace $destination_app because its bundle identifier is '$installed_identifier'." >&2
    exit 1
  fi
  rm -rf "$destination_app"
fi

ditto "$source_app" "$destination_app"
codesign --verify --deep --strict --verbose=2 "$destination_app"
open "$destination_app"

echo "$destination_app"
