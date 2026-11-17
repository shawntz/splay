---
layout: default
title: Changelog
description: What changed in each release of Splay.
permalink: /changelog/
---

<p class="github-only">This page is part of Splay's manual. Read it with its figures and navigation at
https://shawntz.github.io/splay/changelog/.</p>

# Changelog

Splay's releases. `CHANGELOG.md` in the source is upstream Dinky's, merged in
as it stands, and lists Dinky's releases.

## 0.4

- The strip's default keys are on Option. A newly written config walks the strip with Alt-Left and Alt-Right and jumps to its ends with Alt-Home and Alt-End. Alt is the Option key. Cmd-Left and Cmd-Right stay with apps, where they reach the ends of a line in text fields and go back and forward in browsers. Cmd-Home and Cmd-End stay with apps too.
- Splay never rewrites your `splay.toml`, so a file written by 0.3 or earlier keeps Cmd-Left, Cmd-Right, Cmd-Home and Cmd-End. To switch, rename `cmd-left`, `cmd-right`, `cmd-home` and `cmd-end` in it to `alt-left`, `alt-right`, `alt-home` and `alt-end`. Splay's menu shows each command with the key your file gives it.
- With the new keys, Option-Left and Option-Right no longer move by a word in text fields. In standard macOS text fields Ctrl-Option-B and Ctrl-Option-F still do. `alt = 'left'` under `[modifiers]` leaves the right Option key to apps.

## 0.3

- `brew install --cask shawntz/tap/splay` installs Splay with Homebrew and links the `splay` command.
- A window Splay cannot reach when it quits, such as one closed with Cmd-W that its app keeps around, is no longer forgotten. Splay keeps its original place and puts it back at a later quit, once the window is open again. Before, it stayed at its tiled spot for good.
- The menu's Restore item, and `splay recover`, count only the windows a restore can reach now.

## 0.2

- When Splay finds a new version on its own, it shows `↑` after the workspace number and an Update to Splay item in its menu, and keeps both until you install or skip the update. Before, the update window could open behind other windows.
- A newly written config names Splay's schema on its first line, so editors with Taplo or Even Better TOML check and complete it with no setup. To get this in a config written by 0.1, add `#:schema https://shawntz.github.io/splay/schemas/splay.json` at the top.
- A build from source reports version 0.0 and carries no update feed, so it never offers to replace itself with a release.

## 0.1

The first release. What Splay adds to Dinky:

- Scrolling is the default layout, and Cmd-Left and Cmd-Right focus left and right along the strip. Alt-H and Alt-L are left unbound.
- The strip commands `center-column`, `column-width`, `maximize-column` and `focus-column`, in the menu and on Alt-C, Alt-R and Alt-Shift-R, Alt-M, and Cmd-Home and Cmd-End.
- The `[scrolling]` keys `center-focused-column`, `preset-column-widths` and `peek`.
- A focus step into another column lands on the window last focused in it.
- Another column closing or changing width leaves the focused column where it is on screen.
- Windows already open at launch go into the strip left to right, as they stand on screen.
- For half a second after Splay focuses a window, or until macOS reports it in front, commands start from that window. Quick presses of `focus right` step one column each, and a command pressed right after acts on the window just focused.
- Closing the terminal an attached run was started from quits it and puts the windows back.
- Closing the Accessibility window before granting access quits Splay.
- Started from a terminal or another app, the Accessibility window and `splay doctor` say whose grant counts.
- A strip command in a rule works on the window the rule matched.
- `splay version` reads the app's version through a link to the executable.
- Each tree in `debug-state` names its layout.
- `start-at-login` is `false` unless set.
- Its own names, so it can sit beside Dinky: the `splay` command, `~/.config/splay/splay.toml`, `$TMPDIR/splay.sock`, `~/Library/Logs/splay.log`, `~/Library/Application Support/splay`, `SPLAY_` hook variables and the bundle ID `com.shawnschwartz.splay`.
- A running Dinky counts as another tiling window manager.
- Releases are universal, signed with Developer ID and notarized. Splay updates itself from its own feed, with Check for Updates in the menu.
- If you ran a source build before, macOS still holds the Accessibility grant for that build's signature. Remove Splay from System Settings > Privacy & Security > Accessibility, or run `tccutil reset Accessibility com.shawnschwartz.splay`, then turn on the release.
