#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
swift build -c release
task_bin_dir="$(swift build -c release --show-bin-path)"
task_app="$task_root/build/Shadowing Player.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
cp "$task_bin_dir/ShadowingPlayer" "$task_app/Contents/MacOS/ShadowingPlayer"
cp "$task_root/Info.plist" "$task_app/Contents/Info.plist"
# Local ad-hoc signing only; distribution would require a Developer ID and notarization.
codesign --force --sign - "$task_app"
print "Built: $task_app"
