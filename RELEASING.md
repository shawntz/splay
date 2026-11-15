# Releases

Versions are `X.Y`. Changes that users will notice go under `## Unreleased` in `docs/changelog.md` as
they land.

```sh
NOTARYTOOL_PROFILE=<profile> scripts/release.sh        # the latest tag plus 0.1
NOTARYTOOL_PROFILE=<profile> scripts/release.sh 0.1    # or name the version
```

Run it from a clean `main` that matches `origin/main`. It runs the tests, renames `## Unreleased` to
`## X.Y`, sets `version:` in `docs/_config.yml`, commits and pushes `Release X.Y`, then builds, signs,
notarizes and publishes. Running it again retries a failed release. A published version is never replaced.

`scripts/package-release.sh X.Y` does the build half and publishes nothing. It writes `dist/Splay.app.zip`
and `dist/appcast.xml`:

- a universal build for Apple silicon and Intel, checked by `scripts/check-universal.sh`
- signed with the Developer ID Application identity in the keychain, with the hardened runtime
  (`DEVELOPER_ID_APPLICATION` picks another)
- notarized and stapled through the `notarytool` keychain profile named by `NOTARYTOOL_PROFILE`
- zipped, and the zip signed for Sparkle

The build number is the commit count plus 100, so a release is always newer than a local build of the same
commit. Packaging builds in `dist/build`, so a copy of Splay running from `build/` keeps running.

## One-time setup

A notarization profile, stored in the keychain:

```sh
xcrun notarytool store-credentials splay-notary --apple-id <Apple ID> --team-id <team ID>
```

It asks for an app-specific password from account.apple.com.

## Updates

Splay updates itself with [Sparkle](https://sparkle-project.org). The feed, `SUFeedURL` in
`Resources/Info.plist`, is the `appcast.xml` asset of the latest GitHub release, so publishing a release
is what ships the update.

Updates are signed with an EdDSA key. Its private half lives in the login keychain under the account
`com.shawnschwartz.splay`, and its public half is `SUPublicEDKey` in `Resources/Info.plist`. Without the
private key, installed copies can no longer update, so keep a backup somewhere safe:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x splay-sparkle-key --account com.shawnschwartz.splay
```

Import it on another Mac with `generate_keys -f splay-sparkle-key --account com.shawnschwartz.splay`.
