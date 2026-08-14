#!/usr/bin/env python3
"""Classify sweep screenshots by what is actually on them.

PNG file size is the triage this project has always used, and it is too crude
for the FM77AV. It cannot separate three states that mean completely different
things:

  * a blank screen                      -- ~3790 bytes on the FM-7
  * the AV F-BASIC banner               -- ~5182 bytes, i.e. the disk did NOT
                                           boot and the machine fell through to
                                           BASIC. Reads as "renders something".
  * a real game frame                   -- anything from 4000 upwards

Coverage and colour count separate them properly: the banner is a handful of
white-on-black text rows, one colour, a few percent of the screen. A game frame
in 320x200 mode has many colours. A blank has none.

  classify.py <shots-dir> [results.tsv]

Prints one row per shot, and merges the instruction rates from results.tsv when
given, because a screenshot alone still cannot tell "idling at a finished
screen" from "crashed" -- see sweep.sh.
"""
import os
import struct
import sys
import zlib


def read_png(path):
    """Minimal PNG reader: 8-bit RGB/RGBA, non-interlaced, which is what
    sim_video writes. Returns (width, height, [(r,g,b), ...])."""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('not a PNG')
    pos, idat, w, h, depth, ctype = 8, b'', 0, 0, 0, 0
    while pos < len(data):
        (ln,) = struct.unpack('>I', data[pos:pos + 4])
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if typ == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', body[:10])
        elif typ == b'IDAT':
            idat += body
        elif typ == b'IEND':
            break
        pos += 12 + ln
    if depth != 8 or ctype not in (2, 6):
        raise ValueError(f'unsupported PNG depth={depth} colour={ctype}')
    nch = 3 if ctype == 2 else 4
    raw = zlib.decompress(idat)
    stride = w * nch
    out, prev = [], bytearray(stride)
    p = 0
    for _ in range(h):
        filt = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if filt == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 0xff
        elif filt == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xff
        elif filt == 3:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xff
        elif filt == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                b = prev[i]
                c = prev[i - nch] if i >= nch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xff
        out.append(bytes(line))
        prev = line
    px = []
    for line in out:
        for x in range(w):
            o = x * nch
            px.append((line[o], line[o + 1], line[o + 2]))
    return w, h, px


def classify(path):
    w, h, px = read_png(path)
    n = len(px)
    nonblack = [p for p in px if p != (0, 0, 0)]
    colours = set(nonblack)
    cover = 100.0 * len(nonblack) / n if n else 0.0
    if cover < 0.5:
        kind = 'blank'
    elif len(colours) <= 2 and cover < 12:
        kind = 'text'          # white-on-black rows: a banner or a prompt
    elif len(colours) <= 8:
        kind = 'lowcolour'
    else:
        kind = 'GRAPHICS'
    return kind, cover, len(colours)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    shots = sys.argv[1]
    rates = {}
    if len(sys.argv) > 2 and os.path.exists(sys.argv[2]):
        for ln in open(sys.argv[2]):
            f = ln.rstrip('\n').split('\t')
            if len(f) >= 6 and f[0] != 'MAIN_PF':
                rates[f[5]] = (f[0], f[1])
    rows = []
    for name in sorted(os.listdir(shots)):
        if not name.endswith('.png'):
            continue
        try:
            kind, cover, nc = classify(os.path.join(shots, name))
        except Exception as e:                       # noqa: BLE001
            print(f'{name}: {e}', file=sys.stderr)
            continue
        title = name[:-4]
        rows.append((kind, cover, nc, title))
    order = {'GRAPHICS': 0, 'lowcolour': 1, 'text': 2, 'blank': 3}
    rows.sort(key=lambda r: (order[r[0]], -r[1]))
    print(f'{"KIND":10} {"COVER%":>7} {"COLOURS":>8}  {"MAIN/f":>7} {"SUB/f":>7}  TITLE')
    for kind, cover, nc, title in rows:
        m, s = rates.get(title, ('', ''))
        # results.tsv keys on the raw title; shot names are sanitised, so fall
        # back to a loose match rather than silently printing blanks.
        if not m:
            # sweep_one.sh sanitises with tr -c 'A-Za-z0-9._-' '_', so match
            # that exactly -- keeping dot, underscore and hyphen.
            keep = set('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
                       '0123456789._-')
            # `echo "$base" | tr` also converts the trailing newline, so the
            # shot name carries one more underscore than the title does.
            for k, v in rates.items():
                san = ''.join(c if c in keep else '_' for c in k)
                if san.rstrip('_') == title.rstrip('_'):
                    m, s = v
                    break
        print(f'{kind:10} {cover:7.1f} {nc:8d}  {m:>7} {s:>7}  {title}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
