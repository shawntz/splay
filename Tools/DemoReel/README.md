# DemoReel

Renders the animations in `docs/assets/demo` from Splay's layout engine. Each clip sets up workspaces with the shipped config (`Config.default`), presses keys bound in it, and runs the commands they are bound to through the engine, the way the app's coordinator does. Windows glide to the frames the engine computes on the app's own spring, and their borders are drawn as the app draws them. The desktop and the windows are placeholders on a mock 1512 x 982 point display. No clip is a screen recording.

Regenerate every clip, each as a GIF, an MP4 and a poster:

```sh
cd Tools/DemoReel
swift run demoreel
```

`swift run demoreel strip` renders one clip. `swift run demoreel --stills DIR 0 2.5` writes PNG frames at those times and nothing else.

- It builds in debug only: it reads engine internals through `@testable import`.
- The GIFs are encoded by `make_gif.py`, which needs python3 with Pillow and numpy.
- It is a package of its own, so the app's `swift build` never compiles it.

| Clip | Shows |
| --- | --- |
| `strip` | New windows open as columns beside the focused one. Alt-Left, Alt-Right, Alt-Home and Alt-End walk the strip. |
| `widths` | Alt-R and Alt-Shift-R step through the preset widths, Alt-M maximizes and restores, Alt-C centres. |
| `versus` | The same five windows under Dinky's default layout (tiles) and Splay's (the strip). |
| `workspaces` | Ctrl-Left and Ctrl-Right switch workspace, Alt-Shift-2 and Alt-Shift-1 send a window across. |

Not from the engine: where an app first puts a new window, the fades as windows open and close, the 120 ms slide between Spaces (macOS draws that; on macOS 27 Splay's switch skips it), the minimap and the key overlay.
