---
layout: default
title: Get started
description: What Splay is, how to install it, its first run and keys, using it next to Dinky, and how to remove it.
permalink: /start/
---

<p class="github-only">This page is part of Splay's manual. Read it with its figures and navigation at
https://shawntz.github.io/splay/start/.</p>

# Get started

<pre><code>$ splay workspace 3
$ splay list-windows --workspace 3
4211 | Ghostty | ~
4388 | Safari  | Splay
$ splay column-width next <span class="cursor">█</span></code></pre>

Splay tiles the windows on each native Space as one row of columns that runs
past the edges of the display and scrolls sideways, after niri. A new window
opens as a column right of the focused one, and Cmd-Left and Cmd-Right walk
along the row.

Splay is a fork of [Dinky](https://github.com/mikker/Dinky) by Mikkel
Malmberg. It keeps Dinky's dwindle,
fixed and master layouts, an accordion mode, focus borders, a TOML config and a
`splay` command line for scripts and bars, and Dinky's way of switching Spaces,
which Dinky's manual puts at about 70 ms instead of half a second. Nothing is
injected into the Dock.

It is not a compositor. macOS still draws every window. Windows glide to their
tiles by being moved there, frame by frame, and a column scrolled out of view
hangs off the display edge, since nothing can clip it.

Status: new. Splay is built for macOS 15 or later and developed on macOS 27.

> **Private APIs.** macOS has no public way to switch Spaces quickly or move a
> window between them, so Splay, like Dinky, uses a synthetic Dock swipe and a
> few private SkyLight calls. A macOS update can break them. Splay also looks
> up one private libsystem function to tell which app's Accessibility grant
> counts.

## Requirements

- The build targets macOS 15 or later, on Apple silicon or Intel. Splay has
  been built, unit-tested and run on macOS 27 only. macOS 15 to 26 and Intel Macs,
  which run macOS up to 26, are untested.
- To build the app, Xcode 26 or later, which itself needs macOS 15.6, because
  Xcode's `actool` compiles the app icon. The Command Line Tools of the same
  version build and test the code, but cannot bundle it. If
  `xcode-select -p` prints the Command Line Tools, run `bundle.sh` with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` set.
- Accessibility permission. The first run asks.

## Install

Download [Splay.app.zip](https://github.com/shawntz/splay/releases/latest/download/Splay.app.zip),
unzip it and drag Splay to Applications. Releases are signed and notarized, and
run on Apple silicon and Intel. Splay offers each new version in the app, and
Check for Updates is in its menu. When Splay finds a new version on its own, it
shows `↑` after the workspace number and adds Update to Splay, with the version,
above Check for Updates. Choose it to see the update.

To use the `splay` command, link it onto your `PATH`:

```sh
mkdir -p ~/.local/bin
ln -sf /Applications/Splay.app/Contents/MacOS/splay ~/.local/bin/splay
```

If you ran a source build before, macOS still holds the Accessibility grant for
that build's signature. Remove Splay from System Settings > Privacy & Security >
Accessibility, or run `tccutil reset Accessibility com.shawnschwartz.splay`,
then turn on the release.

## Build from source

Or build Splay from a checkout. A build has no update feed, so it never offers
to replace itself with a release. To update a build, quit Splay, build again
and open it. A rebuild alone leaves the old one running, and `open` only
brings that one forward.

```sh
scripts/bundle.sh                # build/Splay.app, a release build for this Mac
scripts/bundle.sh --debug        # a debug build
UNIVERSAL=1 scripts/bundle.sh    # one app for Apple silicon and Intel
open build/Splay.app
```

`splay version` prints the version, which is `0.0` for a build from source,
and the build number, the number of commits in the checkout.
Link the command line into `~/.local/bin`:

```sh
mkdir -p ~/.local/bin
ln -sf "$PWD/build/Splay.app/Contents/MacOS/splay" ~/.local/bin/splay
```

If `~/.local/bin` is not on your `PATH`, add
`export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc`.

With [`just`](https://github.com/casey/just), `just install` builds the release
app and makes that link, and `just run` stops a running Splay, builds a debug
app and runs it attached to the terminal, with its log there. Ctrl-C or closing
that terminal quits it and puts the windows back. This manual is `docs/` in the
source, published at https://shawntz.github.io/splay/. `just docs` serves it at
http://127.0.0.1:4000/splay/, on this Mac only, once Jekyll is installed
(`gem install jekyll jekyll-relative-links`).

### Signing

macOS ties the Accessibility grant to the app's signature, so sign with a
stable identity, or every rebuild loses the grant. `bundle.sh` signs with the
first Apple Development certificate in your keychain. A free Apple account
signed in to Xcode can create one under Xcode > Settings > Accounts > Manage
Certificates. To pick another, set `IDENTITY` to a name or hash from
`security find-identity -v -p codesigning`; `IDENTITY=-` signs ad hoc. With no
certificate it signs ad hoc and warns, and its last line says how it signed.

After an ad hoc rebuild, remove Splay from the Accessibility list and add it
again.

### Accessibility

Splay moves windows and reads keys through Accessibility. Until it has the
grant, a window says so and waits. Open Accessibility Settings goes to System
Settings > Privacy & Security > Accessibility, where you turn Splay on, adding
`/Applications/Splay.app`, or `build/Splay.app` for a build, with + if it isn't
listed. The window moves on by itself
once Splay is allowed. Nothing is tiled before then, and Splay has no menu
bar item yet, so closing the window quits it.

macOS holds an app started from a terminal to the terminal's grant, not its
own. So for `just run`, or the executable typed at a prompt, it is the terminal
you turn on in that list, and the window says so.

## First run

Splay writes `~/.config/splay/splay.toml`, asks for Accessibility, and offers
once to turn off "When switching to an application, switch to a Space with
open windows" (Desktop & Dock > Mission Control). With that off, Cmd-Tab and
Dock clicks switch Spaces the fast way instead of sliding while Splay is running
and enabled. Saying no is fine. This is a persistent macOS preference: quitting
or disabling Splay does not turn it back on. If activating an app with Quicksilver,
Cmd-Tab or the Dock shows only its menu bar instead of switching to its Space,
turn the setting back on in System Settings > Desktop & Dock > Mission Control.

Once it has Accessibility, Splay tiles straight away, without asking. Every
window already open on the Spaces on screen goes into the strip, left to right
as it stands, after Splay has noted where each was so it can put it back. It
also makes the Spaces match `workspaces`, 5 unless set: it creates the missing
ones on the main display and removes empty ones left over. Splay adds no login
item unless you set `start-at-login = true`.

The menu bar shows the current workspace. Its menu has the everyday commands
(workspaces, focus, move, join, resize, layout, displays and modes, and the
strip's own), each with the key bound to it in the current mode, and lists the
bindings it doesn't cover under Other Key Bindings. `splay doctor` checks the
config and the macOS settings Splay depends on.

Turn off "Automatically rearrange Spaces based on most recent use" in the same
place, or workspace numbers move around; `splay doctor` warns while it's on.

Run one tiling window manager at a time. With AeroSpace, Amethyst, yabai,
KiwiDesk or Dinky also running, each undoes the other's layouts; Splay shows a
`!` in the menu bar and says which one to quit.

## Keys

The default bindings, all spelled out in the config:

<div class="wide-table" markdown="1">

| Keys | |
|---|---|
| Cmd-Left, Cmd-Right | Focus the column to the left or right. |
| Cmd-Home, Cmd-End | Focus the first or last column. |
| Alt-J, Alt-K | Focus the window below or above in a column. |
| Alt-Shift-H, Alt-Shift-J, Alt-Shift-K, Alt-Shift-L | Move the window left, down, up, right. |
| Alt-R, Alt-Shift-R | Give the column the next or previous preset width. |
| Alt-C | Centre the column. |
| Alt-M | Maximize the column, or give it back its width. |
| Alt-Minus, Alt-Equal | Make the column 50 points narrower or wider. |
| Alt-F | Fullscreen. |
| Alt-Shift-F | Float the window, or tile it again. |
| Alt-Comma, Alt-Slash | Show the column, or in a tree the container, as an accordion or as tiles. |
| Ctrl-Left, Ctrl-Right | The previous or next workspace. |
| Alt-1 to Alt-9 | Go to a workspace. |
| Alt-Shift-1 to Alt-Shift-9 | Move the window to a workspace. |
| Alt-Tab | Back to the workspace before. |
| Alt-Shift-N | Move the window to the next display. |
| Alt-Shift-Semicolon | Service mode: Esc reloads the config, R flattens the workspace, Alt-Shift-H, J, K and L join the window with its neighbour. Each goes back to main. |

</div>

A bound key never reaches the app in front, whether or not its window is
tiled. So Cmd-Left and Cmd-Right no longer move to the start and end of a line
in text fields; Ctrl-A and Ctrl-E still do. Browsers lose them for Back and
Forward, which Cmd-[ and Cmd-] still do. To give an app its keys back, list its
bundle ID in the binding's `exclude-apps`, and Splay leaves the key to it
while it is in front:

```toml
[mode.main]
cmd-left = { command = 'focus left', exclude-apps = ['com.apple.Terminal'] }
cmd-right = { command = 'focus right', exclude-apps = ['com.apple.Terminal'] }
```

`splay list-windows --all --format '%{app-name} %{app-bundle-id}'` prints the
bundle IDs. Cmd-Home and Cmd-End are Cmd-Fn-Left and Cmd-Fn-Right on a keyboard
without Home and End. The default Alt bindings take over Option-letter
characters; [`[modifiers]`](configuration.md#modifiers) can leave right Option
for typing them.

Dinky also puts `focus left` and `focus right` on Alt-H and Alt-L. Splay
leaves those two unbound, because Cmd-Left and Cmd-Right do that job. Option-H
and Option-L then still reach apps and tools such as Hammerspoon. To have them
back, add two lines to the `[mode.main]` your `splay.toml` already has:

```toml
alt-h = 'focus left'
alt-l = 'focus right'
```

Don't start a second `[mode.main]` for them. A table named twice is a parse
error, which the menu and `splay doctor` report.

### Magnet and Rectangle

To snap a window with Magnet or Rectangle, first float it with
`splay layout floating`, or disable Splay with `splay enable off` before snapping.
Splay keeps tiled windows in their layout, including after another app moves or
resizes them; a snapping command does not automatically float a window. Snapping
tools are not included in the warning about other tiling window managers.
Use `splay layout tiling` to tile the window again, or `splay enable on` to resume
tiling after disabling Splay. For a workspace-filling window managed by Splay,
use [`splay fullscreen`](commands.md) instead.

## Next to Dinky

Run Splay or Dinky, not both. They tile the same windows and undo each
other's layouts, and Splay counts a running Dinky as another tiling window
manager: it shows the `!` and `splay doctor` warns. Before starting Splay,
quit Dinky from its menu, which puts its windows back, and turn off its login
item in System Settings > General > Login Items & Extensions if it has one.

The two share no config, socket, log, journal, preferences or login item:
Splay keeps its own under the name `splay` and the bundle ID
`com.shawnschwartz.splay`, so either can be removed without touching the other.

To bring your Dinky settings along, start from the `splay.toml` Splay writes
and copy your changes into it. Don't copy Dinky's file over it. Bindings come
only from the file, and Dinky's has none of the strip's, so Cmd-Left and
Cmd-Right would go to apps as before, and `splay doctor` would not complain,
because the file is valid. Dinky's file also says `default-layout = 'tiles'` and
`start-at-login = true`, and its first line points editors at Dinky's schema,
which does not know the strip's keys. Rename hook variables as
[Scripting](commands.md#sketchybar) says. The macOS settings above are shared:
if Dinky turned the Space switching off, it stays off and Splay doesn't ask.

## Quit and restore

Quit Splay from its menu, `kill` it, log out, or close the terminal of an
attached run such as `just run`, and every window goes back to the frame and
Space it had before Splay tiled it. `splay enable off`, or Enabled in the
menu, does the same and keeps Splay running with tiling, borders and key
bindings off; `splay enable on` tiles again. A crash, `kill -9` or Force Quit
puts nothing back. For those, see [Recovery](commands.md#recovery).

Quitting puts back windows, not the rest. The Spaces Splay created stay, the
macOS Space switching stays as you left it, and apps whose Enhanced UI
Splay turned off, so their windows don't animate against it, keep it off.

## Back out

1. If `start-at-login = true`, set it to `false` and save while Splay runs,
   or turn Splay off in System Settings > General > Login Items & Extensions.
2. Quit Splay from its menu. Every window goes back. Before it has
   Accessibility it has no menu, so close its window, which quits it.
3. Delete `/Applications/Splay.app` or `build/Splay.app`, and `~/.local/bin/splay`.
4. Delete `~/.config/splay`, `~/Library/Application Support/splay`,
   `~/Library/Caches/com.shawnschwartz.splay` and `~/Library/Logs/splay.log`,
   and run `defaults delete com.shawnschwartz.splay`.
5. Remove Splay from System Settings > Privacy & Security > Accessibility, or
   run `tccutil reset Accessibility com.shawnschwartz.splay`. If you turned
   your terminal on there for `just run`, turn it off too.
6. Remove the Spaces you don't want in Mission Control.
7. To get the Cmd-Tab slide back:

   ```sh
   defaults write com.apple.dock workspaces-auto-swoosh -bool true && killall Dock
   ```

Dinky, if you use it, can start again once Splay has quit.

## Known limits

- Dinky has been tested properly on only one display, and Splay's changes
  consider only one. Switching a display the pointer is not on may flicker the
  pointer.
- Splay creates and removes Spaces to keep one per workspace, but leaves a
  leftover Space with windows alone.
- Apps refuse some sizes (Safari's minimum width, Terminal's grid). Splay lays
  out around them, but tiles can overlap or leave gaps. A window has a minimum
  size once it comes back at the same size for two different sizes asked, so
  the first window of an app may overlap its neighbour until its tile changes
  size. Splay remembers each app's minimum size; Clear Saved Minimum Sizes in
  the menu forgets them.
- macOS cannot focus a window on another Space, so Splay switches first.
- The order of a strip is not saved. Quitting puts the windows back, and the
  next start lines them up left to right as they then stand. Columns parked off
  an edge share that edge, so after a crash, or when a hidden app comes back,
  those can come back in another order.

## Credits

- [Dinky](https://github.com/mikker/Dinky) (MIT) by Mikkel Malmberg: Splay is
  a fork of it.
- [niri](https://github.com/niri-wm/niri) and
  [Hyprland](https://github.com/hyprwm/Hyprland): Dinky's scrolling and master
  layouts follow their design. Splay's column commands and `[scrolling]` keys
  follow niri's behaviour, and some take its names. Neither project's code is
  used.
- [PaperWM](https://github.com/paperwm/PaperWM): the scrolling tiling that niri
  follows.
- [yabai](https://github.com/asmvik/yabai) (MIT): SkyLight signatures, window
  filtering, focus and event handling. SIP-on paths only.
- [mimi](https://github.com/y3owk1n/mimi) (MIT): the fast Dock swipe and the
  SkyLight symbol lookup.
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) (MIT): key syntax,
  commands and the accordion.
- [JankyBorders](https://github.com/FelixKratz/JankyBorders) (GPL-3.0): borders,
  studied only.
- [Tuna](https://tunaformac.com): an earlier Dock swipe.
- [bobrwm](https://github.com/bobrwm/bobrwm) (MIT): creating Spaces.

MIT licensed, like Dinky.
