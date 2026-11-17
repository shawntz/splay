// The config dinky writes on first run. Apart from the rules and bindings, which it spells out, its
// values are the built-in defaults, so a key left out of a user's file means what this file says.

extension Config {
    public static let defaultTOML = """
    #:schema https://shawntz.github.io/splay/schemas/splay.json
    # ~/\(Brand.configPath). Saved changes take effect at once.
    # A key you leave out keeps the value shown here.
    # Every command: `\(Brand.name) help`. Every key: https://shawntz.github.io/splay/configuration/

    start-at-login = false          # true starts \(Brand.name) when you log in
    workspaces = 5                  # across all displays, one native Space each
    follow-space-order = false      # true renumbers workspaces when you reorder Spaces in Mission Control
    default-layout = 'scrolling'    # scrolling | tiles (dwindle) | dwindle | accordion | fixed | master
    default-tiling = true           # false leaves workspaces untiled unless overridden
    follow-app-activation = true    # Cmd-Tab and Dock clicks switch Spaces the fast way
    float-windows-without-fullscreen = true   # progress windows, About, Calculator and the like float
    fullscreen-width = 1.0          # share of the width a fullscreen window, or a window alone, takes, centred
    # lone-window-width = 0.75      # lone windows only; omitted uses the resolved fullscreen-width

    # Example: follow every app but one. Replaces the follow-app-activation line above.
    # [follow-app-activation]
    # enabled = true
    # exclude-apps = ['com.synology.SynologyDrive']   # its menu bar popover counts as a window

    # Example: only tile workspace 2 in a fixed 2x3 template.
    # Empty cells stay empty; a seventh window adds a column by default.
    # default-tiling = false
    # [workspace.2]
    # tiling = true
    # layout = 'fixed'
    # columns = 2
    # rows = 3
    # expand = 'columns'           # columns | rows | accordion (overflow in last cell)
    # [workspace.2.display.built-in]   # its settings while on the laptop screen
    # layout = 'accordion'

    [accordion]
    padding = 30                    # maximum points the neighbours peek out by
    orientation = 'auto'            # auto: run along the container's longer side | keep

    [scrolling]
    column-width = 0.49             # a new column's share of the display; a lone column fills it
    center-focused-column = 'never' # centre the focused column: never | always | on-overflow (when it won't fit beside the one before)
    preset-column-widths = [0.33333, 0.5, 0.66667]   # what column-width next and prev step through; [] for none
    peek = 25                       # points of a scrolled-out window left on screen

    [master]
    size = 0.6                      # the master's share of the display beside the stack; alone it fills it
    side = 'left'                   # left | right | center: the master's side

    [gaps]
    inner = 8                       # or { horizontal = 8, vertical = 8 }
    outer = 8                       # or { top = 8, bottom = 8, left = 8, right = 8 }

    # Display patterns: main, secondary, or part of a name as `\(Brand.name) list-displays` prints it.
    # A workspace lives on the first display its patterns match, else on the main display.
    # [workspace-to-display]
    # 5 = 'secondary'

    # Overrides for one display.
    # [display.main]
    # gaps.outer.top = 44
    # [display.'DELL U3421WE']
    # fullscreen-width = 0.55       # on an ultrawide, a fullscreen or lone window takes half the width
    # lone-window-width = 0.75      # lone windows only; omitted uses the resolved fullscreen-width

    [borders]
    enabled = true
    width = 4
    active-color = '#e1e3e4'        # '#rrggbb' or '#rrggbbaa'
    inactive-color = '#494d64'
    order = 'below'                 # below | above (a click-through ring over the window)
    exclude-apps = []               # bundle IDs whose windows get no border

    [focus-follows-mouse]
    enabled = false
    delay-ms = 100                  # how long the pointer rests on a window before it takes focus
    accordion-edges = true          # resting on a peeking accordion edge focuses that window

    [swipe]
    enabled = false                 # the Spaces swipe focuses the next window of a tiled workspace first
    space-switch = 'instant'        # instant (focus, then switch past the edge) | native (macOS also acts); native on macOS 27+
    vertical = false                # up and down too; always native, so macOS may also open an overview

    [animations]
    enabled = true                  # windows glide to their tiles; off while Reduce Motion is on
    duration-ms = 150               # roughly how long a window takes to arrive

    [drag]
    placeholders = true             # outline where a dragged tile came from and the tile it will swap with
    split-trigger = 'off'           # off | hold | alt | ctrl | cmd | shift: what makes a drop split the tile instead of swapping
    split-delay-ms = 500            # with split-trigger = 'hold', how long the pointer rests on the tile first

    # Which key of each pair bindings answer to: both | left | right. With alt = 'left',
    # right Option still types special characters.
    [modifiers]
    alt = 'both'
    ctrl = 'both'
    cmd = 'both'
    shift = 'both'

    # \(Brand.name) commands run on events. exec-and-forget gets $\(Brand.envPrefix)WORKSPACE, $\(Brand.envPrefix)PREV_WORKSPACE and $\(Brand.envPrefix)DISPLAY
    # in the workspace hooks, $\(Brand.envPrefix)MODE, $\(Brand.envPrefix)PREV_MODE in mode-changed, and $\(Brand.envPrefix)DISPLAYS,
    # $\(Brand.envPrefix)PREV_DISPLAYS (how many displays) in display-changed.
    # [hooks]
    # startup = ['exec-and-forget brew services restart sketchybar']
    # workspace-changed = ['exec-and-forget sketchybar --trigger workspace_change']
    # focus-changed = []
    # mode-changed = []
    # display-changed = []

    # Every rule whose conditions all match a new window runs, in order.
    [[rules]]
    app-id = 'com.apple.systempreferences'   # also: app-name, title (regexes), kind (normal|dialog|sheet|panel)
    run = 'layout floating'

    [mode.main]
    ctrl-left = 'workspace prev'
    ctrl-right = 'workspace next'
    alt-1 = 'workspace 1'
    alt-2 = 'workspace 2'
    alt-3 = 'workspace 3'
    alt-4 = 'workspace 4'
    alt-5 = 'workspace 5'
    alt-6 = 'workspace 6'
    alt-7 = 'workspace 7'
    alt-8 = 'workspace 8'
    alt-9 = 'workspace 9'
    alt-shift-1 = 'move-window-to-workspace 1'
    alt-shift-2 = 'move-window-to-workspace 2'
    alt-shift-3 = 'move-window-to-workspace 3'
    alt-shift-4 = 'move-window-to-workspace 4'
    alt-shift-5 = 'move-window-to-workspace 5'
    alt-shift-6 = 'move-window-to-workspace 6'
    alt-shift-7 = 'move-window-to-workspace 7'
    alt-shift-8 = 'move-window-to-workspace 8'
    alt-shift-9 = 'move-window-to-workspace 9'
    alt-tab = 'workspace-back-and-forth'
    alt-j = 'focus down'
    alt-k = 'focus up'
    alt-shift-h = 'move left'
    alt-shift-j = 'move down'
    alt-shift-k = 'move up'
    alt-shift-l = 'move right'
    alt-minus = 'resize smart -50'
    alt-equal = 'resize smart +50'
    alt-f = 'fullscreen'
    alt-shift-f = 'layout floating tiling'
    alt-comma = 'layout accordion'
    alt-slash = 'layout tiles'
    alt-shift-n = 'move-window-to-display next'
    alt-shift-semicolon = 'mode service'
    # Alt-Left and Alt-Right walk the strip, so apps no longer get them. Text fields use them to move by a word.
    # Standard macOS text fields also do that on Ctrl-Option-B and Ctrl-Option-F. To leave the keys to some
    # apps, list their bundle IDs:
    # alt-left = { command = 'focus left', exclude-apps = ['bundle.id'] }
    # To leave the right Option key to every app, set alt = 'left' under [modifiers].
    # alt-h and alt-l are left unbound, so Option-H and Option-L still reach apps and other tools.
    alt-left = 'focus left'
    alt-right = 'focus right'
    # The strip: its first and last column, the focused column's preset widths, centring and maximising it.
    alt-home = 'focus-column first'
    alt-end = 'focus-column last'
    alt-r = 'column-width next'
    alt-shift-r = 'column-width prev'
    alt-c = 'center-column'
    alt-m = 'maximize-column'

    [mode.service]
    esc = ['reload-config', 'mode main']
    r = ['flatten-workspace-tree', 'mode main']
    alt-shift-h = ['join-with left', 'mode main']
    alt-shift-j = ['join-with down', 'mode main']
    alt-shift-k = ['join-with up', 'mode main']
    alt-shift-l = ['join-with right', 'mode main']
    """
}
