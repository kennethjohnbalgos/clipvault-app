#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
bundle="Clipvault.app"
iconset="AppIcon.iconset"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
dist="dist"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$bundle/Contents/Resources/AppIcon.icns"
swiftc -parse-as-library ClipboardVault.swift -o "$bundle/Contents/MacOS/Clipvault"
cp Info.plist "$bundle/Contents/Info.plist"
mkdir -p "$dist"
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$dist/Clipvault-${version}.zip"
