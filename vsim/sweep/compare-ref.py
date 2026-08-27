#!/usr/bin/env python3
"""Join a sweep against its 77AVEMU renders, one row per title.

A sweep says "this title is blank". That is not a finding on its own: the AV
set is full of data, scenario and save disks that were never bootable, and a
title that is blank on the reference too is not our bug. This joins the two so
every row carries both verdicts and the difference is the only thing that needs
looking at.

    compare-ref.py <sweep-outdir>

Reads <outdir>/shots (the core), <outdir>/ref-shots (77AVEMU) and
<outdir>/results.tsv (instruction rates), and prints the rows sorted worst
first -- CORE-BLANK, where the reference drew a picture and we did not, is the
actionable list.

Verdicts:
  CORE-BLANK   reference renders graphics, core does not      <- our bug
  CORE-WORSE   both render, but the core has much less on screen
  BOTH-BLANK   neither renders -- not a bootable disk, or broken for everyone
  MATCH        both render comparable content
  REF-WORSE    the core renders and the reference does not (worth a look:
               usually the reference was given less machine time)
  NO-SHOT      one side has no render at all -- an unfinished sweep, or a title
               77AVEMU itself aborts on. Not a verdict about the core.
"""
import os
import re
import sys

FRAME_PNG = re.compile(r'_frame_\d+\.png$')

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from classify import classify   # noqa: E402


def load_rates(path):
    rates = {}
    if not os.path.exists(path):
        return rates
    keep = set('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
               '0123456789._-')
    for ln in open(path):
        f = ln.rstrip('\n').split('\t')
        if len(f) >= 6 and f[0] != 'MAIN_PF':
            san = ''.join(c if c in keep else '_' for c in f[5]).rstrip('_')
            rates[san] = (f[0], f[1])
    return rates


def safe_classify(path):
    if not path or not os.path.exists(path) or os.path.getsize(path) == 0:
        return ('missing', 0.0, 0)
    try:
        return classify(path)
    except Exception as e:                                   # noqa: BLE001
        print(f'{path}: {e}', file=sys.stderr)
        return ('unreadable', 0.0, 0)


def verdict(ours, ref):
    ok, oc, _ = ours
    rk, rc, _ = ref
    drew = {'GRAPHICS', 'lowcolour'}
    # A shot that is not there yet is NOT a blank shot. A sweep still running,
    # or one that died partway, would otherwise read as a long list of core
    # bugs -- which is the same class of mistake as scoring a screenshot by its
    # file size. Say so instead.
    if ok in ('missing', 'unreadable') or rk in ('missing', 'unreadable'):
        return 'NO-SHOT'
    if rk in drew and ok not in drew:
        return 'CORE-BLANK'
    if ok in drew and rk not in drew:
        return 'REF-WORSE'
    if ok in drew and rk in drew:
        # Both drew. Only flag a big shortfall; the two machines are never at
        # the same point in a title, so small differences mean nothing.
        if rc > 4.0 and oc < rc * 0.4:
            return 'CORE-WORSE'
        return 'MATCH'
    if ok == 'text' or rk == 'text':
        return 'TEXT-ONLY'
    return 'BOTH-BLANK'


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    out = sys.argv[1]
    ours_dir, ref_dir = os.path.join(out, 'shots'), os.path.join(out, 'ref-shots')
    rates = load_rates(os.path.join(out, 'results.tsv'))

    # sweep_one.sh leaves BOTH the canonical <title>.png and one
    # <title>_frame_<N>.png per sampled frame. Globbing all of them counts every
    # title twice and invents a NO-SHOT row for each per-frame file, which reads
    # as a half-finished sweep -- and makes `ls shots/*.png | wc -l` report
    # double the titles actually done. The canonical copy always exists if any
    # frame file does (sweep_one.sh falls back to the latest), so drop them.
    def names(d):
        return {n[:-4] for n in os.listdir(d)
                if n.endswith('.png') and not FRAME_PNG.search(n)}

    titles = sorted(names(ours_dir) | names(ref_dir)
                    if os.path.isdir(ref_dir) else names(ours_dir))

    rows = []
    for t in titles:
        ours = safe_classify(os.path.join(ours_dir, t + '.png'))
        ref = safe_classify(os.path.join(ref_dir, t + '.png'))
        rows.append((verdict(ours, ref), ours, ref, t))

    order = {'CORE-BLANK': 0, 'CORE-WORSE': 1, 'TEXT-ONLY': 2,
             'BOTH-BLANK': 3, 'MATCH': 4, 'REF-WORSE': 5, 'NO-SHOT': 6}
    rows.sort(key=lambda r: (order.get(r[0], 9), -r[2][1]))

    print(f'{"VERDICT":11} {"OURS":10} {"COV%":>6} {"REF":10} {"COV%":>6} '
          f'{"MAIN/f":>7} {"SUB/f":>7}  TITLE')
    counts = {}
    for v, ours, ref, t in rows:
        counts[v] = counts.get(v, 0) + 1
        m, s = rates.get(t.rstrip('_'), ('', ''))
        print(f'{v:11} {ours[0]:10} {ours[1]:6.1f} {ref[0]:10} {ref[1]:6.1f} '
              f'{m:>7} {s:>7}  {t}')
    print()
    for v in sorted(counts, key=lambda k: order.get(k, 9)):
        print(f'{counts[v]:4d}  {v}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
