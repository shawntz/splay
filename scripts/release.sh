#!/usr/bin/env bash
# Prepares, tests, packages, tags and publishes a GitHub release from a clean, pushed main, then puts its cask
# in the shawntz/homebrew-tap repository.
# Usage: NOTARYTOOL_PROFILE=<profile> scripts/release.sh [X.Y]   (run again to retry a failed release)
# Without a version it bumps the latest tag by 0.1. Preparing turns the `## Unreleased` section of
# docs/changelog.md into `## X.Y`, sets the site's version and commits and pushes "Release X.Y"; a rerun reuses
# that commit.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:-}"
version="${version#v}"
repo=shawntz/splay
changelog=docs/changelog.md
tap=git@github.com:shawntz/homebrew-tap.git

# Prints the body of a `## ` section of the changelog, without surrounding blank lines.
changelog_section() {
  awk -v heading="## $1" '
    $0 == heading { found = 1; next }
    found && /^## / { exit }
    found { print }
  ' "$changelog" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'
}

# Puts dist/splay.rb into the tap as Casks/splay.rb through a temporary clone, so a local tap checkout is left
# alone. Callers test its status, which turns off set -e inside it, so each step checks its own.
update_tap() (
  grep -qx "  version \"$version\"" dist/splay.rb || { echo "dist/splay.rb is not the cask for $version" >&2; exit 1; }
  checkout="$(mktemp -d "${TMPDIR:-/tmp}/splay-tap.XXXXXX")" || exit 1
  trap 'rm -rf "$checkout"' EXIT
  git clone --quiet --depth 1 "$tap" "$checkout" || exit 1
  mkdir -p "$checkout/Casks" && cp dist/splay.rb "$checkout/Casks/splay.rb" || exit 1
  git -C "$checkout" add Casks/splay.rb || exit 1
  if ! git -C "$checkout" diff --cached --quiet; then
    git -C "$checkout" commit -q -m "Update splay to $version" || exit 1
    git -C "$checkout" push -q origin HEAD || exit 1
  fi
  echo "==> Homebrew tap: splay $version"
)

# The release stays published when the tap update fails, so this warns and the script carries on.
tap_failed() {
  echo "warning: $tag is published, but the Homebrew tap was not updated to it." >&2
  echo "warning: to retry, run scripts/release.sh $version while HEAD is still the Release $version commit." >&2
  echo "warning: after other commits, copy the splay.rb asset of $tag to Casks/splay.rb in the tap by hand." >&2
}

# The site shows the version and the changelog. On a fork a push does not start the Pages workflow, so start it.
deploy_site() {
  gh workflow run pages.yml -R "$repo" --ref main >/dev/null \
    || echo "warning: the site was not redeployed; run: gh workflow run pages.yml -R $repo --ref main" >&2
}

: "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to a notarytool keychain profile (make one with: xcrun notarytool store-credentials)}"
[[ "$(git branch --show-current)" == main ]] || { echo 'Release from main' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit your changes first' >&2; exit 1; }
git fetch -q origin main
latest="$(gh release view -R "$repo" --json tagName --jq .tagName 2>/dev/null || true)"

prepared="$(git log -1 --format=%s | sed -n 's/^Release \([0-9][0-9]*\.[0-9][0-9]*\)$/\1/p')"
if [[ -n "$prepared" ]]; then
  [[ -z "$version" || "$version" == "$prepared" ]] || { echo "HEAD prepares $prepared, not $version" >&2; exit 1; }
  version="$prepared"
  if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
    [[ "$(git rev-parse HEAD^)" == "$(git rev-parse origin/main)" ]] || { echo 'Push or pull main first' >&2; exit 1; }
    git push -q origin HEAD:main
  fi
else
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo 'Push or pull main first' >&2; exit 1; }
  if [[ -z "$version" ]]; then
    last="$(git tag --list 'v*' --sort=-v:refname | head -1)"
    [[ -n "$last" ]] || { echo 'No v* tag to bump; pass a version' >&2; exit 1; }
    version="$(python3 -c 'import sys; m, n = sys.argv[1][1:].split(".")[:2]; print(f"{m}.{int(n) + 1}")' "$last")"
  fi
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+$ ]] || { echo 'Expected version X.Y' >&2; exit 1; }
tag="v$version"
if [[ -n "$latest" && "$latest" != "$tag" ]]; then
  python3 - "$tag" "$latest" <<'PY'
import sys
v = lambda s: tuple(int(x) for x in s.removeprefix('v').split('.'))
if v(sys.argv[1]) <= v(sys.argv[2]): raise SystemExit(f'{sys.argv[1]} is not newer than the latest release {sys.argv[2]}')
PY
fi

if [[ -z "$prepared" ]]; then
  [[ "$(grep -cx '## Unreleased' "$changelog" || true)" == 1 ]] || { echo "$changelog needs one ## Unreleased section" >&2; exit 1; }
  [[ -n "$(changelog_section Unreleased)" ]] || { echo "The ## Unreleased section of $changelog is empty" >&2; exit 1; }
  git rev-parse --verify -q "$tag" >/dev/null && { echo "Tag $tag already exists" >&2; exit 1; }
  echo "==> Testing before preparing $version"
  swift test --jobs 4
  sed -i '' "s/^## Unreleased\$/## $version/" "$changelog"
  sed -i '' "s/^version: \".*\"\$/version: \"$version\"/" docs/_config.yml
  git commit -q -m "Release $version" "$changelog" docs/_config.yml
  git push -q origin HEAD:main
  echo "==> Prepared and pushed Release $version"
fi

head="$(git rev-parse HEAD)"
grep -qx "version: \"$version\"" docs/_config.yml || { echo "docs/_config.yml does not name $version" >&2; exit 1; }
if git rev-parse --verify -q "$tag" >/dev/null; then
  [[ "$head" == "$(git rev-list -n 1 "$tag")" ]] || { echo "Tag $tag points to another commit" >&2; exit 1; }
fi
mkdir -p dist
changelog_section "$version" > dist/release-notes.md
[[ -s dist/release-notes.md ]] || { echo "$changelog has no notes under ## $version" >&2; exit 1; }

# A published release is never replaced. A rerun retries its tap update with the cask it shipped, and the site.
if [[ "$(gh release view "$tag" -R "$repo" --json isDraft --jq .isDraft 2>/dev/null || true)" == false ]]; then
  echo "$tag is already published: https://github.com/$repo/releases/tag/$tag"
  if [[ -z "$latest" ]]; then
    echo "warning: could not read the latest release, so the Homebrew tap is left alone" >&2
  elif ! { gh release download "$tag" -R "$repo" -p splay.rb -D dist --clobber && update_tap; }; then
    tap_failed
  fi
  deploy_site
  exit 0
fi

[[ -n "$prepared" ]] && swift test --jobs 4
scripts/package-release.sh "$version"
[[ "$head" == "$(git rev-parse HEAD)" && -z "$(git status --porcelain)" ]] || { echo 'Source changed during packaging; retry' >&2; exit 1; }

git rev-parse --verify -q "$tag" >/dev/null || git tag -a "$tag" -m "Release $version"
git push origin "$tag"
if gh release view "$tag" -R "$repo" >/dev/null 2>&1; then
  gh release edit "$tag" -R "$repo" --notes-file dist/release-notes.md
else
  gh release create "$tag" -R "$repo" --verify-tag --draft --title "Splay $version" --notes-file dist/release-notes.md
fi
gh release upload "$tag" -R "$repo" dist/Splay.app.zip dist/appcast.xml dist/splay.rb --clobber
gh release edit "$tag" -R "$repo" --draft=false --latest
tap_updated=true
update_tap || tap_updated=false
deploy_site
echo "==> https://github.com/$repo/releases/tag/$tag"
$tap_updated || tap_failed
