---
layout: default
title: Changelog
description: Splay has no releases yet. What it changes from Dinky so far.
permalink: /changelog/
---

<p class="github-only">This page is part of Splay's manual. Read it with its figures and navigation at
https://shawntz.github.io/splay/changelog/.</p>

# Changelog

Splay has no releases yet. It is built from source, and its history is the
git log. `CHANGELOG.md` in the source is upstream Dinky's, merged in as it
stands: it lists Dinky's releases, not Splay's.

## Unreleased

What Splay changes from the Dinky it merges:

- Scrolling is the default layout, and Cmd-Left and Cmd-Right focus left and
  right along the strip. Alt-H and Alt-L are left unbound.
- The strip commands `center-column`, `column-width`, `maximize-column` and
  `focus-column`, in the menu and on Alt-C, Alt-R and Alt-Shift-R, Alt-M, and
  Cmd-Home and Cmd-End.
- The `[scrolling]` keys `center-focused-column`, `preset-column-widths` and
  `peek`.
- A focus step into another column lands on the window last focused in it.
- Another column closing or changing width leaves the focused column where it
  is on screen.
- Windows already open at launch go into the strip left to right, as they
  stand on screen.
- For half a second after Splay focuses a window, or until macOS reports it
  in front, commands start from that window. Quick presses of `focus right`
  step one column each, and a command pressed right after acts on the window
  just focused.
- Closing the terminal an attached run was started from quits it and puts the
  windows back.
- Closing the Accessibility window before granting access quits Splay.
- Started from a terminal or another app, the Accessibility window and
  `splay doctor` say whose grant counts.
- A strip command in a rule works on the window the rule matched.
- `splay version` reads the app's version through a link to the executable.
- Each tree in `debug-state` names its layout.
- `start-at-login` is `false` unless set.
- Its own names, so it can sit beside Dinky: the `splay` command,
  `~/.config/splay/splay.toml`, `$TMPDIR/splay.sock`,
  `~/Library/Logs/splay.log`, `~/Library/Application Support/splay`,
  `SPLAY_` hook variables and the bundle ID `com.shawnschwartz.splay`.
- A running Dinky counts as another tiling window manager.
- No updater, download or Homebrew cask: Splay is built with
  `scripts/bundle.sh`.
