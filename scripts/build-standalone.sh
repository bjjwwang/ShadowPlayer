#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
python3 scripts/fetch-standalone-tools.py
for task_arch in arm64 x86_64; do
    swift build -c release --arch "$task_arch" --scratch-path ".build/standalone-$task_arch"
done
task_arm_bin="$(swift build -c release --arch arm64 --scratch-path .build/standalone-arm64 --show-bin-path)"
task_intel_bin="$(swift build -c release --arch x86_64 --scratch-path .build/standalone-x86_64 --show-bin-path)"
task_app="$task_root/dist/Shadowing Player.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
lipo -create "$task_arm_bin/ShadowingPlayer" "$task_intel_bin/ShadowingPlayer" \
    -output "$task_app/Contents/MacOS/ShadowingPlayer"
cp Info.plist "$task_app/Contents/Info.plist"
ditto .build/standalone-tools/Tools "$task_app/Contents/Resources/Tools"
ditto .build/standalone-tools/Licenses "$task_app/Contents/Resources/Licenses"
cp .build/standalone-tools/tool-manifest.json "$task_app/Contents/Resources/tool-manifest.json"
cp Samples/practice.srt "$task_app/Contents/Resources/practice.srt"
cp PORTABLE-QUICKSTART.txt "$task_app/Contents/Resources/Quickstart.txt"
for task_tool in yt-dlp deno; do
    codesign --force --sign - "$task_app/Contents/Resources/Tools/$task_tool"
done
codesign --force --sign - "$task_app"
codesign --verify --deep --strict "$task_app"
for task_binary in "$task_app/Contents/MacOS/ShadowingPlayer" "$task_app/Contents/Resources/Tools/yt-dlp" "$task_app/Contents/Resources/Tools/deno"; do
    lipo "$task_binary" -verify_arch arm64 x86_64
done
task_package="$task_root/.build/standalone-package"
mkdir -p "$task_package"
ditto "$task_app" "$task_package/Shadowing Player.app"
cp PORTABLE-QUICKSTART.txt "$task_package/在另一台Mac上运行.txt"
cp Samples/practice.srt "$task_package/practice.srt"
ditto -c -k --sequesterRsrc "$task_package" dist/ShadowingPlayer-1.2-universal.zip
(
    cd dist
    shasum -a 256 ShadowingPlayer-1.2-universal.zip > ShadowingPlayer-1.2-universal.zip.sha256
)
print "Standalone app: $task_app"
print "Copyable archive: $task_root/dist/ShadowingPlayer-1.2-universal.zip"
