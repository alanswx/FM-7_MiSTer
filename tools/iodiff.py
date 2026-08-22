#!/usr/bin/env python3
"""Where do this core and 77AVEMU first disagree?

    # this core
    cd vsim && ./obj_dir/Vemu --headless --machine fm77av --disk TITLE.d77 \\
        --stop-at-frame 600 --trace-io /tmp/ours.log

    # the reference, same title
    refs/local/fm77av_headless refs/local/fm77av-roms TITLE.d77 20000000 \\
        /dev/null --trace-io > /tmp/ref.log

    tools/iodiff.py /tmp/ours.log /tmp/ref.log

A screenshot says a title is blank. It cannot say *where* the two machines
parted company, and for a title that executes healthily and never draws -- the
class Shounen Mike, Woody Poco and Pro Yakyuu Fan are all in -- that is the only
question that matters. Both sides already emit every $FDxx access with the PC
that made it, so the answer is a diff away.

The two traces really do run in lockstep from reset: the first accesses of any
title match port, value AND program counter on both machines. That is what makes
the PC usable as part of the comparison key rather than just a label, and it is
worth re-checking on any title before trusting a result -- if the opening
sequence does not match, something more basic is wrong than the divergence this
tool is looking for.

**Runs of identical accesses are collapsed to one entry with a count.** Polling
is most of any trace -- a `LDA $fd1f / BITA` wait can spin thousands of times --
and the two machines will never agree on how many times round a timing loop they
go. Comparing raw traces drowns the signal in that. Comparing the *sequence* of
distinct accesses, with the repeat counts carried alongside as information
rather than as part of the key, is what makes the divergence visible. A count
that differs by orders of magnitude is still worth reading: it usually means one
machine escaped a loop the other is stuck in, which is the finding itself.

Note the two traces cover different ground: `--trace-io` on this core logs the
main CPU's $FDxx only, while the reference logs the sub CPU's $D4xx as well.
Sub-side accesses are dropped by default so the two are comparable; --sub keeps
them, which is useful only when diffing a reference trace against itself.
"""
import re
import sys
import difflib

OURS = re.compile(r'^\s*(\d+)\s+([RW])\s+\$(fd|d4)([0-9a-f]{2})\s+(?:<-|->)\s+\$([0-9a-f]{2})\s+pc=\$([0-9a-f]{4})')
REF = re.compile(r'^IO(WRITE|READ)\s+(MAIN|SUB):\s*([0-9A-F]{4})\s+IO:([0-9A-F]{4})\s+VALUE:([0-9A-F]{2})')


def load_ours(path, keep_sub=False):
    out = []
    for line in open(path, errors='replace'):
        m = OURS.match(line)
        if m:
            frame, rw, page, port, val, pc = m.groups()
            if page == 'd4' and not keep_sub:
                continue
            # $d4xx is carried in the high byte so the two pages cannot collide
            # in the comparison key.
            p = int(port, 16) | (0xd400 if page == 'd4' else 0)
            out.append((rw, p, int(val, 16), int(pc, 16), int(frame)))
    return out


def load_ref(path, keep_sub):
    out = []
    for line in open(path, errors='replace'):
        m = REF.match(line)
        if not m:
            continue
        kind, cpu, pc, io, val = m.groups()
        io = int(io, 16)
        page = io & 0xFF00
        if page not in (0xFD00, 0xD400):
            continue
        if page == 0xD400 and not keep_sub:
            continue
        p = (io & 0xFF) | (0xd400 if page == 0xD400 else 0)
        out.append(('W' if kind == 'WRITE' else 'R', p,
                    int(val, 16), int(pc, 16), 0))
    return out


def collapse(events, use_pc):
    """Fold runs of identical accesses into (key, count, first_frame)."""
    out = []
    for rw, port, val, pc, frame in events:
        key = (rw, port, val, pc) if use_pc else (rw, port, val)
        if out and out[-1][0] == key:
            out[-1][1] += 1
        else:
            out.append([key, 1, frame])
    return out


def fmt(entry, use_pc):
    key, count, frame = entry
    if use_pc:
        rw, port, val, pc = key
        s = f"{rw} ${'d4' if port & 0xd400 else 'fd'}{port & 0xff:02x} {'<-' if rw=='W' else '->'} ${val:02x}  pc=${pc:04x}"
    else:
        rw, port, val = key
        s = f"{rw} ${'d4' if port & 0xd400 else 'fd'}{port & 0xff:02x} {'<-' if rw=='W' else '->'} ${val:02x}"
    if count > 1:
        s += f"   x{count}"
    return s, frame


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    use_pc = '--no-pc' not in sys.argv
    keep_sub = '--sub' in sys.argv
    # --ports 18-1f narrows both traces to one device before diffing. A whole
    # trace is dominated by whatever polls hardest, and the divergence that
    # matters is often a handful of accesses to one register underneath it.
    want = None
    for a in sys.argv[1:]:
        if a.startswith('--ports='):
            want = set()
            for part in a.split('=', 1)[1].split(','):
                if '-' in part:
                    lo, hi = part.split('-')
                    want |= set(range(int(lo, 16), int(hi, 16) + 1))
                else:
                    want.add(int(part, 16))
    context = 6
    if len(args) != 2:
        print(__doc__)
        return 2

    oe, re_ = load_ours(args[0], keep_sub), load_ref(args[1], keep_sub)
    if want is not None:
        oe = [e for e in oe if e[1] in want]
        re_ = [e for e in re_ if e[1] in want]
        print(f"narrowed to ports {' '.join(f'${p:02x}' for p in sorted(want))}\n")
    ours = collapse(oe, use_pc)
    ref = collapse(re_, use_pc)
    if not ours or not ref:
        print(f"empty trace: ours {len(ours)} entries, reference {len(ref)}", file=sys.stderr)
        return 1

    a = [e[0] for e in ours]
    b = [e[0] for e in ref]
    print(f"this core : {len(a)} distinct accesses (runs collapsed)")
    print(f"77AVEMU   : {len(b)} distinct accesses")
    print(f"comparing on {'direction, port, value and PC' if use_pc else 'direction, port and value'}\n")

    sm = difflib.SequenceMatcher(a=a, b=b, autojunk=False)
    ops = sm.get_opcodes()
    matched = sum(o[2] - o[1] for o in ops if o[0] == 'equal')
    print(f"agree on the first {ops[0][2] - ops[0][1]} accesses; "
          f"{matched} of {len(a)} match overall\n")

    shown = 0
    for tag, i1, i2, j1, j2 in ops:
        if tag == 'equal':
            continue
        if shown == 0:
            print(f"=== first divergence, at our access {i1} "
                  f"(frame {ours[i1][2] if i1 < len(ours) else '?'}) ===\n")
            lo = max(0, i1 - context)
            for k in range(lo, i1):
                s, f = fmt(ours[k], use_pc)
                print(f"    both  {s}")
            print()
        shown += 1
        if shown > 3:
            print(f"    ... and {len(ops) - 1 - 3} more differing regions")
            break
        for k in range(i1, min(i2, i1 + context)):
            s, f = fmt(ours[k], use_pc)
            print(f"    OURS  {s}")
        if i2 > i1 + context:
            print(f"    OURS  ... {i2 - i1 - context} more")
        for k in range(j1, min(j2, j1 + context)):
            s, f = fmt(ref[k], use_pc)
            print(f"    REF   {s}")
        if j2 > j1 + context:
            print(f"    REF   ... {j2 - j1 - context} more")
        print()

    if shown == 0:
        print("no divergence: the two traces are identical as sequences.")

    # Which registers are involved, over the whole trace rather than just the
    # first divergence. Every AV title diverges first inside the boot ROM -- the
    # same access index on every disk -- so the first-divergence view alone says
    # nothing title-specific. This does: a port only this core touches, or one
    # the reference works far harder at, is where to look next.
    ours_tot, ref_tot = {}, {}
    for e in ours: ours_tot[e[0][1]] = ours_tot.get(e[0][1], 0) + e[1]
    for e in ref:  ref_tot[e[0][1]]  = ref_tot.get(e[0][1], 0) + e[1]

    ours_only, ref_only = {}, {}
    for tag, i1, i2, j1, j2 in ops:
        if tag == 'equal':
            continue
        for k in range(i1, i2):
            port = ours[k][0][1]
            ours_only[port] = ours_only.get(port, 0) + ours[k][1]
        for k in range(j1, j2):
            port = ref[k][0][1]
            ref_only[port] = ref_only.get(port, 0) + ref[k][1]

    # WHOLE-TRACE totals next to the differing-region counts. Both are needed
    # and reading only one misleads: a port can show zero in the differing
    # columns purely because its accesses all landed in matching regions, which
    # reads as "this core never touches it" and is wrong. The totals are the
    # honest measure of who does more work; the differing columns say where the
    # sequences actually came apart.
    print("\n=== by port: whole trace, and inside differing regions ===")
    print(f"{'port':>6s} {'ours':>9s} {'77AVEMU':>9s} | {'ours(d)':>8s} {'ref(d)':>8s}   note")
    for port in sorted(set(ours_tot) | set(ref_tot),
                       key=lambda p: -(ours_tot.get(p, 0) + ref_tot.get(p, 0)))[:16]:
        ot, rt = ours_tot.get(port, 0), ref_tot.get(port, 0)
        o, r = ours_only.get(port, 0), ref_only.get(port, 0)
        note = ''
        if ot and not rt:
            note = 'only this core touches it'
        elif rt and not ot:
            note = 'only the reference touches it'
        elif rt > ot * 8:
            note = f'reference does {rt // max(ot,1)}x more'
        elif ot > rt * 8:
            note = f'this core does {ot // max(rt,1)}x more'
        print(f"  ${'d4' if port & 0xd400 else 'fd'}{port & 0xff:02x} {ot:9d} {rt:9d} | {o:8d} {r:8d}   {note}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
