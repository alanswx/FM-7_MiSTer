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
"""
import os
import sys
import glob

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from classify import read_png                                   # noqa: E402
from gallery import agreement, stats                            # noqa: E402

BLANK = 1.0   # per-cent coverage at or below which a render is "blank"
DRAWN = 5.0   # per-cent coverage above which this core is definitely drawing


def score_dir(sweep, refdir):
    out = {}
    for p in sorted(glob.glob(os.path.join(sweep, 'shots', '*.png'))):
        name = os.path.basename(p)
        ref = os.path.join(refdir, name)
        if not os.path.exists(ref):
            continue
        rw, rh, rp = read_png(ref)
        w, h, px = read_png(p)
        rcov, _ = stats(rw, rh, rp)
        ocov, ocol = stats(w, h, px)
        out[name] = (agreement(px, w, rp, rw, rh), rcov, ocov, ocol)
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
    for name, (a, rcov, ocov, ocol) in now.items():
        if rcov > BLANK:
            scored.append((name, a, rcov, ocov, ocol))
        elif ocov > DRAWN:
            we_draw.append((name, a, rcov, ocov, ocol))
        else:
            blank_both.append(name)

    print(f"{len(now)} titles: {len(scored)} scored, "
          f"{len(blank_both)} blank on both sides, {len(we_draw)} drawn here only\n")

    if we_draw:
        print("=== the reference is blank and this core is NOT ===")
        print("(check these by eye -- a low agreement here is not a regression)")
        for n, a, rcov, ocov, ocol in sorted(we_draw, key=lambda r: -r[3]):
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
        for n, (a, rcov, ocov, ocol) in now.items():
            if n not in base:
                continue
            b = base[n][0]
            if abs(a - b) > 0.005:
                kind = 'we-draw' if rcov <= BLANK and ocov > DRAWN else 'scored'
                moved.append((a - b, a, b, n, kind))
        moved.sort(key=lambda r: -r[0])
        print(f"\n=== {len(moved)} titles moved vs {os.path.basename(args[1])} ===")
        print(f"{'now':>7} {'base':>7} {'delta':>7}  kind      TITLE")
        for d, a, b, n, kind in moved:
            print(f"{a:6.2f}% {b:6.2f}% {d:+6.2f}  {kind:8s}  {n[:-4][:40]}")
        sm = [r for r in moved if r[4] == 'scored']
        if sm:
            print(f"\nof those, {len(sm)} are on titles the reference actually drew:")
            for d, a, b, n, _ in sm:
                print(f"  {d:+6.2f}  {n[:-4][:44]}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
