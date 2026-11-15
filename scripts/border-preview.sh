#!/bin/sh
# Standalone native comparison. Does not start or replace Splay.
set -eu
cd "$(dirname "$0")/.."
app="$PWD/build/Splay Border Preview.app"
mkdir -p "$app/Contents/MacOS" "$PWD/build/border-preview-cache"
clang -fobjc-arc -fmodules-cache-path="$PWD/build/border-preview-cache" \
	-framework AppKit -framework CoreGraphics \
	-F/System/Library/PrivateFrameworks -framework SkyLight \
	scripts/border-preview.m -o "$app/Contents/MacOS/border-preview"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>border-preview</string>
	<key>CFBundleIdentifier</key><string>local.splay.border-preview</string>
	<key>CFBundleName</key><string>Splay Border Preview</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
open "$app"
