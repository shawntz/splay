#!/usr/bin/env bash
# Builds a universal Splay.app, signs it with Developer ID and the hardened runtime, notarizes and staples it,
# zips it into dist/, and writes the Sparkle appcast. Publishes nothing.
# Usage: NOTARYTOOL_PROFILE=<profile> scripts/package-release.sh 0.1
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Usage: scripts/package-release.sh X.Y}"
version="${version#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+$ ]] || { echo 'Expected version X.Y' >&2; exit 1; }
profile="${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to a notarytool keychain profile (make one with: xcrun notarytool store-credentials)}"
# By hash, as scripts/bundle.sh picks its identity: two certificates can share a name.
identity="${DEVELOPER_ID_APPLICATION:-$(security find-identity -v -p codesigning | awk '/"Developer ID Application: /{print $2; exit}')}"
[[ -n "$identity" ]] || { echo 'No Developer ID Application identity; set DEVELOPER_ID_APPLICATION' >&2; exit 1; }
build="$(( $(git rev-list --count HEAD) + 100 ))"
# Not build/Splay.app: a copy running from there keeps running while a release is packaged.
app=dist/build/Splay.app
account=com.shawnschwartz.splay

echo "==> Building and signing Splay.app $version ($build) with Developer ID"
FEED=1 UNIVERSAL=1 VERSION="$version" BUILD="$build" IDENTITY="$identity" SIGN_FLAGS="--options runtime --timestamp" \
  OUT="$app" scripts/bundle.sh
scripts/check-universal.sh "$app"
codesign --verify --strict --verbose=1 "$app"
for key in SUFeedURL SUPublicEDKey; do
  [[ -n "$(/usr/libexec/PlistBuddy -c "Print :$key" "$app/Contents/Info.plist" 2>/dev/null)" ]] \
    || { echo "The packaged Info.plist has no $key; see RELEASING.md" >&2; exit 1; }
done

rm -f dist/Splay.app.zip dist/signature.txt dist/appcast.xml
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==> Notarizing with profile $profile"
ditto -c -k --sequesterRsrc --keepParent "$app" "$tmp/Splay.zip"
xcrun notarytool submit "$tmp/Splay.zip" --keychain-profile "$profile" --wait 2>&1 | tee "$tmp/notary.log"
grep -q 'status: Accepted' "$tmp/notary.log" \
  || { echo "Notarization was not accepted. Read why with: xcrun notarytool log <id above> --keychain-profile $profile" >&2; exit 1; }
xcrun stapler staple "$app"
spctl --assess --type execute --verbose=1 "$app"

ditto -c -k --sequesterRsrc --keepParent "$app" dist/Splay.app.zip

# Check the archive that ships, not only the app it was made from.
ditto -x -k dist/Splay.app.zip "$tmp/unpacked"
scripts/check-universal.sh "$tmp/unpacked/Splay.app"

echo "==> Signing the update and writing the appcast"
sign_update="$(find .build/artifacts -path '*/Sparkle/bin/sign_update' | head -1)"
[[ -x "$sign_update" ]] || { echo 'sign_update not found under .build/artifacts' >&2; exit 1; }
"$sign_update" --account "$account" -p dist/Splay.app.zip > dist/signature.txt
# -E: appcast.py checks its inputs with assert, which PYTHONOPTIMIZE in the environment would skip.
python3 -E scripts/appcast.py "$version"
echo "==> dist/Splay.app.zip ($(du -h dist/Splay.app.zip | cut -f1)), version $version build $build"
