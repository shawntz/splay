"""Run the release scripts in a temp folder against mock tools.

Each test copies scripts/ and Resources/Info.plist into a new temp folder and puts mock swift, lipo, plutil,
xcrun, ditto, git, codesign, spctl, security and gh first on PATH, with a mock sign_update where SwiftPM puts
Sparkle's. Nothing is built, signed or notarized, the keychain and the network are not used, and the checkout's
build/, dist/ and .build/ are left alone. The mocks log every call, so a test can check what ran and in what order.
"""
import email.utils
import html
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
SPARKLE_BINARIES = [
    "Sparkle", "Autoupdate", "Updater.app/Contents/MacOS/Updater",
    "XPCServices/Downloader.xpc/Contents/MacOS/Downloader",
    "XPCServices/Installer.xpc/Contents/MacOS/Installer",
]
# check-universal.sh checks the app's executable and five Sparkle binaries, for two architectures each.
CHECKS_PER_APP = 12
SIGNATURE = "A" * 86 + "=="
APPLE_DEVELOPMENT = "1" * 40
DEVELOPER_ID = "2" * 40
IDENTITIES = (
    f'  1) {APPLE_DEVELOPMENT} "Apple Development: Test Person (TEAM000001)"\n'
    f'  2) {DEVELOPER_ID} "Developer ID Application: Test Person (TEAM000001)"\n'
    "     2 valid identities found\n"
)
CHANGELOG = """---
layout: default
title: Changelog
permalink: /changelog/
---

# Changelog

## Unreleased

- Not released yet.

## 0.24

- Changed in 0.24.
- Also changed in 0.24.

## 0.2

- Changed in 0.2.
"""
MOCKED = ["swift", "lipo", "plutil", "xcrun", "ditto", "git", "codesign", "spctl", "security", "gh"]
MOCK = r'''#!/usr/bin/env -S python3 -I -S
# Stands in for a build, signing or release tool, and logs each call to $MOCK_LOG.
import html, json, os, pathlib, plistlib, shutil, sys, zipfile
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
env = os.environ.get
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(json.dumps([name, *args]) + "\n")
# MOCK_FAIL="codesign Splay.app" fails a codesign call whose last argument ends in Splay.app.
tool, _, target = env("MOCK_FAIL", "").partition(" ")
if tool == name and args[-1].endswith(target):
    sys.exit(f"mock {name} failed")

if name == "swift":
    config = args[args.index("-c") + 1]
    archs = [args[i + 1] for i, arg in enumerate(args) if arg == "--arch"]
    # As with SwiftPM, a build for named architectures lands in a different folder from a build for this Mac.
    out = pathlib.Path(f".build/apple/Products/{config.title()}" if archs else f".build/arm64-apple-macosx/{config}")
    if "--show-bin-path" in args:
        print(out.resolve())
    else:
        out.mkdir(parents=True, exist_ok=True)
        (out / "dinky").write_text(" ".join(archs) or "arm64")
        if env("MOCK_BUILD_RESOLVES_SIGN_UPDATE"):
            signer = pathlib.Path(".build/artifacts/sparkle/Sparkle/bin/sign_update")
            signer.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(sys.argv[0], signer)
elif name == "lipo":
    # A mock binary is a text file that lists its architectures.
    if args[0] == "-archs":
        print(" ".join(pathlib.Path(args[1]).read_text().split()))
    elif len(args) == 3 and args[1] == "-verify_arch":
        binary = pathlib.Path(args[0])
        sys.exit(0 if binary.is_file() and args[2] in binary.read_text().split() else 1)
    else:
        sys.exit("unexpected lipo call")
elif name == "plutil":
    path = pathlib.Path(args[-1])
    info = plistlib.loads(path.read_bytes())
    if len(args) == 5 and args[0] == "-replace" and args[2] == "-string":
        info[args[1]] = args[3]
    elif len(args) == 3 and args[0] == "-remove":
        if args[1] not in info:
            sys.exit(f"{path}: No value to remove at key path {args[1]}")
        del info[args[1]]
    else:
        sys.exit("unexpected plutil call")
    path.write_bytes(plistlib.dumps(info))
elif name == "xcrun":
    if args[0] == "actool":
        if not pathlib.Path(args[1]).is_dir():
            sys.exit(f"actool: no icon at {args[1]}")
        out = pathlib.Path(args[args.index("--compile") + 1])
        icon = args[args.index("--app-icon") + 1]
        for filename in ["Assets.car", icon + ".icns", "partial.plist"]:
            (out / filename).touch()
    elif args[:2] == ["notarytool", "submit"]:
        status = env("MOCK_NOTARY_STATUS", "Accepted")
        print("Conducting pre-submission checks for Splay.zip and initiating connection to the Apple notary service...")
        print("Submission ID received\n  id: 00000000-0000-0000-0000-000000000000")
        print("Successfully uploaded file\nWaiting for processing to complete.")
        print(f"Current status: {status}...Processing complete")
        print(f"  id: 00000000-0000-0000-0000-000000000000\n  status: {status}")
    elif args[:2] != ["stapler", "staple"]:
        sys.exit("unexpected xcrun call")
elif name == "ditto":
    if args[0] == "-c":
        source, target = map(pathlib.Path, args[-2:])
        base = source.parent if "--keepParent" in args else source
        with zipfile.ZipFile(target, "w") as archive:
            for path in sorted(source.rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(base))
    elif args[0] == "-x":
        with zipfile.ZipFile(args[-2]) as archive:
            archive.extractall(args[-1])
        if env("MOCK_THIN_ARCHIVE"):
            (pathlib.Path(args[-1]) / "Splay.app/Contents/MacOS/splay").write_text("arm64")
    else:
        shutil.copytree(args[0], args[1], symlinks=True)
elif name == "git":
    if args != ["rev-list", "--count", "HEAD"]:
        sys.exit("unexpected git call")
    print("123")
elif name == "security":
    if args != ["find-identity", "-v", "-p", "codesigning"]:
        sys.exit("unexpected security call")
    print(os.environ["MOCK_IDENTITIES"], end="")
elif name == "sign_update":
    if not pathlib.Path(args[-1]).is_file():
        sys.exit("sign_update: no archive to sign")
    print("A" * 86 + "==")
elif name == "gh":
    if args[:2] != ["api", "markdown"] or "mode=markdown" not in args:
        sys.exit("unexpected gh call")
    if env("MOCK_GH_FAIL"):
        sys.exit("gh: HTTP 503")
    text = next(arg[len("text="):] for arg in args if arg.startswith("text="))
    print(f'<div class="from-gh">{html.escape(text)}</div>')
elif name not in ["codesign", "spctl"]:
    sys.exit("unexpected command: " + name)
'''
# Replaces mv for bundle.sh, and fails to move the staged app into place.
MOVE_FAILS = """#!/bin/bash
[[ "$1" == */.staging/Splay.app ]] && { echo "mv: mock failure" >&2; exit 1; }
exec /bin/mv "$@"
"""


@unittest.skipUnless(sys.platform == "darwin", "package-release.sh reads plists with macOS's PlistBuddy")
class PackagingTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="splay-packaging-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        shutil.copytree(ROOT / "scripts", self.root / "scripts", ignore=shutil.ignore_patterns("tests", "__pycache__"))
        (self.root / "Resources/Splay.icon").mkdir(parents=True)
        shutil.copy(ROOT / "Resources/Info.plist", self.root / "Resources/Info.plist")
        self.source_info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        (self.root / "docs").mkdir()
        (self.root / "docs/changelog.md").write_text(CHANGELOG)
        self.framework = (self.root / ".build/artifacts/sparkle/Sparkle/macos-arm64_x86_64"
                          / "Sparkle.framework/Versions/Current")
        for binary in SPARKLE_BINARIES:
            path = self.framework / binary
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("arm64 x86_64")
        mock_bin = self.root / "mock-bin"
        for name in MOCKED:
            self.write_tool(mock_bin / name, MOCK)
        self.signer = self.root / ".build/artifacts/sparkle/Sparkle/bin/sign_update"
        self.write_tool(self.signer, MOCK)
        self.log = self.root / "commands.jsonl"
        # Only what the scripts need, so release settings in the shell running the tests change nothing.
        self.env = {
            "PATH": f"{mock_bin}:{os.environ['PATH']}", "HOME": str(self.root / "home"),
            "MOCK_LOG": str(self.log), "MOCK_IDENTITIES": IDENTITIES, "NOTARYTOOL_PROFILE": "test-profile",
        }
        if "TMPDIR" in os.environ:
            self.env["TMPDIR"] = os.environ["TMPDIR"]
        for name in MOCKED:
            self.assertEqual(shutil.which(name, path=self.env["PATH"]), str(mock_bin / name),
                             f"the real {name} would run")

    @staticmethod
    def write_tool(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(0o755)

    def run_script(self, script, *args, **env):
        """Runs scripts/<script>. An environment variable given as None is unset."""
        env = {key: value for key, value in {**self.env, **env}.items() if value is not None}
        return subprocess.run(["bash", f"scripts/{script}", *args], cwd=self.root, env=env,
                              text=True, capture_output=True)

    def run_appcast(self, version, **env):
        return subprocess.run([sys.executable, "scripts/appcast.py", version], cwd=self.root,
                              env={**self.env, **env}, text=True, capture_output=True)

    def commands(self, name=None):
        lines = self.log.read_text().splitlines() if self.log.exists() else []
        return [command for command in map(json.loads, lines) if name in (None, command[0])]

    def clear_log(self):
        self.log.unlink(missing_ok=True)

    def signed_with(self):
        return [command[command.index("--sign") + 1] for command in self.commands("codesign") if "--sign" in command]

    def info(self, app):
        return plistlib.loads((self.root / app / "Contents/Info.plist").read_bytes())

    def write_info(self, **changes):
        """Writes Resources/Info.plist as the checkout has it, with changes. A key given as None is removed."""
        info = dict(self.source_info)
        for key, value in changes.items():
            if value is None:
                info.pop(key)
            else:
                info[key] = value
        (self.root / "Resources/Info.plist").write_bytes(plistlib.dumps(info))

    def stage_release(self, version="0.24", build="223", archs="arm64 x86_64", changelog=CHANGELOG):
        """Puts in place what package-release.sh leaves for appcast.py."""
        contents = self.root / "dist/build/Splay.app/Contents"
        (contents / "MacOS").mkdir(parents=True, exist_ok=True)
        info = {**self.source_info, "CFBundleShortVersionString": version, "CFBundleVersion": build}
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        (contents / "MacOS/splay").write_text(archs)
        (self.root / "dist/Splay.app.zip").write_bytes(b"zip" * 1000)
        (self.root / "dist/signature.txt").write_text(SIGNATURE + "\n")
        (self.root / "docs/changelog.md").write_text(changelog)
        (self.root / "dist/appcast.xml").unlink(missing_ok=True)

    def appcast_item(self):
        return ET.parse(self.root / "dist/appcast.xml").getroot().find("channel/item")

    # scripts/bundle.sh and scripts/check-universal.sh

    def test_universal_build_and_lookup_flags_match(self):
        result = self.run_script("bundle.sh", UNIVERSAL="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        flags = ["-c", "release", "--jobs", "4", "--arch", "arm64", "--arch", "x86_64"]
        self.assertEqual(self.commands("swift"), [["swift", "build", *flags],
                                                  ["swift", "build", *flags, "--show-bin-path"]])
        self.assertEqual(len(self.commands("lipo")), CHECKS_PER_APP)
        self.assertEqual((self.root / "build/Splay.app/Contents/MacOS/splay").read_text(), "arm64 x86_64")

    def test_default_and_debug_builds_stay_native(self):
        for args, config in [((), "release"), (("--debug",), "debug")]:
            with self.subTest(config=config):
                self.clear_log()
                result = self.run_script("bundle.sh", *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                flags = ["-c", config, "--jobs", "4"]
                self.assertEqual(self.commands("swift"), [["swift", "build", *flags],
                                                          ["swift", "build", *flags, "--show-bin-path"]])
                self.assertEqual(self.commands("lipo"), [])

    def test_every_thin_or_missing_sparkle_binary_fails_before_signing(self):
        for binary in SPARKLE_BINARIES:
            path = self.framework / binary
            for missing in [False, True]:
                with self.subTest(binary=binary, missing=missing):
                    if missing:
                        path.unlink()
                    else:
                        path.write_text("arm64")
                    self.clear_log()
                    result = self.run_script("bundle.sh", UNIVERSAL="1")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(f"{binary} has no", result.stderr)
                    self.assertEqual(self.commands("codesign"), [])
                    self.assertFalse((self.root / "build/Splay.app").exists())
                    self.assertFalse((self.root / "build/.staging").exists())
                    path.write_text("arm64 x86_64")

    def test_validator_rejects_thin_main_executable(self):
        contents = self.root / "thin/Splay.app/Contents"
        (contents / "MacOS").mkdir(parents=True)
        shutil.copytree(self.framework, contents / "Frameworks/Sparkle.framework/Versions/Current")
        executable = contents / "MacOS/splay"
        executable.write_text("arm64 x86_64")
        result = self.run_script("check-universal.sh", str(contents.parent))
        self.assertEqual(result.returncode, 0, result.stderr)
        for archs in ["arm64", "x86_64"]:
            with self.subTest(archs=archs):
                executable.write_text(archs)
                result = self.run_script("check-universal.sh", str(contents.parent))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("MacOS/splay has no", result.stderr)

    def test_default_bundle_is_a_source_build_without_the_update_feed(self):
        result = self.run_script("bundle.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("built build/Splay.app", result.stdout)
        contents = self.root / "build/Splay.app/Contents"
        # The SwiftPM product keeps upstream's name and is renamed in the bundle.
        self.assertEqual((contents / "MacOS/splay").read_text(), "arm64")
        self.assertEqual(sorted(os.listdir(contents / "Resources")), ["Assets.car", "Splay.icns"])
        info = self.info("build/Splay.app")
        self.assertNotIn("SUFeedURL", info)
        self.assertEqual(info["SUPublicEDKey"], self.source_info["SUPublicEDKey"])
        self.assertEqual((info["CFBundleShortVersionString"], info["CFBundleVersion"]), ("0.0", "123"))
        self.assertEqual((info["CFBundleIconFile"], info["CFBundleIconName"]), ("Splay", "Splay"))
        # Signed inside out, Sparkle's helpers first, then the framework, then the app.
        self.assertEqual([Path(command[-1]).name for command in self.commands("codesign")], [
            "Downloader.xpc", "Installer.xpc", "Updater.app", "Autoupdate", "Sparkle", "Sparkle.framework",
            "Splay.app",
        ])
        self.assertEqual(os.listdir(self.root / "build"), ["Splay.app"])

    def test_feed_1_keeps_the_update_feed(self):
        for feed, kept in [("1", True), ("0", False), ("", False)]:
            with self.subTest(FEED=feed):
                result = self.run_script("bundle.sh", FEED=feed, VERSION="0.24")
                self.assertEqual(result.returncode, 0, result.stderr)
                info = self.info("build/Splay.app")
                self.assertEqual(info.get("SUFeedURL"), self.source_info["SUFeedURL"] if kept else None)
                self.assertEqual(info["SUPublicEDKey"], self.source_info["SUPublicEDKey"])
                self.assertEqual(info["CFBundleShortVersionString"], "0.24")

    def test_bundle_signs_with_an_apple_development_identity_by_hash(self):
        only_developer_id = IDENTITIES.splitlines()[1] + "\n"
        cases = [
            ("the first Apple Development identity", {}, APPLE_DEVELOPMENT, "signed Apple Development"),
            ("ad hoc without one", {"MOCK_IDENTITIES": only_developer_id}, "-", "signed ad hoc"),
            ("the one IDENTITY names", {"IDENTITY": "Some Name"}, "Some Name", "signed custom"),
            ("ad hoc when IDENTITY is -", {"IDENTITY": "-"}, "-", "signed ad hoc"),
        ]
        for case, env, identity, said in cases:
            with self.subTest(case):
                self.clear_log()
                result = self.run_script("bundle.sh", **env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(set(self.signed_with()), {identity})
                self.assertIn(said, result.stdout)
                self.assertEqual("No Apple Development identity" in result.stderr, "MOCK_IDENTITIES" in env)
                self.assertEqual(self.commands("security") == [], "IDENTITY" in env)

    def test_out_is_honoured_and_build_is_left_alone(self):
        running = self.root / "build/Splay.app/Contents/MacOS/splay"
        running.parent.mkdir(parents=True)
        running.write_text("the copy that is running")
        for out in ["elsewhere/Splay.app", str(self.root / "absolute/Splay.app")]:
            with self.subTest(OUT=out):
                self.clear_log()
                result = self.run_script("bundle.sh", OUT=out)
                self.assertEqual(result.returncode, 0, result.stderr)
                app = self.root / out
                self.assertEqual((app / "Contents/MacOS/splay").read_text(), "arm64")
                self.assertEqual(os.listdir(app.parent), ["Splay.app"])
                self.assertEqual(running.read_text(), "the copy that is running")
                self.assertEqual(os.listdir(self.root / "build"), ["Splay.app"])
                self.assertEqual(sorted(path.name for path in (self.root / "build/Splay.app").rglob("*")),
                                 ["Contents", "MacOS", "splay"])
                touched = [command for command in self.commands() for arg in command[1:]
                           if arg.startswith(("build/", str(self.root / "build") + "/"))]
                self.assertEqual(touched, [])

    def test_an_app_already_at_out_survives_a_failed_build(self):
        app = self.root / "build/Splay.app"
        move_fails = self.root / "move-fails"
        self.write_tool(move_fails / "mv", MOVE_FAILS)
        # Each failure, and how many codesign calls run before it.
        failures = [
            ("the build", {"MOCK_FAIL": "swift"}, 0),
            ("signing the app", {"MOCK_FAIL": "codesign Splay.app"}, 7),
            ("the move into place", {"PATH": f"{move_fails}:{self.env['PATH']}"}, 7),
        ]
        for failure, env, signs in failures:
            with self.subTest(failure):
                shutil.rmtree(app, ignore_errors=True)
                (app / "Contents/MacOS").mkdir(parents=True)
                (app / "Contents/MacOS/splay").write_text("the working app")
                self.clear_log()
                result = self.run_script("bundle.sh", **env)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(self.commands("codesign")), signs, result.stderr)
                self.assertEqual((app / "Contents/MacOS/splay").read_text(), "the working app")
                self.assertEqual(os.listdir(app.parent), ["Splay.app"])
        result = self.run_script("bundle.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((app / "Contents/MacOS/splay").read_text(), "arm64")
        self.assertEqual(os.listdir(app.parent), ["Splay.app"])

    # scripts/package-release.sh

    def test_package_checks_the_shipped_archive(self):
        result = self.run_script("package-release.sh", "0.24")
        self.assertEqual(result.returncode, 0, result.stderr)
        app = "dist/build/Splay.app"
        commands = self.commands()
        # bundle.sh checks the staged app, then package-release.sh checks the app and the archive.
        self.assertEqual(len([command for command in self.commands("lipo") if "-verify_arch" in command]),
                         3 * CHECKS_PER_APP)
        verified = commands.index(["codesign", "--verify", "--strict", "--verbose=1", app])
        notarized = next(i for i, command in enumerate(commands) if command[:3] == ["xcrun", "notarytool", "submit"])
        self.assertEqual(commands[notarized][4:], ["--keychain-profile", "test-profile", "--wait"])
        stapled = commands.index(["xcrun", "stapler", "staple", app])
        assessed = commands.index(["spctl", "--assess", "--type", "execute", "--verbose=1", app])
        zipped = commands.index(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, "dist/Splay.app.zip"])
        unpacked = next(i for i, command in enumerate(commands) if command[:3] == ["ditto", "-x", "-k"])
        self.assertEqual(commands[unpacked][3], "dist/Splay.app.zip")
        checked = [i for i, command in enumerate(commands)
                   if command[0] == "lipo" and "/unpacked/Splay.app/" in command[1]]
        self.assertEqual(len(checked), CHECKS_PER_APP)
        signed = commands.index(["sign_update", "--account", "com.shawnschwartz.splay", "-p", "dist/Splay.app.zip"])
        steps = [verified, notarized, stapled, assessed, zipped, unpacked, min(checked), max(checked), signed]
        self.assertEqual(steps, sorted(steps), "the steps ran out of order")

        for command in self.commands("codesign"):
            if command[1] == "--force":
                self.assertEqual(command[2:7], ["--options", "runtime", "--timestamp", "--sign", DEVELOPER_ID])
        info = self.info(app)
        self.assertEqual(info["SUFeedURL"], self.source_info["SUFeedURL"])
        self.assertEqual(info["SUPublicEDKey"], self.source_info["SUPublicEDKey"])
        self.assertEqual((info["CFBundleShortVersionString"], info["CFBundleVersion"]), ("0.24", "223"))
        dist = self.root / "dist"
        self.assertEqual((dist / "signature.txt").read_text().strip(), SIGNATURE)
        self.assertEqual(list(dist.glob("*.rb")), [], "Splay ships no Homebrew cask")
        self.assertFalse((self.root / "build").exists(), "a copy running from build/ is left alone")
        item = self.appcast_item()
        self.assertEqual(item.find("enclosure").get(f"{SPARKLE}version"), "223")
        self.assertIsNone(item.find(f"{SPARKLE}hardwareRequirements"))
        self.assertIn("Changed in 0.24.", item.findtext("description"))

    def test_thin_archive_fails_before_sparkle_signing(self):
        result = self.run_script("package-release.sh", "0.24", MOCK_THIN_ARCHIVE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unpacked/Splay.app/Contents/MacOS/splay has no x86_64 slice", result.stderr)
        self.assertEqual(self.commands("sign_update"), [])
        self.assertFalse((self.root / "dist/signature.txt").exists())
        self.assertFalse((self.root / "dist/appcast.xml").exists())

    def test_package_needs_a_notarization_profile(self):
        for profile in [None, ""]:
            with self.subTest(NOTARYTOOL_PROFILE=profile):
                self.clear_log()
                result = self.run_script("package-release.sh", "0.24", NOTARYTOOL_PROFILE=profile)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Set NOTARYTOOL_PROFILE", result.stderr)
                self.assertEqual(self.commands(), [], "it stops before building")

    def test_package_takes_x_y_versions(self):
        for version, said in [("0.24.1", "Expected version X.Y"), ("1", "Expected version X.Y"),
                              ("0.x", "Expected version X.Y"), ("", "Usage")]:
            with self.subTest(version=version):
                result = self.run_script("package-release.sh", version)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(said, result.stderr)
                self.assertEqual(self.commands("swift"), [])
        result = self.run_script("package-release.sh", "v0.24")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.info("dist/build/Splay.app")["CFBundleShortVersionString"], "0.24")
        self.assertIn("/download/v0.24/", self.appcast_item().find("enclosure").get("url"))

    def test_package_signs_with_a_developer_id_identity(self):
        named = "Developer ID Application: Someone Else (TEAM000002)"
        result = self.run_script("package-release.sh", "0.24", DEVELOPER_ID_APPLICATION=named)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(self.signed_with()), {named})
        self.assertEqual(self.commands("security"), [])
        self.clear_log()
        result = self.run_script("package-release.sh", "0.24", MOCK_IDENTITIES=IDENTITIES.splitlines()[0] + "\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No Developer ID Application identity", result.stderr)
        self.assertEqual(self.commands("swift"), [])

    def test_package_stops_when_the_packaged_info_plist_lacks_a_sparkle_key(self):
        for key, value in [("SUFeedURL", None), ("SUPublicEDKey", None), ("SUPublicEDKey", "")]:
            with self.subTest(key=key, value=value):
                self.write_info(**{key: value})
                self.clear_log()
                result = self.run_script("package-release.sh", "0.24")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"The packaged Info.plist has no {key}", result.stderr)
                self.assertFalse(any(command[:2] == ["xcrun", "notarytool"] for command in self.commands()))
                self.assertFalse((self.root / "dist/Splay.app.zip").exists())

    def test_package_stops_when_notarization_is_not_accepted(self):
        dist = self.root / "dist"
        for status in ["Invalid", "Rejected"]:
            with self.subTest(status=status):
                # Files from an earlier run, which the script removes so they cannot pass for this run's.
                dist.mkdir(exist_ok=True)
                for stale in ["Splay.app.zip", "signature.txt", "appcast.xml"]:
                    (dist / stale).write_text("from an earlier run")
                self.clear_log()
                result = self.run_script("package-release.sh", "0.24", MOCK_NOTARY_STATUS=status)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Notarization was not accepted", result.stderr)
                commands = self.commands()
                self.assertTrue(any(command[:3] == ["xcrun", "notarytool", "submit"] for command in commands))
                self.assertFalse(any(command[:2] == ["xcrun", "stapler"] for command in commands))
                self.assertEqual(self.commands("spctl") + self.commands("sign_update"), [])
                self.assertEqual(os.listdir(dist), ["build"])

    def test_package_stops_without_sign_update(self):
        for case in ["not executable", "missing"]:
            with self.subTest(case):
                if case == "missing":
                    self.signer.unlink()
                else:
                    self.signer.chmod(0o644)
                self.clear_log()
                result = self.run_script("package-release.sh", "0.24")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("sign_update not found under .build/artifacts", result.stderr)
                self.assertEqual(self.commands("sign_update"), [])
                self.assertFalse((self.root / "dist/signature.txt").exists())
                self.assertFalse((self.root / "dist/appcast.xml").exists())

    def test_package_finds_a_sign_update_that_the_build_resolves(self):
        # In a fresh checkout SwiftPM downloads Sparkle, and sign_update with it, during the build.
        self.signer.unlink()
        result = self.run_script("package-release.sh", "0.24", MOCK_BUILD_RESOLVES_SIGN_UPDATE="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.commands("sign_update")), 1)
        self.assertEqual((self.root / "dist/signature.txt").read_text().strip(), SIGNATURE)

    # scripts/appcast.py

    def test_appcast_keeps_architecture_safeguard(self):
        for archs, expected in [("arm64", "arm64"), ("arm64 x86_64", None), ("x86_64", None)]:
            with self.subTest(archs=archs):
                self.stage_release(archs=archs)
                result = self.run_appcast("0.24")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.appcast_item().findtext(f"{SPARKLE}hardwareRequirements"), expected)

    def test_appcast_describes_the_release(self):
        self.stage_release()
        result = self.run_appcast("0.24")
        self.assertEqual(result.returncode, 0, result.stderr)
        channel = ET.parse(self.root / "dist/appcast.xml").getroot().find("channel")
        self.assertEqual(channel.findtext("title"), "Splay")
        item = channel.find("item")
        self.assertEqual(item.findtext("title"), "0.24")
        self.assertIsNotNone(email.utils.parsedate_to_datetime(item.findtext("pubDate")))
        self.assertEqual(item.findtext(f"{SPARKLE}minimumSystemVersion"), self.source_info["LSMinimumSystemVersion"])
        self.assertEqual(item.find("enclosure").attrib, {
            "url": "https://github.com/shawntz/splay/releases/download/v0.24/Splay.app.zip",
            "length": str((self.root / "dist/Splay.app.zip").stat().st_size),
            "type": "application/octet-stream",
            f"{SPARKLE}version": "223",
            f"{SPARKLE}shortVersionString": "0.24",
            f"{SPARKLE}edSignature": SIGNATURE,
        })

    def test_release_notes_come_from_the_versions_changelog_section(self):
        for version, section in [("0.24", "- Changed in 0.24.\n- Also changed in 0.24."), ("0.2", "- Changed in 0.2.")]:
            with self.subTest(version=version):
                self.stage_release(version=version)
                self.clear_log()
                result = self.run_appcast(version)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.commands("gh"), [["gh", "api", "markdown", "-f", "mode=markdown",
                                                        "-f", f"text={section}"]])
                item = self.appcast_item()
                notes = item.findtext("description")
                self.assertIn(f'<div class="from-gh">{html.escape(section)}</div>', notes)
                self.assertIn('href="https://shawntz.github.io/splay/changelog/"', notes)
                self.assertIsNone(item.find(f"{SPARKLE}releaseNotesLink"))

    def test_release_notes_fall_back_to_the_release_page(self):
        cases = [
            ("no section", "0.3", CHANGELOG),
            ("an empty section", "0.24", "# Changelog\n\n## 0.24\n\n## 0.23\n\n- Changed in 0.23.\n"),
            ("only a longer version's section", "0.2", "# Changelog\n\n## 0.24\n\n- Changed in 0.24.\n"),
        ]
        for case, version, changelog in cases:
            with self.subTest(case):
                self.stage_release(version=version, changelog=changelog)
                self.clear_log()
                result = self.run_appcast(version)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.commands("gh"), [])
                item = self.appcast_item()
                self.assertIsNone(item.find("description"))
                self.assertEqual(item.findtext(f"{SPARKLE}releaseNotesLink"),
                                 f"https://github.com/shawntz/splay/releases/tag/v{version}")

    def test_a_failing_gh_stops_the_appcast(self):
        self.stage_release()
        result = self.run_appcast("0.24", MOCK_GH_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "dist/appcast.xml").exists())

    def test_appcast_refuses_another_version_or_a_bad_signature(self):
        self.stage_release(version="0.23")
        self.assertNotEqual(self.run_appcast("0.24").returncode, 0)
        self.assertFalse((self.root / "dist/appcast.xml").exists())
        self.stage_release()
        (self.root / "dist/signature.txt").write_text("not a signature\n")
        self.assertNotEqual(self.run_appcast("0.24").returncode, 0)
        self.assertFalse((self.root / "dist/appcast.xml").exists())


if __name__ == "__main__":
    unittest.main()
