#!/usr/bin/env python3
"""Score hardware screenshots: size, lit-pixel coverage, distinct colours.

Byte size alone is not a pass/fail signal (trap 6 -- a garbage frame measured
7444 bytes against a 5.3 KB banner), so this reports *lit* coverage and the
colour count separately.  "Lit" is any pixel that is not the frame's modal
colour, which is the background whether the title draws on black or not.

usage: score.py <png> [png...]
"""
import sys
from collections import Counter
from PIL import Image

print(f"{'label':<22} {'WxH':>9} {'bytes':>8} {'lit%':>7} {'cols':>5}  top colours")
for p in sys.argv[1:]:
    im = Image.open(p).convert("RGB")
    w, h = im.size
    px = list(im.getdata())
    c = Counter(px)
    bg, bgn = c.most_common(1)[0]
    lit = 100.0 * (len(px) - bgn) / len(px)
    import os
    top = " ".join("%02x%02x%02x:%.1f%%" % (r, g, b, 100.0*n/len(px))
                   for (r, g, b), n in c.most_common(3))
    print(f"{os.path.basename(p)[:-4]:<22} {w}x{h:<5} {os.path.getsize(p):>8} "
          f"{lit:>6.2f}% {len(c):>5}  {top}")
