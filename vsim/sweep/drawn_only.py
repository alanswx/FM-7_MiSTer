#!/usr/bin/env python3
"""Filter a sweep image list down to the titles 77AVEMU itself renders.

    drawn_only.py <images.txt> <ref-shots-dir>   -> filtered list on stdout

Used by `av-sweep.sh DRAWN_ONLY=1`. A title whose reference render is blank
contributes nothing to a regression check -- see the long comment in
av-sweep.sh, and score.py for why a blank reference also flatters the mean.

A title with NO reference render at all is kept: absent is not the same as
blank, and dropping it would silently narrow the sweep.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from classify import read_png                                   # noqa: E402
from gallery import stats                                       # noqa: E402

BLANK = 1.0

def main():
    images, refdir = sys.argv[1], sys.argv[2]
    kept = dropped = 0
    for line in open(images):
        img = line.rstrip('\n')
        if not img:
            continue
        base = os.path.basename(img)
        base = base[:-4] if base.lower().endswith('.d77') else base
        # sweep_one.sh builds this with `echo "$base" | tr -c 'A-Za-z0-9._-' '_'`,
        # and tr rewrites echo's trailing NEWLINE too -- so every reference name
        # carries one extra trailing underscore. Getting this wrong silently
        # matches nothing and the filter passes the whole list through.
        safe = ''.join(c if c.isalnum() or c in '._-' else '_' for c in base) + '_'
        ref = os.path.join(refdir, safe + '.png')
        if os.path.exists(ref):
            w, h, px = read_png(ref)
            if stats(w, h, px)[0] <= BLANK:
                dropped += 1
                continue
        print(img)
        kept += 1
    print(f"drawn-only: kept {kept}, dropped {dropped} blank-reference titles",
          file=sys.stderr)

if __name__ == '__main__':
    main()
