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


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else 10
    i = shown = 0
    ctx = []
    print(f"{'#':>8} {'frame':>6}  {'OURS':<34} {'REFERENCE':<34}")
    for (ka, na, fra), (kb, nb, _) in zip(collapse(ours(sys.argv[1])),
                                          collapse(ref(sys.argv[2]))):
        i += 1
        ctx.append((i, fra, ka, na, kb, nb))
        if len(ctx) > 6:
            ctx.pop(0)
        if ka != kb:
            if shown == 0:
                for j, f2, x, xn, y, yn in ctx[:-1]:
                    print(f"{j:8d} {str(f2):>6}  {fmt(x, xn):<34} {fmt(y, yn):<34}")
            print(f"{i:8d} {str(fra):>6}  {fmt(ka, na):<34} {fmt(kb, nb):<34}  <<<")
            shown += 1
            if shown >= limit:
                break
    if shown == 0:
        print("\nno divergence in the overlapping prefix")
    else:
        print(f"\n{shown} shown. Read the FIRST one or two only -- once the streams")
        print("desynchronise, 'ours' row N lines up against 'reference' row N-1 and")
        print("every later row is an artifact of the offset, not a real difference.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
