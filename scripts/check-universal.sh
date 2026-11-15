#!/usr/bin/env bash
# Fail before signing if the app or any bundled Sparkle executable loses a slice.
set -euo pipefail
app="${1:?Usage: scripts/check-universal.sh path/to/Splay.app}"
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/Current"
for binary in \
  "$app/Contents/MacOS/splay" \
  "$sparkle/Sparkle" \
  "$sparkle/Autoupdate" \
  "$sparkle/Updater.app/Contents/MacOS/Updater" \
  "$sparkle/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
  "$sparkle/XPCServices/Installer.xpc/Contents/MacOS/Installer"; do
  # Verify separately: some Apple lipo versions reject a multi-architecture verification.
  for arch in arm64 x86_64; do
    lipo "$binary" -verify_arch "$arch" || { echo "check-universal: $binary has no $arch slice" >&2; exit 1; }
  done
done
