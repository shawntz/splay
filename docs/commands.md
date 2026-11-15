---
layout: default
title: Commands
description: Splay commands, the command line and socket, and scripting a bar.
permalink: /commands/
---

<p class="github-only">This page is part of Splay's manual. Read it with its figures and navigation at
https://shawntz.github.io/splay/commands/.</p>

# Commands

Key bindings, `splay <command>` and the menu share one vocabulary. `splay help`
prints it.

<div class="wide-table" markdown="1">

| Command | |
|---|---|
| `workspace <n\|prev\|next>` | Show a workspace and focus its display. `prev`/`next` step through the focused display's and don't wrap. |
| `workspace-back-and-forth` | Switch to the previous workspace. |
| `move-window-to-workspace <n\|prev\|next> [--follow] [--window-id <id>]` | Move the focused window or the window with the given ID. With `--follow`, switch to the destination. |
| `move-window-to-display <next\|prev> [--follow] [--window-id <id>]` | Move the focused or selected window to another display's workspace. |
| `focus <left\|down\|up\|right> [--boundaries <b>] [--boundaries-action <a>]` | Focus the nearest window. `--boundaries` is `workspace` (default) or `all-monitors-outer-frame`, which continues onto the next display. `--boundaries-action` is `stop` (default), `fail`, `wrap-around-the-workspace` (`--wrap-around`) or `wrap-around-all-monitors`, which needs `all-monitors-outer-frame`. |
| `focus-monitor <left\|down\|up\|right\|next\|prev\|n>` | Focus a display. |
| `move <left\|down\|up\|right>` | Move the focused window in the tree. |
| `join-with <left\|down\|up\|right>` | Put the focused window and its neighbour in a new container. |
| `resize <smart\|width\|height> <+n\|-n>` | Resize by n points. |
| `layout <tiles\|accordion\|horizontal\|vertical\|auto\|h_tiles\|v_tiles\|h_accordion\|v_accordion\|floating\|tiling>... [--window-id <id>]` | Set the layout of the focused or selected window's container, or float/tile the window. In a [master layout](configuration.md#master) the container is the stack, in a [scrolling layout](configuration.md#scrolling) the window's column. Given several, applies the one after the current one, so `layout floating tiling` and `layout tiles accordion` toggle. Tiles the window first if it floats, so it does nothing on an empty workspace without an ID. |
| `workspace-layout <dwindle\|master\|scrolling>... [--window-id <id>]` | Switch the focused or selected window's workspace to its tree (`dwindle`: the tree its config gives it, or tiles when the config gives scrolling or master), to [master](configuration.md#master) with that window as the master, or to [scrolling](configuration.md#scrolling). The switch holds until the next. Given several, applies the one after the current one, so `workspace-layout dwindle master` toggles and `workspace-layout dwindle master scrolling` cycles. |
| `fullscreen` | Toggle filling the workspace (not macOS full screen). [`fullscreen-width`](configuration.md#top-level) narrows and centres it. |
| `flatten-workspace-tree` | Put every window back into the workspace's layout, in order, undoing tree edits. A scrolling workspace keeps its column widths. |
| `balance-sizes` | Give every window an equal share. |
| `swap-with-master` | In a [master layout](configuration.md#master), swap the focused window with the master, or the master with the top of the stack. |
| `retile` | Re-read windows and re-apply every layout. |
| `clear-minimum-sizes` | Forget the minimum window sizes learned for every app and re-apply every layout. |
| `mode <name>` | Switch binding mode. |
| `reload-config` | Reload the config. |
| `enable <on\|off\|toggle>` | Turn Splay on or off. Off restores windows, takes their borders away and turns key bindings off too, so turn it back on from the menu or with `splay enable on`. While off, Splay leaves new windows, `[[rules]]`, Spaces and workspaces alone; turning it on tiles what opened meanwhile, where it is. |
| `list-workspaces`, `list-windows`, `list-monitors`, `list-displays`, `list-modes` | See [Scripting](#scripting). `list-displays` = `list-monitors`. |
| `debug-state` | Tiling state as JSON, for bug reports. Each tree's `layout` is its workspace layout, as `%{workspace-layout}` prints it. |
| `exec-and-forget <shell command>` | Run with `/bin/sh -c` without waiting. Output goes to the log. |
| `center-column` | In a [scrolling layout](configuration.md#scrolling), centre the focused column on the display and keep it centred while it has focus. `center-focused-column` centres columns as focus reaches them. |
| `column-width <next\|prev\|share>` | In a scrolling layout, give the focused column the next wider of `preset-column-widths`, wrapping to the narrowest, or with `prev` the next narrower; or a share of the display from 0.1 to 1, such as `column-width 0.75`. |
| `maximize-column` | In a scrolling layout, widen the focused column to the whole display; again, give it back its width. |
| `focus-column <first\|last>` | In a scrolling layout, focus the first or last column, at the window last focused in it. |

</div>

Workspaces are numbered across displays; see
[`[workspace-to-display]`](configuration.md#workspace-to-display). A full-screen
app's Space has no number, nor does the Space of a display without workspaces.

### Targeting a window

`move-window-to-workspace`, `move-window-to-display`, `layout` and
`workspace-layout` accept `--window-id <id>` before or after their other arguments.
Without it, they act on the focused window (or the new window in a rule, as
[the strip's commands](#the-strip) do there too).
Find IDs with `splay list-windows --all`. Only managed windows on numbered
workspaces can be targeted: tiled and floating windows, not minimized, hidden,
native full-screen, system or border windows. A stale or ineligible ID is an error.
Layout commands change the selected window's container or workspace without
switching Spaces or focusing it.

With an explicit ID, `move-window-to-workspace prev` and `next` step from the
window's workspace, on its display, without wrapping. Without an ID, they step
from the focused display's current or pending workspace, as `workspace` does.
Display moves always step from the window's display.

Moving without `--follow` keeps focus where you are. Bringing a window to the
current workspace does not focus it. Use `--follow` to show its destination and
focus it, including when it is already there:

```sh
splay move-window-to-workspace 3 --window-id 12345 --follow
```

### The strip

`center-column`, `column-width`, `maximize-column` and `focus-column` work on
the focused window's column in a [scrolling layout](layouts.md#scrolling). In
any other layout they succeed with `<name>: nothing to do`, as they do when
nothing would change: a lone column already fills the display, and a column
can be centred or at the end already. With no tiled window focused they fail
with `<name>: the focused window is not tiled`.

- `center-column` keeps the column centred while focus stays in it, through
  resizes and other columns closing. Focusing another column ends it.
- `column-width next` and `prev` pass over a preset that would change nothing
  on screen, as when a window's minimum size holds the column wider. With
  `preset-column-widths = []` they do nothing.
- `column-width` takes a share as a plain decimal. Outside 0.1 to 1 the command
  line refuses it before sending anything:
  `can't parse 'column-width 1.5': a share must be 0.1 to 1`.
- `maximize-column` remembers the column's width, and run again gives it back.
  Any other width change, or the window leaving, forgets it, so the next
  `maximize-column` widens again. A tab that takes the window's place keeps it.
- The width commands end `fullscreen`, as `resize` does.
- `focus-column` gives the window keyboard focus, as `focus` does, and replies
  `focused window <id> <app>`.
- In a rule's `run`, each works on the column of the window the rule matched,
  whichever window has focus. A failure then names it: `<name>: window <id> is
  not tiled`.

Focusing another app's window takes macOS a moment, and until then it still
reports the window before it in front. So after Splay focuses a window, until
macOS reports it in front or half a second has passed, every command that acts
on the focused window starts from that one, while it stays tiled and its Space
stays on screen. Quick presses of `focus right` then walk the strip instead of
stepping from the same window twice, and a `move-window-to-workspace` pressed
right after moves the window just focused. A click on another window inside
that moment does not change where the next command starts.

## Command line

The app binary is the CLI. `splay <command>` sends a command to the running app
and exits 1 on errors or when it isn't running. A command with nothing to do
succeeds: `move left` on a window already at the left edge prints
`move left: nothing to do` and exits 0, as `workspace 1` does on workspace 1.
CLI-only commands:

| Command | |
|---|---|
| `app` | Run the app in the foreground, logging to the terminal. |
| `doctor [--config <path>]` | Check the config and macOS settings, and that no other tiling window manager is running. |
| `recover` | Ask the running app to restore windows a crashed session left tiled. |
| `debug events\|windows` | Print window events or windows, without the app. |
| `version`, `-v`, `--version` | Print the version and build number. |

Run from the bundle the CLI is `build/Splay.app/Contents/MacOS/splay`; see
[Build from source](start.md#build-from-source) to put it on your `PATH`.

The log is `~/Library/Logs/splay.log` when Splay was started without a
terminal, as from Finder or at login; attach it to bug reports.

`debug-state` reports frames as `[x, y, width, height]`. An unavailable frame,
including a transient frame during a close or minimize, is `[]`.

Scripts can skip the CLI and talk to the socket: one command per connection,
answered with `ok` or `error` and the reply.

```sh
printf 'workspace 2\n' | nc -U "$TMPDIR/splay.sock"
```

Requests are UTF-8, up to 1 MiB, and may contain newlines. After writing the
request, close the connection's writing half (`shutdown(SHUT_WR)`) and read the
reply until EOF. The CLI and macOS `nc` do this automatically. A newline alone
does not finish a request. The app rejects an incomplete request after two seconds
without incoming data, or an oversized or invalid UTF-8 request, without running it.

The CLI also rejects replies over 1 MiB (including the status header), invalid
UTF-8 replies and transport failures rather than printing partial output. The
command may already have run when receiving its reply fails. Narrow large list
queries with filters or `--format`, or use a raw socket client for larger replies.

## Recovery

Splay journals each window's original frame and Space before tiling it, in
`~/Library/Application Support/splay/journal.json`. `enable off`, quitting,
`kill`, logging out and closing the terminal of an attached run put them all
back. A window that can't be put back
(display gone, app not answering) stays journaled and is tried again by the next
disable, quit or `splay recover`, unless you move it first.

A crash, `kill -9` or Force Quit skips all that. Start Splay again: it tiles as usual,
and its menu offers to restore the windows the crashed session left (or
`splay recover`). Restoring them turns Splay off until `splay enable on`.

While Mission Control or App Exposé is detected, automatic layout writes,
animations and restacking pause. Visible workspaces apply their pending layout
when the overview closes; hidden workspaces wait until shown. Disabling or
quitting still restores the original windows during overview.

## Scripting

The queries follow [AeroSpace](https://nikitabobko.github.io/AeroSpace/commands)'s
names, flags and output, so most AeroSpace bar scripts work by swapping the
command name.

<div class="wide-table" markdown="1">

| Query | Flags | Default format |
|---|---|---|
| `list-workspaces` | `--all`, `--focused`, `--monitor <focused\|all\|n>...`, `--visible [no]`, `--empty [no]`, `--format` | `%{workspace}` |
| `list-windows` | `--all`, `--focused`, `--monitor <focused\|all\|n>...`, `--workspace <focused\|visible\|n>...`, `--app-bundle-id <id>` (or `--app-id`), `--format` | `%{window-id}%{right-padding} \| %{app-name}%{right-padding} \| %{window-title}` |
| `list-monitors` | `--focused [no]`, `--format` | `%{monitor-id}%{right-padding} \| %{monitor-name}` |
| `list-modes` | `--current` | Mode names, `main` first |

</div>

Without a display flag, `list-workspaces` and `list-windows` cover the focused
display; `list-monitors` lists every display. `list-windows` leaves out windows
an app has hidden rather than closed, such as a settings window closed with
Cmd-W that the app keeps around. Format variables:

- `%{right-padding}`, `%{newline}`, `%{tab}`
- Workspaces: `workspace`, `workspace-is-focused`, `workspace-is-visible`,
  `workspace-layout` (`dwindle`, `fixed`, `master` or `scrolling`, empty on a
  full-screen Space), `monitor-id`, `monitor-name`, `monitor-is-main`
- Windows: `window-id`, `window-title`, `window-identifier`, `window-layout`,
  `window-parent-container-layout`, `window-is-floating`,
  `window-is-fullscreen`, `app-name`, `app-bundle-id`, `app-pid`, and the
  workspace variables

`%{window-title}` is read through Accessibility, as rules read it. A window
whose app doesn't answer, or one on a Space not shown since Splay started, lists
with an empty title.

`%{monitor-is-main}` tells a bar which workspaces are on the side display.

### SketchyBar

Drive a bar from the config's [hooks](configuration.md#hooks):

```toml
[hooks]
startup = ['exec-and-forget brew services restart sketchybar']
workspace-changing = ['exec-and-forget sketchybar --trigger workspace_changing SPLAY_DISPLAY=$SPLAY_DISPLAY SPLAY_WORKSPACE=$SPLAY_WORKSPACE']
workspace-changed = ['exec-and-forget sketchybar --trigger workspace_change WORKSPACE=$SPLAY_WORKSPACE']
focus-changed = ['exec-and-forget sketchybar --trigger focus_changed']
mode-changed = ['exec-and-forget sketchybar --trigger mode_changed MODE=$SPLAY_MODE']
```

The workspace hooks set `SPLAY_WORKSPACE` (empty on a full-screen Space),
`SPLAY_PREV_WORKSPACE` and `SPLAY_DISPLAY` (1-based). `workspace-changing`
fires only for Splay's own switches, so draw the target there and the real
state on `workspace-changed`, which always follows. `mode-changed` sets
`SPLAY_MODE` and `SPLAY_PREV_MODE`; `splay list-modes --current` prints the
mode at any time. `startup` and `focus-changed` set none. The variables reach
only commands that hooks run, not key bindings or the menu. `exec-and-forget`
has `splay` and Homebrew on `PATH`.

A bar script written for Dinky works once its hook variables start with
`SPLAY_` and its commands with `splay`.

With `follow-space-order`, renumbering can send `workspace-changed` with equal
`SPLAY_WORKSPACE` and `SPLAY_PREV_WORKSPACE`: the workspace contents changed even
though the visible number did not. Bars should still refresh on that notification.
See [hooks](configuration.md#hooks) for switch settlement and renumbering behavior.

### Docking

For a workspace's layout per display, use
[`[workspace.<number>.display.<pattern>]`](configuration.md#workspacenumberdisplaypattern).
For anything else, `display-changed` runs once the workspaces have moved after
a display connects or disconnects. It sets `SPLAY_DISPLAYS` and
`SPLAY_PREV_DISPLAYS`, the number of displays now and before;
`splay list-monitors` names them.

```toml
[hooks]
display-changed = ['exec-and-forget [ "$SPLAY_DISPLAYS" = 1 ] && ~/bin/laptop-mode.sh || ~/bin/desk-mode.sh']
```
