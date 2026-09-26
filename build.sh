#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
bundle="Clipvault.app"
iconset="AppIcon.iconset"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
dist="dist"
executable="$bundle/Contents/MacOS/Clipvault"
arm_executable="${executable}.arm64"
intel_executable="${executable}.x86_64"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$bundle/Contents/Resources/AppIcon.icns"
swiftc -parse-as-library -target arm64-apple-macos14.0 ClipboardVault.swift -o "$arm_executable"
swiftc -parse-as-library -target x86_64-apple-macos14.0 ClipboardVault.swift -o "$intel_executable"
lipo -create "$arm_executable" "$intel_executable" -output "$executable"
rm -f "$arm_executable" "$intel_executable"
cp Info.plist "$bundle/Contents/Info.plist"
codesign --force --deep --sign - "$bundle"
mkdir -p "$dist"
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$dist/Clipvault-${version}.zip"
