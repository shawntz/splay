"""Runs a copy of scripts/release.sh against mock git, gh and swift and a stub package-release.sh, to exercise
the Homebrew tap steps. Nothing real is cloned, pushed or published."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
MOCK = r'''#!/usr/bin/env -S python3 -I -S
import json, os, pathlib, shutil, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
env = os.environ.get
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(json.dumps([name, *args]) + "\n")
fail = env("MOCK_FAIL", "").split(",")

if name == "swift":
    sys.exit(0 if args[:1] == ["test"] else "unexpected swift call")
elif name == "git":
    if args[:1] == ["-C"]:
        checkout, sub = pathlib.Path(args[1]), args[2:]
        if sub[:1] == ["add"]:
            pass
        elif sub[:3] == ["diff", "--cached", "--quiet"]:
            sys.exit(0 if env("MOCK_TAP_SAME") else 1)
        elif sub[:1] == ["commit"]:
            (checkout / ".message").write_text(sub[sub.index("-m") + 1])
        elif sub[:1] == ["push"]:
            if "tap-push" in fail:
                sys.exit("git push: mock failure")
            pushed = pathlib.Path(os.environ["MOCK_PUSHED"])
            pushed.mkdir(parents=True, exist_ok=True)
            shutil.copy(checkout / "Casks/splay.rb", pushed / "splay.rb")
            shutil.copy(checkout / ".message", pushed / "message")
        else:
            sys.exit("unexpected git -C call")
    elif args[:1] == ["clone"]:
        if args[-2] != "git@github.com:shawntz/homebrew-tap.git":
            sys.exit("cloned another repository")
        if "tap-clone" in fail:
            sys.exit("git clone: mock failure")
        pathlib.Path(args[-1], "Casks").mkdir(parents=True, exist_ok=True)
    elif args == ["branch", "--show-current"]:
        print("main")
    elif args == ["status", "--porcelain"] or args[:1] in (["fetch"], ["tag"], ["push"]):
        pass
    elif args == ["log", "-1", "--format=%s"]:
        print("Release 0.3")
    elif args[:1] == ["rev-parse"]:
        if "--verify" in args:
            sys.exit(1)
        print("a" * 40)
    else:
        sys.exit("unexpected git call: " + " ".join(args))
elif name == "gh":
    if args[:2] == ["release", "view"]:
        if args[2] == "-R":
            print(env("MOCK_LATEST", "v0.2"))
        elif "--json" in args and env("MOCK_PUBLISHED"):
            print("false")
        else:
            sys.exit(1)
    elif args[:2] == ["release", "download"]:
        if "download" in fail:
            sys.exit("no assets match the file pattern")
        dist = pathlib.Path(args[args.index("-D") + 1])
        (dist / "splay.rb").write_text(env("MOCK_ASSET"))
    elif args[:2] == ["release", "upload"]:
        for path in args[5:-1]:
            if not pathlib.Path(path).is_file():
                sys.exit(f"no {path} to upload")
    elif args[:2] in (["release", "create"], ["release", "edit"], ["workflow", "run"]):
        pass
    else:
        sys.exit("unexpected gh call: " + " ".join(args))
'''
PACKAGE = r'''#!/usr/bin/env bash
set -euo pipefail
echo '["package-release.sh"]' >> "$MOCK_LOG"
printf 'zip' > dist/Splay.app.zip
printf '<rss/>' > dist/appcast.xml
sed -e "s/@VERSION@/$1/" -e "s/@SHA256@/$(shasum -a 256 dist/Splay.app.zip | cut -d' ' -f1)/" scripts/splay.rb.template > dist/splay.rb
'''


class ReleaseTapTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="splay-release-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        (self.root / "scripts").mkdir()
        shutil.copy(REPO / "scripts/release.sh", self.root / "scripts/release.sh")
        shutil.copy(REPO / "scripts/splay.rb.template", self.root / "scripts/splay.rb.template")
        self.tool(self.root / "scripts/package-release.sh", PACKAGE)
        (self.root / "docs").mkdir()
        (self.root / "docs/_config.yml").write_text('version: "0.3"\n')
        (self.root / "docs/changelog.md").write_text("# Changelog\n\n## 0.3\n\n- Changed.\n\n## 0.2\n\n- Old.\n")
        bin_ = self.root / "mock-bin"
        for name in ["git", "gh", "swift"]:
            self.tool(bin_ / name, MOCK)
        self.log = self.root / "commands.jsonl"
        self.pushed = self.root / "pushed"
        self.env = {"PATH": f"{bin_}:{os.environ['PATH']}", "HOME": str(self.root / "home"),
                    "MOCK_LOG": str(self.log), "MOCK_PUSHED": str(self.pushed), "NOTARYTOOL_PROFILE": "p",
                    "TMPDIR": str(self.root / "tmp")}
        (self.root / "tmp").mkdir()
        for name in ["git", "gh", "swift"]:
            self.assertEqual(shutil.which(name, path=self.env["PATH"]), str(bin_ / name))

    @staticmethod
    def tool(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(0o755)

    def run_release(self, **env):
        return subprocess.run(["bash", "scripts/release.sh"], cwd=self.root, env={**self.env, **env},
                              text=True, capture_output=True)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def index(self, prefix):
        return next(i for i, c in enumerate(self.commands()) if c[:len(prefix)] == prefix)

    def asset(self, version):
        return (REPO / "scripts/splay.rb.template").read_text().replace("@VERSION@", version).replace("@SHA256@", "0" * 64)

    def test_a_new_release_uploads_the_cask_then_updates_the_tap_then_the_site(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        upload = self.commands()[self.index(["gh", "release", "upload"])]
        self.assertIn("dist/splay.rb", upload)
        published = self.index(["gh", "release", "edit", "v0.3", "-R", "shawntz/splay", "--draft=false"])
        cloned = self.index(["git", "clone"])
        site = self.index(["gh", "workflow", "run"])
        self.assertLess(published, cloned)
        self.assertLess(cloned, site)
        self.assertEqual((self.pushed / "splay.rb").read_text(), (self.root / "dist/splay.rb").read_text())
        self.assertIn('version "0.3"', (self.pushed / "splay.rb").read_text())
        self.assertEqual((self.pushed / "message").read_text(), "Update splay to 0.3")
        self.assertNotIn("warning", result.stderr)
        self.assertIn("==> Homebrew tap: splay 0.3", result.stdout)
        self.assertEqual(os.listdir(self.root / "tmp"), [], "the temporary clone is removed")

    def test_a_failed_tap_update_warns_and_still_deploys_the_site(self):
        for failure in ["tap-clone", "tap-push"]:
            with self.subTest(failure):
                self.log.unlink(missing_ok=True)
                result = self.run_release(MOCK_FAIL=failure)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("v0.3 is published, but the Homebrew tap was not updated", result.stderr)
                self.assertIn("to retry, run scripts/release.sh 0.3 while HEAD is still the Release 0.3 commit", result.stderr)
                self.assertIn("==> https://github.com/shawntz/splay/releases/tag/v0.3", result.stdout)
                self.assertNotIn("==> Homebrew tap", result.stdout)
                self.index(["gh", "workflow", "run"])
                self.assertFalse(self.pushed.exists())
                self.assertEqual(os.listdir(self.root / "tmp"), [])

    def test_an_unchanged_tap_is_not_committed(self):
        result = self.run_release(MOCK_TAP_SAME="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(c[:2] == ["git", "-C"] and c[3] in ("commit", "push") for c in self.commands()))
        self.assertIn("==> Homebrew tap: splay 0.3", result.stdout)

    def test_a_published_release_retries_the_tap_with_its_own_cask(self):
        result = self.run_release(MOCK_PUBLISHED="1", MOCK_LATEST="v0.3", MOCK_ASSET=self.asset("0.3"))
        self.assertEqual(result.returncode, 0, result.stderr)
        names = [c[0] for c in self.commands()]
        self.assertNotIn("package-release.sh", names)
        self.assertFalse(any(c[:3] in (["gh", "release", "upload"], ["gh", "release", "create"]) for c in self.commands()))
        downloaded = self.index(["gh", "release", "download", "v0.3", "-R", "shawntz/splay", "-p", "splay.rb"])
        self.assertLess(downloaded, self.index(["git", "clone"]))
        self.assertLess(self.index(["git", "clone"]), self.index(["gh", "workflow", "run"]))
        self.assertEqual((self.pushed / "splay.rb").read_text(), self.asset("0.3"))
        self.assertNotIn("warning", result.stderr)

    def test_a_published_release_whose_tap_retry_fails_still_deploys_the_site(self):
        cases = [("no cask asset", {"MOCK_FAIL": "download"}), ("push fails", {"MOCK_FAIL": "tap-push"}),
                 ("another version's cask", {"MOCK_ASSET": self.asset("0.2")})]
        for case, env in cases:
            with self.subTest(case):
                self.log.unlink(missing_ok=True)
                result = self.run_release(MOCK_PUBLISHED="1", MOCK_LATEST="v0.3",
                                          **{"MOCK_ASSET": self.asset("0.3"), **env})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("the Homebrew tap was not updated", result.stderr)
                self.index(["gh", "workflow", "run"])
                self.assertFalse(self.pushed.exists())
                if case == "another version's cask":
                    self.assertIn("dist/splay.rb is not the cask for 0.3", result.stderr)
                    self.assertFalse(any(c[:2] == ["git", "clone"] for c in self.commands()))


if __name__ == "__main__":
    unittest.main()
