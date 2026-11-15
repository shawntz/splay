#!/usr/bin/env bash
# Builds build/Splay.app and signs it with a stable identity, so the Accessibility grant survives rebuilds.
# Usage: scripts/bundle.sh [--debug]. UNIVERSAL=1 builds arm64 and x86_64; the default is this Mac's architecture.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${IDENTITY:-}"
SIGN_FLAGS="${SIGN_FLAGS:-}"  # extra codesign flags, such as --options runtime
CONFIG=release
[[ "${1:-}" == "--debug" ]] && CONFIG=debug

# macOS ties the Accessibility grant to the signing certificate, so prefer a real one over ad hoc. Pick it by
# hash: two certificates can share a name.
if [[ "$IDENTITY" == - ]]; then
  SIGNED_WITH="ad hoc"
elif [[ -n "$IDENTITY" ]]; then
  SIGNED_WITH=custom
elif IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development: /{print $2; exit}')" \
  && [[ -n "$IDENTITY" ]]; then
  SIGNED_WITH="Apple Development"
else
  IDENTITY=- SIGNED_WITH="ad hoc"
  echo "No Apple Development identity, signing ad hoc: macOS drops the Accessibility grant on every rebuild. Set IDENTITY to a name or hash from 'security find-identity -v -p codesigning' to keep it." >&2
fi

BUILD_FLAGS=(-c "$CONFIG" --jobs 4)
if [[ "${UNIVERSAL:-}" == 1 ]]; then
  BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_FLAGS[@]}"

# Put together beside the app and moved into place once signed. A step that fails, or an interrupt, then leaves
# the app that was there working, and with it the Accessibility grant, login item and command line link that
# point at it. The app that was there waits in the staging folder while the new one moves in, and goes back if
# that move never happens.
OUT=build/Splay.app
STAGE=build/.staging
APP="$STAGE/Splay.app"
ICON_OUT="$(mktemp -d)"
trap '[[ -e "$OUT" || ! -e "$STAGE/previous.app" ]] || mv "$STAGE/previous.app" "$OUT"; rm -rf "$STAGE" "$ICON_OUT"' EXIT
rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS"
# The SwiftPM product keeps upstream's name; the CLI reads its arguments, not argv[0].
cp "$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/dinky" "$APP/Contents/MacOS/splay"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD" "$APP/Contents/Info.plist"

# The app icon: Resources/Splay.icon (Icon Composer) compiled into Assets.car and an icns fallback.
xcrun actool "$PWD/Resources/Splay.icon" --compile "$ICON_OUT" --platform macosx --minimum-deployment-target 15.0 \
  --app-icon Splay --include-all-app-icons --output-partial-info-plist "$ICON_OUT/partial.plist" >/dev/null
mkdir -p "$APP/Contents/Resources"
cp "$ICON_OUT/Assets.car" "$ICON_OUT/Splay.icns" "$APP/Contents/Resources/"
plutil -replace CFBundleIconFile -string Splay "$APP/Contents/Info.plist"
plutil -replace CFBundleIconName -string Splay "$APP/Contents/Info.plist"

# Sparkle.framework from the resolved SwiftPM artifact; the linker rpath finds it here.
# The binary still links it, but Info.plist has no feed, so it never checks for updates.
SPARKLE_SRC="$(find .build/artifacts -maxdepth 6 -path '*macos-arm64_x86_64/Sparkle.framework' | head -1)"
[[ -n "$SPARKLE_SRC" ]] || { echo 'Sparkle.framework not found in .build/artifacts' >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_SRC" "$APP/Contents/Frameworks/Sparkle.framework"

if [[ "${UNIVERSAL:-}" == 1 ]]; then
  scripts/check-universal.sh "$APP"
fi

# Sign inside out: Sparkle's helpers, the framework, then the app.
sign() { codesign --force $SIGN_FLAGS --sign "$IDENTITY" "$1"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for item in XPCServices/Downloader.xpc XPCServices/Installer.xpc Updater.app Autoupdate Sparkle; do
  sign "$SPARKLE/Versions/Current/$item"
done
sign "$SPARKLE"
sign "$APP"
[[ ! -e "$OUT" ]] || mv "$OUT" "$STAGE/previous.app"
mv "$APP" "$OUT"
echo "built $OUT ($CONFIG, $VERSION build $BUILD, signed $SIGNED_WITH)"
