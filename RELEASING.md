# Releases

Versions are `X.Y`. Changes that users will notice go under `## Unreleased` in `docs/changelog.md` as
they land.

```sh
NOTARYTOOL_PROFILE=<profile> scripts/release.sh        # the latest v* tag with its minor number plus one
NOTARYTOOL_PROFILE=<profile> scripts/release.sh 0.1    # or name the version
```

Run it from a clean `main` that matches `origin/main`. It runs the tests, renames `## Unreleased` to
`## X.Y`, sets `version:` in `docs/_config.yml`, commits and pushes `Release X.Y`, then builds, signs,
notarizes and publishes, and updates the Homebrew tap. Running it again without adding commits reuses the
`Release X.Y` commit and retries a failed release. If the fix needs a commit, first `git revert` the
unpublished `Release X.Y` commit, commit the fix, push, and run it again. A published version is never
replaced.

A pull request can carry the bump instead. In it, rename `## Unreleased` to `## X.Y` in `docs/changelog.md`
and set `version:` in `docs/_config.yml`. Merge it any way GitHub offers, pull `main`, and run
`scripts/release.sh`. It sees that the changelog's newest section and the site's version name the same `X.Y`,
and that no local tag `vX.Y` exists yet. It skips its own bump, then tests, builds and publishes that version.
To retry a failed run, run it again before adding commits to `main`. Release the bump before another
changelog entry lands. The script refuses a `## Unreleased` section above a `## X.Y` that has no release.

`scripts/package-release.sh X.Y` does the build half and publishes nothing. It writes `dist/Splay.app.zip`,
`dist/appcast.xml` and `dist/splay.rb`:

- a universal build for Apple silicon and Intel, checked by `scripts/check-universal.sh`
- signed with the Developer ID Application identity in the keychain, with the hardened runtime
  (`DEVELOPER_ID_APPLICATION` picks another)
- notarized and stapled through the `notarytool` keychain profile named by `NOTARYTOOL_PROFILE`
- zipped, and the zip signed for Sparkle
- the Homebrew cask, `dist/splay.rb`, from `scripts/splay.rb.template` with the version and the zip's
  SHA-256, written only once the zip has passed the universal check

The build number is the commit count plus 100, so a release is always newer than a local build of the same
commit. Packaging builds in `dist/build`, so a copy of Splay running from `build/` keeps running. Only a
packaged release carries the update feed. `scripts/bundle.sh` leaves it out, so a local build never offers
to replace itself with a release.

## One-time setup

A notarization profile, stored in the keychain:

```sh
xcrun notarytool store-credentials splay-notary --apple-id <Apple ID> --team-id <team ID>
```

It asks for an app-specific password from account.apple.com.

The Homebrew tap, the public repository
[shawntz/homebrew-tap](https://github.com/shawntz/homebrew-tap), must exist before a release, and
`git@github.com:shawntz/homebrew-tap.git` must accept your SSH key for pushes.

## Homebrew

People install with `brew install --cask shawntz/tap/splay`. Each release uploads `dist/splay.rb` with
the zip and the appcast. Once the release is published, `scripts/release.sh` clones the tap into a
temporary folder, copies the cask to `Casks/splay.rb`, and commits and pushes `Update splay to X.Y`.

If that fails, the release stays published, and the script warns, deploys the site and exits without an
error. To retry, run `scripts/release.sh X.Y` again before adding commits to `main`. For a published
release it downloads the release's `splay.rb`, then updates the tap and the site. After other commits,
copy that `splay.rb` to `Casks/splay.rb` in the tap by hand. Release 0.1 was published without one.

## Updates

Splay updates itself with [Sparkle](https://sparkle-project.org). The feed, `SUFeedURL` in
`Resources/Info.plist`, is the `appcast.xml` asset of the latest GitHub release, so publishing a release
is what ships the update.

Updates are signed with an EdDSA key. Its private half lives in the login keychain under the account
`com.shawnschwartz.splay`, and its public half is `SUPublicEDKey` in `Resources/Info.plist`. Without the
private key you cannot sign updates, so keep a backup somewhere safe. Export it outside the repository:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/splay-sparkle-key --account com.shawnschwartz.splay
```

Move that file into a password manager or an encrypted backup, then delete it. Import it on another Mac
with `generate_keys -f ~/splay-sparkle-key --account com.shawnschwartz.splay`.
