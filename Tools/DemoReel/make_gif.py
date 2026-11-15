#!/usr/bin/env python3
"""Encodes a folder of RGBA PNG frames (00000.png, 00001.png, ...) as a looping GIF.

One palette for the whole clip, built from all of it, with any colours listed in --keep held exactly, and every
pixel mapped to its nearest entry without dithering. Pixels outside the rounded frame are transparent. Each frame after the first stores only the rectangle that changed, with the pixels inside it that
did not change left transparent, so a still stretch costs almost nothing. Identical frames are merged into one
longer frame. Pillow picks the palette and does the LZW compression; this file maps the colours and writes the GIF around them.

Usage: make_gif.py FRAMES_DIR OUT.gif [--fps 25] [--keep COLOURS.txt]
Needs python3 with Pillow and numpy.
"""

import argparse
import io
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image, features

TRANSPARENT = 255  # palette index kept for transparency; the clip gets the other 255


def load(path):
    return np.asarray(Image.open(path).convert("RGBA"))


def build_palette(files, keep):
    """255 colours: `keep` exactly, the rest chosen from every frame's opaque pixels, weighted by how often each
    colour shows."""
    all_values, all_counts = [], []
    for path in files:
        rgba = load(path)
        rgb = rgba[..., :3][rgba[..., 3] >= 128]
        packed = (rgb[:, 0].astype(np.uint32) << 16) | (rgb[:, 1].astype(np.uint32) << 8) | rgb[:, 2]
        values, n = np.unique(packed, return_counts=True)
        all_values.append(values)
        all_counts.append(n)
    colours, inverse = np.unique(np.concatenate(all_values), return_inverse=True)
    weights = np.bincount(inverse, weights=np.concatenate(all_counts).astype(np.float64))
    if len(colours) <= 255:
        chosen = np.unique(np.concatenate([colours, keep]))[:255]
    else:
        # A sample image where each colour appears in proportion to its use (at least once), so the quantizer sees
        # the clip's real distribution without holding every frame in memory.
        reps = np.maximum(1, np.round(weights / weights.sum() * 4_000_000)).astype(np.int64)
        sample = np.repeat(colours, reps)
        rgb = np.stack([(sample >> 16) & 255, (sample >> 8) & 255, sample & 255], axis=-1).astype(np.uint8)
        width = 2000
        rows = -(-len(rgb) // width)
        pad = rows * width - len(rgb)
        rgb = np.concatenate([rgb, np.repeat(rgb[-1:], pad, axis=0)])
        image = Image.fromarray(rgb.reshape(rows, width, 3), "RGB")
        method = Image.Quantize.LIBIMAGEQUANT if features.check("libimagequant") else Image.Quantize.MEDIANCUT
        quantized = image.quantize(colors=255 - len(keep), method=method, dither=Image.Dither.NONE)
        pal = np.array(quantized.getpalette()[: (255 - len(keep)) * 3], dtype=np.uint8).reshape(-1, 3)
        picked = (pal[:, 0].astype(np.uint32) << 16) | (pal[:, 1].astype(np.uint32) << 8) | pal[:, 2]
        chosen = np.unique(np.concatenate([keep, picked]))
    palette = np.zeros((256, 3), dtype=np.uint8)
    rgb = np.stack([(chosen >> 16) & 255, (chosen >> 8) & 255, chosen & 255], axis=-1).astype(np.uint8)
    palette[: len(rgb)] = rgb
    # Unused entries, the transparent one included, get a colour nothing will be matched to.
    palette[len(rgb):] = (255, 0, 255)

    # Every colour of the clip mapped to its nearest palette entry, exactly (Pillow's own mapping works on a
    # coarser grid, which merges colours a couple of levels apart and makes soft light band).
    entries = palette[: len(rgb)].astype(np.int32)
    nearest = np.empty(len(colours), dtype=np.uint8)
    channels = np.stack([(colours >> 16) & 255, (colours >> 8) & 255, colours & 255], axis=-1).astype(np.int32)
    for start in range(0, len(colours), 4096):
        block = channels[start: start + 4096]
        distance = ((block[:, None, :] - entries[None, :, :]) ** 2).sum(axis=-1)
        nearest[start: start + 4096] = distance.argmin(axis=1)
    return palette, len(rgb), (colours, nearest)


def quantize(rgba, lookup):
    """Palette indices for a frame, without dithering; transparent where the frame is."""
    colours, nearest = lookup
    rgb = rgba[..., :3]
    packed = (rgb[..., 0].astype(np.uint32) << 16) | (rgb[..., 1].astype(np.uint32) << 8) | rgb[..., 2]
    indices = nearest[np.clip(np.searchsorted(colours, packed), 0, len(colours) - 1)]
    indices[rgba[..., 3] < 128] = TRANSPARENT
    return indices


def lzw(indices, palette):
    """The LZW-compressed image data block for `indices`, as Pillow writes it: code size, sub-blocks, terminator."""
    image = Image.fromarray(indices, "P")
    image.putpalette(palette.flatten().tolist())
    buffer = io.BytesIO()
    image.save(buffer, format="GIF", optimize=False, interlace=False)
    data = buffer.getvalue()
    pos = 13
    flags = data[10]
    if flags & 0x80:
        pos += 3 * (2 ** ((flags & 7) + 1))
    while True:
        tag = data[pos]
        if tag == 0x21:  # an extension: skip its sub-blocks
            pos += 2
            while data[pos]:
                pos += data[pos] + 1
            pos += 1
        elif tag == 0x2C:
            local = data[pos + 9]
            pos += 10
            if local & 0x80:
                pos += 3 * (2 ** ((local & 7) + 1))
            start = pos
            pos += 1
            while data[pos]:
                pos += data[pos] + 1
            return data[start: pos + 1]
        else:
            raise ValueError("unexpected GIF block %r" % tag)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("frames")
    parser.add_argument("out")
    parser.add_argument("--fps", type=int, default=25)
    parser.add_argument("--keep", help="a file of colours, one rrggbb a line, that the palette must hold exactly")
    args = parser.parse_args()
    keep = np.array([], dtype=np.uint32)
    if args.keep:
        lines = [l.strip() for l in Path(args.keep).read_text().split() if l.strip()]
        keep = np.unique(np.array([int(l, 16) for l in lines], dtype=np.uint32))

    files = sorted(Path(args.frames).glob("*.png"))
    if not files:
        sys.exit("make_gif.py: no frames in %s" % args.frames)
    delay = round(100 / args.fps)
    if abs(delay - 100 / args.fps) > 1e-9:
        sys.exit("make_gif.py: %d fps is not a whole number of hundredths of a second" % args.fps)

    palette, used, lookup = build_palette(files, keep)

    height, width = load(files[0]).shape[:2]
    frames = []  # (left, top, indices, delay)
    previous = None
    for path in files:
        current = quantize(load(path), lookup)
        if previous is None:
            frames.append([0, 0, current, delay])
        else:
            changed = current != previous
            if not changed.any():
                frames[-1][3] += delay
                continue
            ys, xs = np.nonzero(changed)
            top, bottom, left, right = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
            patch = current[top:bottom, left:right].copy()
            patch[~changed[top:bottom, left:right]] = TRANSPARENT
            frames.append([int(left), int(top), patch, delay])
        previous = current

    out = bytearray(b"GIF89a")
    out += struct.pack("<HHBBB", width, height, 0xF7, 0, 0)
    out += palette.tobytes()
    out += b"\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00"  # loop for ever
    for left, top, patch, frame_delay in frames:
        # Graphic control: leave the frame in place for the next one, with the transparent index.
        out += struct.pack("<BBBBHBB", 0x21, 0xF9, 4, (1 << 2) | 1, frame_delay, TRANSPARENT, 0)
        h, w = patch.shape
        out += struct.pack("<BHHHHB", 0x2C, left, top, w, h, 0)
        out += lzw(np.ascontiguousarray(patch), palette)
    out += b"\x3B"
    Path(args.out).write_bytes(bytes(out))
    print("  %s: %d frames stored of %d, %d colours, %.2f MB, %.2f s"
          % (Path(args.out).name, len(frames), len(files), used, len(out) / 1e6, len(files) * delay / 100))


if __name__ == "__main__":
    main()
