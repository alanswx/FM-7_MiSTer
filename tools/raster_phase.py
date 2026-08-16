#!/usr/bin/env python3
"""Does a VRAM byte land on the screen column it belongs to?

    tools/raster_phase.py <vram.bin> <screenshot.png> [--320]

Takes this core's own VRAM dump and its own screenshot **from the same run**,
predicts each pixel's palette code from VRAM, and asks whether one consistent
palette explains the whole screen at each candidate horizontal offset. Only the
true offset can: anywhere else the code and the pixel disagree wherever the
picture has detail, and no single mapping fits. The answer must be dx=0.

    cd vsim
    FM7_VRAM_DUMP=/tmp/v.bin ./obj_dir/Vemu --headless --machine fm77av \\
        --disk '../software/D77/Wizardry IV (FM77AV) (Disk A).d77' \\
        --stop-at-frame 620 --av-dump-frame 600 \\
        --screenshot 600 --screenshot-name /tmp/s.png
    ../tools/raster_phase.py /tmp/v.bin /tmp/s.png

Why this rather than a Verilog bench. The screenshot suite cannot see a fault
that moves the WHOLE picture, because every reference is the core's own output
and shifts with it -- the core displayed every frame three pixels right of where
it belonged, in both modes, for the life of the project, with eleven blessed
screenshots and a 350-title sweep green throughout. A standalone bench over
MB60H010 + CRTRAM + PAL was tried and is NOT in the tree: driven with the core's
own modules and sampled exactly as sim.v samples, it still reported the 640-mode
picture one column left of where the assembled core actually puts it. Whatever
that harness was missing, this measurement does not depend on knowing -- it asks
the assembled core, and it needs no reference emulator either.

Requires the run to be in a steady 640x200 or 320x200 mode at the dump frame,
and assumes a zero VRAM scroll offset (true for a title screen).

**Only trust the 640-mode answer.** With eight colour codes on a screen, a wrong
offset has to reuse a code on a differently-coloured pixel and constantly does:
the right offset scores ~99% against ~89-94% either side. 320 mode has thousands
of codes, most nearly unique to a single pixel, so every offset scores ~99.97%
and the peak carries almost no information. Check 320 alignment against 77AVEMU.
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                '..', 'vsim', 'sweep'))
from classify import read_png                                   # noqa: E402


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    mode320 = '--320' in sys.argv[1:]
    if len(args) != 2:
        print(__doc__)
        return 2
    vram = open(args[0], 'rb').read()
    w, h, px = read_png(args[1])
    if len(vram) != 98304:
        print(f"expected a 98304-byte AV VRAM dump, got {len(vram)}")
        return 1

    # The dump is bank, then gun (blue, red, green), then two 8 KB halves.
    def slice_(bank, gun, half):
        i = bank * 6 + gun * 2 + half
        return vram[i * 8192:(i + 1) * 8192]

    if mode320:
        # Four planes per gun: bank0's two halves are bits 3 and 2, bank1's are
        # bits 1 and 0 -- the order 77AVEMU's renderer assembles the DAC index
        # in, {G3..G0, R3..R0, B3..B0}.
        planes = [slice_(b, g, hf) for g in (2, 1, 0) for b, hf in
                  ((0, 0), (0, 1), (1, 0), (1, 1))]
        bytes_per_line, width = 40, 320

        def code(x, y):
            a = y * bytes_per_line + (x >> 3)
            bit = 0x80 >> (x & 7)
            v = 0
            for p in planes:
                v = (v << 1) | (1 if p[a] & bit else 0)
            return v
    else:
        # 640x200 page 0: 16 KB per gun, its two halves contiguous.
        guns = [slice_(0, g, 0) + slice_(0, g, 1) for g in (2, 1, 0)]
        bytes_per_line, width = 80, 640

        def code(x, y):
            a = y * bytes_per_line + (x >> 3)
            bit = 0x80 >> (x & 7)
            v = 0
            for p in guns:
                v = (v << 1) | (1 if p[a] & bit else 0)
            return v

    step = w // width          # 320 mode is pixel-doubled to 640 on this core
    best = None
    for dx in range(-2, 7):
        buckets = {}
        for y in range(h):
            for x in range(width):
                xx = x + dx
                if not (0 <= xx < width):
                    continue
                c = code(x, y)
                p = px[y * w + xx * step]
                buckets.setdefault(c, {})
                buckets[c][p] = buckets[c].get(p, 0) + 1
        good = sum(max(hist.values()) for hist in buckets.values())
        tot = sum(sum(hist.values()) for hist in buckets.values())
        pct = 100.0 * good / tot
        print(f"  dx={dx:+d}: one palette explains {pct:6.2f}% of pixels"
              f"   ({len(buckets)} codes)")
        if best is None or pct > best[0]:
            best = (pct, dx)

    print(f"\nbest dx={best[1]:+d} at {best[0]:.2f}% -- "
          f"{'OK' if best[1] == 0 else 'PICTURE IS DISPLACED'}")
    return 0 if best[1] == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
