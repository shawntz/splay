---
layout: default
title: Layouts
description: Workspace layouts place windows, layout modes show them. Scrolling, the default, then dwindle, fixed and master; tiles and accordion.
permalink: /layouts/
---

<p class="github-only">This page is part of Splay's manual. Read it with its figures and navigation at
https://shawntz.github.io/splay/layouts/.</p>

# Layouts

Two knobs, on two levels.

- A **workspace layout** decides where a new window goes: `scrolling`, the
  default, `dwindle`, `fixed` or `master`. One per workspace, from the config
  or `workspace-layout`.
- A **layout mode** decides how one container shows its windows: `tiles` side
  by side, or an `accordion`. One per container, from `layout`.

## Scrolling

The default. A workspace is one row of columns, wider than the display, after
niri. A new window opens as a column right of the focused one, `column-width`
wide whatever the number of columns. A lone column fills the display, and
columns that all fit are centred. Windows already open when Splay starts go in
left to right as they stand.

<figure class="wide">
{% include figures/scrolling.svg %}
<figcaption>Columns 2 and 3 in view. macOS can't clip a window, so 1 and 4 hang off the edges with a sliver left on.</figcaption>
</figure>

### The sliver

macOS can't clip another app's window, so a column out of view is parked: it
hangs off the display edge with `peek` points of it left on, 25 unless set, an
inner gap from the columns in view. Focus following the mouse leaves it alone;
a click on it scrolls to its column. Where another display sits beyond that
edge, the column stops at the border instead and waits behind the columns in
view, so it never shows on the other display.

### Moving along it

`focus left` and `right` go from column to column, landing on the window last
focused in the column. They are on Alt-Cmd-Left and Alt-Cmd-Right, and on Alt-H
and Alt-L. Alt is the Option key and Cmd is the Command key. `up` and `down`,
on Alt-K and Alt-J, go within one. Focusing a column scrolls just far enough to
show it whole. `focus-column first` and `last`, on Alt-Cmd-Home and
Alt-Cmd-End, jump to the ends.

`move left` and `right` swap the column with its neighbour, or take a window
that shares its column out into a new one. `join-with left` and `right` put the
window into the column beside it. A column closing or changing width leaves the
focused one where it is on screen, as far as the ends of the strip let it.

### Centring

`center-column`, on Alt-C, centres the focused column and keeps it centred
while focus stays in it, through resizes, other columns closing, and display or
gap changes. Focusing another column ends it.

`center-focused-column` centres as focus moves instead: `'always'` every
column, so the first and last can leave empty space beside them, or
`'on-overflow'` only a column that would not fit in view beside its neighbour
on the side focus came from.

### Widths

A width is a share of the display. `column-width next` and `prev`, on Alt-R and
Alt-Shift-R, step the focused column through `preset-column-widths`, a third, a
half and two thirds unless set, and wrap at the ends. `column-width 0.75` sets a
share outright. `maximize-column`, on Alt-M, widens the column to the whole
display, short of the slivers at its edges; again, it gives the column back its
width. `resize width` changes it
by points, and Alt-Minus and Alt-Equal do so 50 at a time through
`resize smart`.

```toml
[scrolling]
column-width = 0.49             # a new column's share of the display
center-focused-column = 'never' # never | always | on-overflow
preset-column-widths = [0.33333, 0.5, 0.66667]
peek = 25                       # points of a parked window left on screen
```

## Dwindle

Dinky's default. A new window splits the focused tile along its longer side.
Close it and the space goes back.

<figure class="steps">
{% include figures/dwindle-1.svg %}
{% include figures/dwindle-2.svg %}
{% include figures/dwindle-3.svg %}
{% include figures/dwindle-4.svg %}
<figcaption>Four windows open, one after the other. <code>tiles</code> is another name for it.</figcaption>
</figure>

```toml
default-layout = 'tiles'        # every workspace, as in Dinky
```

## Fixed

A grid, reserved from the start. New windows fill holes left to right, top to
bottom. An empty cell stays empty.

<figure>
{% include figures/fixed.svg %}
{% include figures/fixed-expand.svg %}
<figcaption>Four windows in a 2 by 3 grid. The grid is full, so a seventh window adds a column.</figcaption>
</figure>

When every cell is taken, `expand` adds a column, a row, or an accordion in the
last cell.

```toml
[workspace.2]
layout = 'fixed'
columns = 2
rows = 3
expand = 'columns'    # columns | rows | accordion
```

## Master

One window, the master, takes `size` of the display on `side`. The others
stack beside it, after Hyprland. The first window fills the display alone;
when the master closes, the top of the stack takes its place.

<figure>
{% include figures/master.svg %}
{% include figures/master-accordion.svg %}
<figcaption>A stack of tiles, and the same stack after <code>layout accordion</code>.</figcaption>
</figure>

`swap-with-master` trades places with the master. `resize width` changes the
master's share.

On a wide display, `side = 'center'` puts the master in the middle once two
windows are stacked, and new windows alternate between a stack on its right and
one on its left. Closing windows rebalances the stacks, keeping any extra window
on the right so flattening or switching sides and back keeps their arrangement.

<figure>
{% include figures/master-center.svg %}
<figcaption>A centred master with three windows stacked.</figcaption>
</figure>

```toml
[workspace.3]
layout = 'master'

[master]
size = 0.6
side = 'left'
```

## Tiles and accordion

The two layout modes. Tiles share the container. An accordion gives it to the
focused window, with the others peeking out by up to `padding` points on each side.
Peeks shrink in narrow containers to leave usable content and respect recorded
window minima. Focus a neighbour and it comes to the front.

<figure>
{% include figures/tiles.svg %}
{% include figures/accordion-h.svg %}
{% include figures/accordion-v.svg %}
<figcaption>The same three windows as tiles, as an accordion, and as a vertical one.</figcaption>
</figure>

A container also has an axis: `horizontal`, `vertical`, or `auto`, the longer
side of its rectangle. `layout vertical` turns it.

## Switching

<div class="wide-table" markdown="1">

| Command | Changes | Of |
|---|---|---|
| `layout tiles\|accordion` | the mode | the focused window's container. In master the stack, in scrolling the column. |
| `layout horizontal\|vertical\|auto` | the axis | the same container. |
| `layout floating\|tiling` | tiled or not | the focused window. |
| `workspace-layout dwindle\|master\|scrolling` | the workspace layout | the focused window's workspace, until the next switch. `dwindle` is the tree the config gives it, or tiles where the config gives scrolling or master. `fixed` comes from the config only. |
| `flatten-workspace-tree` | everything, back to the config | the workspace. |

</div>

Given several names, `layout` and `workspace-layout` apply the one after the
current, so `layout tiles accordion` and `workspace-layout dwindle scrolling`
toggle. The keys, defaults and edge cases are in
[Configuration](configuration.md) and [Commands](commands.md).
