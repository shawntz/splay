#!/usr/bin/env bash
# Merges upstream Dinky's main into the current branch and stops before committing, so the merge can be
# tested first. Files Splay deleted on purpose stay deleted when upstream changes them; every other
# conflict is left to resolve by hand, and files new from upstream are listed to look over. Never pushes.
# Usage: scripts/sync-upstream.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export GIT_LITERAL_PATHSPECS=1  # paths below are file names, never globs

# Upstream files Splay removed: the release, Homebrew, appcast and VM tooling, upstream's agent and
# fut setup, and Dinky's icon. A trailing slash covers everything under a directory. Add a path here
# when the fork drops another upstream file.
DELETED=(
  .agents/skills/dinky-release/
  .claude/skills
  .fut/
  .github/workflows/pages.yml
  RELEASING.md
  Resources/Dinky.icon/
  docs/assets/icon.png
  scripts/appcast.py
  scripts/dinky.rb.template
  scripts/fuzz.py
  scripts/package-release.sh
  scripts/release.sh
  scripts/tests/test_packaging.py
  scripts/vm-fuzz.sh
  scripts/vm-install.sh
  scripts/vm-setup.sh
)

# Syncing only fetches and merges. Publishing stays a separate, deliberate step.
git() {
  if [[ "${1:-}" == push ]]; then echo "sync-upstream: refusing to push" >&2; exit 1; fi
  command git "$@"
}

die() { echo "sync-upstream: $*" >&2; exit 1; }

fork_deleted() {
  local path
  for path in "${DELETED[@]}"; do
    if [[ "$1" == "$path" || ( "$path" == */ && "$1" == "$path"* ) ]]; then return 0; fi
  done
  return 1
}

git remote get-url upstream >/dev/null 2>&1 || die "no remote named upstream"
branch="$(git symbolic-ref --quiet --short HEAD)" || die "HEAD is detached; check out the branch to merge into"
if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  die "a merge is already in progress; finish it or run git merge --abort"
fi
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "uncommitted changes; commit or stash them first"

# --no-tags: upstream's vX.Y tags would mix with Splay's own version numbers.
git fetch --no-tags upstream
count="$(git rev-list --count HEAD..upstream/main)"
if [[ "$count" == 0 ]]; then
  echo "Already up to date with upstream/main."
  exit 0
fi

# git merge replaces an ignored local file, without a word, when upstream adds a file at its path, and
# git merge --abort then removes it. Stop before that. Tracked files have no changes here, so anything that
# stands where upstream adds a file and is not tracked is in the way: a file or folder at that path, or a
# file where one of its folders has to go. --no-renames, so a file upstream moved counts as added.
clobbered=()
while IFS= read -r -d '' path; do
  if [[ -e "$path" || -L "$path" ]]; then
    git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || clobbered+=("$path")
    continue
  fi
  parent="$(dirname -- "$path")"
  while [[ "$parent" != . && "$parent" != / ]]; do
    if [[ ( -e "$parent" || -L "$parent" ) && ! -d "$parent" ]]; then clobbered+=("$parent"); break; fi
    parent="$(dirname -- "$parent")"
  done
done < <(git diff --no-renames --name-only --diff-filter=A -z HEAD...upstream/main)
if [[ ${#clobbered[@]} -gt 0 ]]; then
  echo "sync-upstream: upstream adds files where local files that git does not track are, and the merge would overwrite them. Move these away first:" >&2
  printf '  %s\n' "${clobbered[@]}" >&2
  exit 1
fi

echo "Merging $count upstream commits into $branch."

if ! git merge --no-ff --no-commit upstream/main; then
  git rev-parse -q --verify MERGE_HEAD >/dev/null || die "the merge did not start; see git's message above"
fi

# Upstream changed a file Splay deleted: keep it deleted. Only when Splay's side has no copy (no stage 2);
# a file the fork brought back is a real conflict.
kept=()
while IFS= read -r -d '' path; do
  fork_deleted "$path" || continue
  [[ -z "$(git ls-files -u -- "$path" | awk '$3 == 2')" ]] || continue
  git rm --quiet -- "$path"
  kept+=("$path")
done < <(git diff --name-only --diff-filter=U -z)

# New upstream files inside a deleted directory go too.
while IFS= read -r -d '' path; do
  fork_deleted "$path" || continue
  git rm --quiet -f -- "$path"
  kept+=("$path")
done < <(git diff --cached --name-only --diff-filter=A -z)

echo
if [[ ${#kept[@]} -gt 0 ]]; then
  echo "Kept deleted (Splay removed these on purpose):"
  printf '  %s\n' "${kept[@]}"
fi

# What upstream added and the merge took: nothing above looks at these, and no test reads scripts or resources.
added=()
while IFS= read -r -d '' path; do added+=("$path"); done < <(git diff --cached --name-only --diff-filter=A -z)
if [[ ${#added[@]} -gt 0 ]]; then
  echo "New from upstream (git rm what Splay has no use for, and list it in DELETED in this script):"
  printf '  %s\n' "${added[@]}"
fi

left=()
while IFS= read -r -d '' path; do left+=("$path"); done < <(git diff --name-only --diff-filter=U -z)
if [[ ${#left[@]} -gt 0 ]]; then
  echo "Resolve by hand, then git add each:"
  printf '  %s\n' "${left[@]}"
else
  echo "No conflicts left to resolve."
fi

cat <<'EOF'

Then:
  swift test          fails on upstream's name in a string literal in Sources or in Info.plist, and on its
                      command, paths or site in docs/ and the README
  read by hand        what the tests do not: the new files listed above, scripts/, and the prose of merged
                      docs, which may describe upstream's behaviour rather than Splay's
  git commit --no-edit
Or back out with: git merge --abort
Nothing was pushed. This script never pushes.
EOF
