#!/usr/bin/env python3
"""Where do this core and 77AVEMU first part company? -- streaming version.

    cd vsim && ./obj_dir/Vemu --headless --machine fm77av --disk TITLE.d77 \
        --stop-at-frame 2000 --trace-tail 0 --trace-io /tmp/ours.log

    refs/local/fm77av_headless refs/local/fm77av-roms TITLE.d77 20000000 \
        /dev/null --trace-io > /tmp/ref.log

    tools/seqdiff.py /tmp/ours.log /tmp/ref.log [N]

`iodiff.py` answers the same question and is nicer to read, but it holds both
traces in memory and did not finish inside ten minutes on the pair this was
written for (90 MB and 140 MB, ~1.2 M main-CPU accesses each). This streams
both sides, so it is O(1) in memory and returns in seconds.

WHAT IT COMPARES

Main-CPU $FDxx only, keyed on (direction, port, value, PC). That is the one
stream both machines log with the MAIN CPU's program counter, so the PC is real
information rather than a constant -- on a $D4xx line 77AVEMU logs the SUB CPU's
PC, which on an AV title is frozen wherever the halted sub is parked (see
REFERENCE.md trap 43). Runs of identical accesses collapse to one entry with a
count, because neither machine will agree with the other on how many times round
a polling loop it went.

READING THE OUTPUT

**Only the first divergence or two are real.** The two streams are compared
positionally, so the moment one machine emits an access the other does not, every
subsequent row is offset by one and looks like a divergence. The tell is that
"ours" row N starts matching "reference" row N-1. Fix the first difference, re-run,
and let the next one appear -- that is the loop this tool is for. It walked
Shounen Mike from $FD01 to $FD04 b2 to $FD0B to $FD18 one readback at a time.

**A count difference is not a divergence.** `x282` against `x99` on the same
polling read means the two machines spun a different number of times, which they
always will. Only the key is compared; counts are carried alongside as context.
"""
import re
import sys

OURS = re.compile(r'^\s*(\d+) ([RW]) \$(fd[0-9a-f]{2}) [-<]. \$([0-9a-f]{2})\s+pc=\$([0-9a-f]{4})')
REF = re.compile(r'^IO(READ|WRITE)\s+MAIN:\s*([0-9A-F]+) IO:(FD[0-9A-F]{2}) VALUE:([0-9A-F]+)')


def ours(path):
    with open(path, errors='replace') as f:
        for ln in f:
            m = OURS.match(ln)
            if m:
                port = m.group(3).upper()
                val = '--' if (m.group(2) == 'R' and port in VALUE_UNCOMPARABLE) \
                    else m.group(4).upper()
                yield (m.group(2), port, val, m.group(5).upper()), int(m.group(1))


# 77AVEMU's trace logs a read's value BEFORE the device's side effect runs.
# `FM77AV::IORead` takes `byteData = NonDestructiveIORead(ioAddr)`, prints that,
# and only then reaches `byteData = fdc.IORead(ioAddr)` in its switch -- so for a
# port whose read ADVANCES something, the logged value is the previous one. The
# CPU gets the right byte; the log is one behind. (They know: $FD02 re-reads
# after its side effect with the comment "This one needs to be read after Move."
# The FDC ports do not.)
#
# $FD1B, the FDC data register, is the one that matters here: a sector read logs
# the stale register and then every byte one late, which looks exactly like this
# core returning the wrong bytes. It is not -- reading the .d77 settles it, and
# REFERENCE.md section 1 has the worked example.
#
# So the VALUE of a $FD1B read is not comparable between the two traces. Compare
# direction, port and PC for it and leave the value out of the key, rather than
# letting a known logging artifact desynchronise the whole stream.
VALUE_UNCOMPARABLE = {'FD1B'}


def ref(path):
    with open(path, errors='replace') as f:
        for ln in f:
            m = REF.match(ln)
            if m:
                port = m.group(3)
                val = '--' if (m.group(1)[0] == 'R' and port in VALUE_UNCOMPARABLE) \
                    else m.group(4).zfill(2)
                yield (m.group(1)[0], port, val,
                       m.group(2).upper().zfill(4)), None


def collapse(gen):
    last, n, frame = None, 0, None
    for key, fr in gen:
        if key == last:
            n += 1
            continue
        if last is not None:
            yield last, n, frame
        last, n, frame = key, 1, fr
    if last is not None:
        yield last, n, frame


def fmt(key, n):
    d, port, val, pc = key
    return f"{d} ${port} {val} pc=${pc}" + (f" x{n}" if n > 1 else "")


def fill(buf, it, n):
    """Top `buf` up to n entries from `it`. Returns False at end of stream."""
    while len(buf) < n:
        try:
            buf.append(next(it))
        except StopIteration:
            return False
    return True


# How far to look for a re-sync point, and how many consecutive matches count as
# one. CONFIRM > 1 stops a single coincidentally-equal entry (a $FD05 poll, say)
# from being taken as alignment restored.
WINDOW = 40
CONFIRM = 3


def resync(a, b, ia, ib):
    """Smallest (da, db) that realigns a[ia+da:] with b[ib+db:], or None.

    Prefers the smallest total skip, so a one-sided insertion is reported as an
    insertion rather than as a long run of substitutions.
    """
    for total in range(1, 2 * WINDOW + 1):
        for da in range(0, min(total, WINDOW) + 1):
            db = total - da
            if db > WINDOW:
                continue
            if ia + da + CONFIRM > len(a) or ib + db + CONFIRM > len(b):
                continue
            if all(a[ia + da + k][0] == b[ib + db + k][0] for k in range(CONFIRM)):
                return da, db
    return None


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else 10
    ga, gb = collapse(ours(sys.argv[1])), collapse(ref(sys.argv[2]))
    a, b = [], []
    i = shown = 0
    ctx = []
    lost = False
    print(f"{'#':>8} {'frame':>6}  {'OURS':<34} {'REFERENCE':<34}")
    while True:
        oka = fill(a, ga, WINDOW + CONFIRM + 1)
        okb = fill(b, gb, WINDOW + CONFIRM + 1)
        if not a or not b:
            break
        (ka, na, fra), (kb, nb, _) = a[0], b[0]
        i += 1
        if ka == kb:
            ctx.append((i, fra, ka, na, kb, nb))
            if len(ctx) > 6:
                ctx.pop(0)
            a.pop(0); b.pop(0)
            continue

        if shown == 0:
            for j, f2, x, xn, y, yn in ctx:
                print(f"{j:8d} {str(f2):>6}  {fmt(x, xn):<34} {fmt(y, yn):<34}")
        ctx = []

        r = resync(a, b, 0, 0)
        if r is None:
            print(f"{i:8d} {str(fra):>6}  {fmt(ka, na):<34} {fmt(kb, nb):<34}  <<< LOST")
            lost = True
            shown += 1
            break
        da, db = r
        if da and not db:
            tag = f"<<< {da} extra HERE"
        elif db and not da:
            tag = f"<<< {db} extra on REFERENCE"
        else:
            tag = "<<<"
        print(f"{i:8d} {str(fra):>6}  {fmt(ka, na):<34} {fmt(kb, nb):<34}  {tag}")
        for k in range(1, max(da, db)):
            xa = fmt(*a[k][:2]) if k < da else ""
            xb = fmt(*b[k][:2]) if k < db else ""
            print(f"{'':8} {'':>6}  {xa:<34} {xb:<34}")
        shown += 1
        del a[:da]; del b[:db]
        if shown >= limit:
            break
        if not (oka or okb):
            break

    if shown == 0:
        print("\nno divergence in the overlapping prefix")
    else:
        print(f"\n{shown} divergence(s). These are RE-SYNCHRONISED: after each one the")
        print(f"tool realigns the two streams (look-ahead {WINDOW}, {CONFIRM} matches to")
        print("confirm), so unlike the old strict-positional version every row printed")
        print("is a real difference rather than an artifact of an earlier offset.")
        if lost:
            print("\nThe last row is marked LOST: the streams could not be realigned")
            print(f"within {WINDOW} entries, so they have genuinely gone different ways")
            print("and nothing past it is comparable.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
