"""Run scripts/sync-upstream.sh against a throwaway fork and upstream. No network, and nothing outside a temp folder."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/sync-upstream.sh"


class SyncUpstreamTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="sync-upstream-"))
        self.addCleanup(shutil.rmtree, self.folder, ignore_errors=True)
        # Git's own settings only: no global config, hooks, signing or identity from the machine running this.
        self.env = {
            "PATH": os.environ["PATH"], "HOME": str(self.folder), "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
            "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid",
        }
        self.up, self.fork = self.folder / "up", self.folder / "fork"
        self.git(self.folder, "init", "-q", "-b", "main", "up")
        self.write(self.up, ".gitignore", "build/\n.claude/*\n")
        self.write(self.up, "README.md", "upstream readme\n")
        self.write(self.up, "RELEASING.md", "how upstream releases\n")
        self.write(self.up, "kept.txt", "one\n")
        self.commit(self.up, "base")
        self.git(self.folder, "clone", "-q", "up", "fork")
        self.git(self.fork, "remote", "rename", "origin", "upstream")
        # The fork: its own README, upstream's release notes gone, and the script under test.
        self.write(self.fork, "README.md", "the fork's readme\n")
        self.git(self.fork, "rm", "-q", "RELEASING.md")
        (self.fork / "scripts").mkdir()
        shutil.copy(SCRIPT, self.fork / "scripts/sync-upstream.sh")
        self.commit(self.fork, "fork")

    def git(self, cwd, *args):
        done = subprocess.run(["git", *args], cwd=cwd, env=self.env, capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        return done.stdout.strip()

    def write(self, repo, path, text):
        file = repo / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)

    def commit(self, repo, message):
        self.git(repo, "add", "-A")
        self.git(repo, "commit", "-q", "-m", message)

    def sync(self, **env):
        return subprocess.run([str(self.fork / "scripts/sync-upstream.sh")], cwd=self.fork, env={**self.env, **env},
                              capture_output=True, text=True)

    def merging(self):
        return (self.fork / ".git/MERGE_HEAD").exists()

    def test_nothing_new_upstream(self):
        done = self.sync()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("Already up to date with upstream/main.", done.stdout)
        self.assertNotIn("Merging", done.stdout, "it must stop before the merge and its advice")
        self.assertFalse(self.merging())

    def test_a_merge_that_needs_no_help_is_still_left_uncommitted(self):
        self.write(self.up, "kept.txt", "one\ntwo\n")
        self.commit(self.up, "upstream moves on")
        head = self.git(self.fork, "rev-parse", "HEAD")

        done = self.sync()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("No conflicts left to resolve.", done.stdout)
        self.assertEqual((self.fork / "kept.txt").read_text(), "one\ntwo\n")
        self.assertEqual(self.git(self.fork, "rev-parse", "HEAD"), head, "it must not commit")
        self.assertTrue(self.merging(), "the merge is left open to test")

    def test_merges_without_committing_and_says_what_is_left(self):
        self.write(self.up, "README.md", "upstream readme, edited\n")       # the fork rewrote it: by hand
        self.write(self.up, "RELEASING.md", "how upstream releases now\n")  # the fork deleted it: stays deleted
        self.write(self.up, ".fut/new.txt", "inside a folder the fork drops\n")
        self.write(self.up, "scripts/notarize, check.sh", "new upstream tooling\n")
        self.write(self.up, "kept.txt", "one\ntwo\n")                       # merges by itself
        self.commit(self.up, "upstream moves on")
        head = self.git(self.fork, "rev-parse", "HEAD")

        done = self.sync()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.git(self.fork, "rev-parse", "HEAD"), head, "it must not commit")
        self.assertTrue(self.merging(), "the merge is left open to test")
        self.assertFalse((self.fork / "RELEASING.md").exists())
        self.assertFalse((self.fork / ".fut/new.txt").exists())
        self.assertEqual((self.fork / "kept.txt").read_text(), "one\ntwo\n")

        kept, new, left = (self.section(done.stdout, title) for title in ("Kept deleted", "New from upstream", "Resolve by hand"))
        self.assertEqual(sorted(kept), [".fut/new.txt", "RELEASING.md"])
        self.assertEqual(new, ["scripts/notarize, check.sh"], "a new upstream file is named, not slipped in")
        self.assertEqual(left, ["README.md"])

    def test_refuses_to_let_the_merge_overwrite_an_ignored_local_file(self):
        self.write(self.fork, ".claude/settings.json", "MY LOCAL SETTINGS\n")  # ignored, so git status is clean
        self.write(self.up, ".claude/settings.json", "upstream settings\n")
        self.write(self.up, ".claude/Zed.md", "sorts before it in C, after it in other locales\n")
        self.git(self.up, "add", "-f", ".claude/settings.json", ".claude/Zed.md")
        self.git(self.up, "commit", "-q", "-m", "upstream adds a file at an ignored path")

        for locale in ("C", "en_US.UTF-8"):
            with self.subTest(locale=locale):
                done = self.sync(LC_ALL=locale)
                self.assertNotEqual(done.returncode, 0, done.stdout)
                self.assertIn("  .claude/settings.json", done.stderr)
                self.assertNotIn("Zed.md", done.stderr, "nothing local is in its way")
                self.assertEqual((self.fork / ".claude/settings.json").read_text(), "MY LOCAL SETTINGS\n")
                self.assertFalse(self.merging(), "it must stop before merging")

    def test_refuses_when_an_ignored_folder_stands_where_upstream_adds_a_file(self):
        self.write(self.fork, ".claude/worktrees/one/file.txt", "local work\n")
        self.write(self.up, ".claude/worktrees", "upstream makes this a file\n")
        self.git(self.up, "add", "-f", ".claude/worktrees")
        self.git(self.up, "commit", "-q", "-m", "upstream adds a file where a local folder is")

        done = self.sync()
        self.assertNotEqual(done.returncode, 0, done.stdout)
        self.assertIn("  .claude/worktrees", done.stderr)
        self.assertEqual((self.fork / ".claude/worktrees/one/file.txt").read_text(), "local work\n")
        self.assertFalse(self.merging())

    def test_refuses_when_an_ignored_file_stands_where_upstream_adds_a_folder(self):
        self.write(self.fork, ".claude/notes", "local notes\n")
        self.write(self.up, ".claude/notes/README.md", "upstream makes this a folder\n")
        self.git(self.up, "add", "-f", ".claude/notes/README.md")
        self.git(self.up, "commit", "-q", "-m", "upstream adds a folder where a local file is")

        done = self.sync()
        self.assertNotEqual(done.returncode, 0, done.stdout)
        self.assertIn("  .claude/notes", done.stderr)
        self.assertEqual((self.fork / ".claude/notes").read_text(), "local notes\n")
        self.assertFalse(self.merging())

    def test_refuses_when_upstream_moves_a_file_onto_an_ignored_local_one(self):
        self.write(self.fork, ".claude/settings.json", "MY LOCAL SETTINGS\n")
        (self.up / ".claude").mkdir()
        self.git(self.up, "mv", "-k", "kept.txt", ".claude/settings.json")
        self.git(self.up, "add", "-f", ".claude/settings.json")
        self.git(self.up, "commit", "-q", "-a", "-m", "upstream moves a file to an ignored path")

        done = self.sync()
        self.assertNotEqual(done.returncode, 0, done.stdout)
        self.assertIn("  .claude/settings.json", done.stderr)
        self.assertEqual((self.fork / ".claude/settings.json").read_text(), "MY LOCAL SETTINGS\n")
        self.assertFalse(self.merging())

    def test_a_file_both_sides_added_is_a_conflict_to_resolve_not_a_refusal(self):
        self.write(self.fork, "NOTES.md", "the fork's notes\n")
        self.commit(self.fork, "the fork adds notes")
        self.write(self.up, "NOTES.md", "upstream's notes\n")
        self.commit(self.up, "upstream adds notes too")

        done = self.sync()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.section(done.stdout, "Resolve by hand"), ["NOTES.md"])
        self.assertTrue(self.merging())

    def test_refuses_with_uncommitted_changes(self):
        self.write(self.up, "kept.txt", "one\ntwo\n")
        self.commit(self.up, "upstream moves on")
        self.write(self.fork, "kept.txt", "edited here\n")
        done = self.sync()
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("uncommitted changes", done.stderr)
        self.assertFalse(self.merging())

    @staticmethod
    def section(output, title):
        """The indented lines under the line that starts with `title`."""
        lines = output.splitlines()
        start = next((i for i, line in enumerate(lines) if line.startswith(title)), None)
        if start is None:
            return []
        found = []
        for line in lines[start + 1:]:
            if not line.startswith("  "):
                break
            found.append(line[2:])
        return found


if __name__ == "__main__":
    unittest.main()
