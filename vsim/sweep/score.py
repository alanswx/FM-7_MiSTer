#!/usr/bin/env python3
"""Score a sweep against 77AVEMU's renders, split by whether the reference drew.

    ./score.py <sweep-dir> [baseline-sweep-dir]

`gallery.py` pairs the images for a human to judge. This answers the narrower
question -- "did the set get better or worse" -- and it exists because the
obvious way to answer it is wrong.

**Half the AV set renders BLANK on the reference.** 33 of 67 titles at the time
of writing. Agreement is computed per pixel, so two blank screens agree on
100.0% of them, and those titles dominate any mean taken over the whole set:
they inflate it, they make "titles >= 99%" meaningless, and -- the part that
actually cost time -- a core that starts rendering one of them correctly gets
scored as a REGRESSION.

That is not hypothetical. World Golf II disk 1 sat at 100.00% agreement while
both machines drew nothing. When `c2fc867` fixed the sub I/O decode this core
began drawing its full title screen -- kana logo, golfer, mountains -- and the
number fell to 57.58%, which read as the worst regression in the sweep until the
reference's own coverage was checked and turned out to be 0.0%.

So this script never reports a single mean. It reports three groups:

  scored     the reference drew something, so agreement means something
  blank-both both sides blank -- excluded from the mean, counted only
  we-draw    the reference is blank and this core is not; NOT a regression,
             and worth looking at by eye before believing either machine

With a baseline directory it also prints the movers, and applies the same split
so a `we-draw` title is never listed as a loss.

**It scores the BEST of several samples, not one fixed frame.** The sweep now
takes a spread of screenshots per run (`SHOTLIST` in av-sweep.sh) because the
reference is frozen at a fixed 20,000,000 6809 steps while this core samples at
a fixed frame, and those are different moments. They agreed only by accident,
while the AV main CPU was clocked at the FM-8 rate; `6a7030e` corrected it and a
third of the set promptly "regressed" without a pixel being wrong. Scoring the
closest sample removes that whole class of false result. The frame that won is
printed, so a title that only matches early is visible rather than silently
flattered.

**`shift?` marks the giveaway.** When coverage and colour count both match the
reference closely but agreement is poor, the picture has MOVED rather than
broken -- a scrolling playfield or a timed demo sampled at the wrong instant.
Dragon Buster read as the sweep's worst regression that way while being a
32-point improvement. Treat a `shift?` row as unproven, not as a loss.
"""
import os
import sys
import glob

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from classify import read_png                                   # noqa: E402
from gallery import agreement, stats                            # noqa: E402

BLANK = 1.0   # per-cent coverage at or below which a render is "blank"
DRAWN = 5.0   # per-cent coverage above which this core is definitely drawing


def samples_for(shotsdir, name):
    """The canonical shot plus every phase sample the sweep took for it."""
    base = name[:-4]
    extra = sorted(glob.glob(os.path.join(shotsdir, base + '_frame_*.png')))
    return [os.path.join(shotsdir, name)] + extra


def frame_of(path):
    m = os.path.basename(path).rsplit('_frame_', 1)
    return int(m[1][:-4]) if len(m) == 2 else None


def score_dir(sweep, refdir):
    out = {}
    shotsdir = os.path.join(sweep, 'shots')
    for p in sorted(glob.glob(os.path.join(shotsdir, '*.png'))):
        name = os.path.basename(p)
        if '_frame_' in name:
            continue                      # a sample; scored via its canonical row
        ref = os.path.join(refdir, name)
        if not os.path.exists(ref):
            continue
        rw, rh, rp = read_png(ref)
        rcov, rcol = stats(rw, rh, rp)
        best = None
        for cand in samples_for(shotsdir, name):
            if not os.path.exists(cand):
                continue
            w, h, px = read_png(cand)
            a = agreement(px, w, rp, rw, rh)
            if best is None or a > best[0]:
                best = (a, *stats(w, h, px), frame_of(cand))
        if best is None:
            continue
        a, ocov, ocol, fr = best
        # Coverage and colour count agree but the pixels do not: the picture
        # moved rather than broke. Not a verdict, a flag to go and look.
        shifted = (abs(ocov - rcov) < 2.0 and abs(ocol - rcol) <= 3 and a < 90.0)
        out[name] = (a, rcov, ocov, ocol, fr, shifted)
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    if not args:
        print(__doc__)
        return 2
    refdir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          'renders', 'ref-shots')
    now = score_dir(args[0], refdir)
    base = score_dir(args[1], refdir) if len(args) > 1 else {}

    scored, blank_both, we_draw = [], [], []
    for name, (a, rcov, ocov, ocol, fr, shifted) in now.items():
        if rcov > BLANK:
            scored.append((name, a, rcov, ocov, ocol, fr, shifted))
        elif ocov > DRAWN:
            we_draw.append((name, a, rcov, ocov, ocol, fr, shifted))
        else:
            blank_both.append(name)

    print(f"{len(now)} titles: {len(scored)} scored, "
          f"{len(blank_both)} blank on both sides, {len(we_draw)} drawn here only\n")

    if we_draw:
        print("=== the reference is blank and this core is NOT ===")
        print("(check these by eye -- a low agreement here is not a regression)")
        for n, a, rcov, ocov, ocol, fr, sh in sorted(we_draw, key=lambda r: -r[3]):
            print(f"  ours {ocov:5.1f}% in {ocol:2d} colours, reference {rcov:4.1f}%"
                  f"   agreement {a:5.1f}%   {n[:-4][:44]}")
        print()

    if scored:
        m = sum(r[1] for r in scored) / len(scored)
        print(f"mean agreement over the {len(scored)} titles the reference drew: {m:.2f}%")
        print(f"  >= 99%: {sum(1 for r in scored if r[1] >= 99)}"
              f"   < 50%: {sum(1 for r in scored if r[1] < 50)}")

    if base:
        moved = []
        for n, (a, rcov, ocov, ocol, fr, shifted) in now.items():
            if n not in base:
                continue
            b = base[n][0]
            if abs(a - b) > 0.005:
                kind = 'we-draw' if rcov <= BLANK and ocov > DRAWN else 'scored'
                if shifted:
                    kind = 'shift?'
                moved.append((a - b, a, b, n, kind, fr))
        moved.sort(key=lambda r: -r[0])
        print(f"\n=== {len(moved)} titles moved vs {os.path.basename(args[1])} ===")
        print(f"{'now':>7} {'base':>7} {'delta':>7}  kind      TITLE")
        for d, a, b, n, kind, fr in moved:
            at = f" @f{fr}" if fr else ""
            print(f"{a:6.2f}% {b:6.2f}% {d:+6.2f}  {kind:8s}  {n[:-4][:34]}{at}")
        sm = [r for r in moved if r[4] == 'scored']
        if sm:
            print(f"\nof those, {len(sm)} are on titles the reference actually drew:")
            for d, a, b, n, _, fr in sm:
                print(f"  {d:+6.2f}  {n[:-4][:44]}")
        sh = [r for r in moved if r[4] == 'shift?']
        if sh:
            print(f"\nand {len(sh)} moved only in PHASE -- coverage and colours still")
            print("match the reference, so the picture shifted rather than broke:")
            for d, a, b, n, _, fr in sh:
                print(f"  {d:+6.2f}  {n[:-4][:44]}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
