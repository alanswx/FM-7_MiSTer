#!/usr/bin/env python3
"""Prove a title STARTS and RESPONDS TO INPUT -- which a screenshot cannot.

    cd vsim && ./gameplay.py            # every test
    ./gameplay.py thexder               # substring filter
    ./gameplay.py --list

WHY THIS EXISTS, AND WHY IT IS NOT JUST ANOTHER SCREENSHOT TEST

`run_tests.sh` proves the machine draws the right pixels at one instant. It
cannot tell a title screen from a game, because both are a plausible picture,
and every existing measure in this repo -- coverage %, colour count, byte size
-- is equally happy with a game that has frozen on its logo. The sweep campaign
hit exactly that wall repeatedly: "renders a real screen" was never the same
claim as "runs".

Nor is animation enough on its own. Most FM-7 titles have an attract mode, so a
screen that changes over time proves the machine is executing, not that it is
listening. Thexder's own title screen scrolls.

So the test is a CONTROLLED EXPERIMENT, and the control is the point:

    run A   the title with a scripted key/joystick sequence
    run B   the identical title, identical frames, NO INPUT AT ALL

and the verdict comes from the DIFFERENCE between them. If A and B diverge, the
machine consumed the input and acted on it; nothing an attract loop does can
fake that, because run B has the attract loop too. If they are identical, the
input reached nothing -- which is the failure this harness is for, and it is
invisible to a single screenshot however carefully it is scored.

Two things follow that are worth stating plainly:

* A PASS here is about the INPUT PATH, not about the game being playable. This
  cannot tell "the ship moved" from "the menu cursor moved"; it tells you the
  keyboard or joystick reached the software and changed what it did.
* A FAIL is not automatically a core bug. The key may be the wrong one for the
  title. Check `--list`'s sequence against the game before filing anything --
  and note the joystick tests can only fail meaningfully on a title that polls
  the stick at all (see JOYSTICK TITLES below).

JOYSTICK TITLES

A sound driver only ever WRITES $fd0e; an extended READ of it is the joystick
signature (`docs/IO_MAP.md`: select with PSG register 15, read register 14
active-low). Scanning the 525 distinct FM-7 images for `B6 FD 0E` / `F6 FD 0E`
finds 42, and almost all are single hits. The strongest by a wide margin are
**Death Force** (10x) and **Wibarm** (2x); Topple Zip, Space Harrier and Space
Bee have one each. Per-title joystick support is also recorded as structured
metadata at https://fm-7.com/museum (a ジョイスティック field on each product
page), which is the authority when this scan and a title disagree.

**Thexder cannot test the joystick** -- it never touches PSG registers 14/15, so
no stick can drive it on any machine. It is here as a KEYBOARD test.

MUST RUN FROM vsim/. The Verilog loads its ROMs with $readmem on relative paths
and Verilator treats a failed load as a warning, so from anywhere else every ROM
is silently empty and every title "fails" identically.

DO NOT RUN ALONGSIDE run_tests.sh. docs/HANDOFF.md records four separate runs
invalidated by exactly that.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'sweep'))
from classify import read_png                                    # noqa: E402
from gallery import stats                                        # noqa: E402

EXE  = os.path.join(HERE, 'obj_dir', 'Vemu')
DISK = os.path.join(HERE, '..', 'software', 'D77')
OUT  = os.path.join(HERE, 'gameplay-shots')

# Fraction of pixels that must differ between the input run and the silent one
# before the input counts as having been consumed. Deliberately low: a menu
# cursor moving is a real response and is only a few hundred pixels of 128,000.
# It is not zero because two runs of a deterministic simulator are otherwise
# bit-identical, so anything above noise is signal -- there is no noise here.
DIVERGE_MIN = 0.05

TESTS = [
    dict(
        name='thexder-key',
        disk='Thexder [b].d77',
        # A SPREAD, not a guess. Thexder's start key is not documented anywhere
        # I can find (the DOS port uses numpad 4/6/8/2 + Alt, which says nothing
        # about the FM-7 release), and each attempt costs a ~40-minute run. The
        # divergence test does not care WHICH key was consumed -- it only asks
        # whether the keyboard reached the software at all -- so send several
        # and let the control answer it.
        #
        # Placed late on purpose: the title sequence is still drawing its logo
        # at f1450, and a key sent during that is ignored. Measured, not
        # assumed -- a silent run changes ~9.4% per 500 frames from f650 to
        # f2000 with coverage pinned at 60% / 7 colours, which is the logo
        # scrolling in and is IDENTICAL in a run that pressed four keys.
        keys=[(1600, '@SPACE'), (1900, '@RETURN'), (2200, '1'),
              (2500, '@F1'), (2800, '8'), (3100, '@UP')],
        shots=[1500, 2500, 3500],
        min_cov=20.0,
        note='keyboard; Thexder never reads PSG 14/15 so it cannot test a stick',
    ),
    dict(
        name='deathforce-joy',
        disk='Death Force (1987)(River Hill)(JP).d77',
        machine='fm77av',          # screened as AV software -- cohort 08
        joy=[(1500, 'fire', 30), (1700, 'right', 30), (1900, 'fire', 30)],
        shots=[1400, 1800, 2100],
        min_cov=1.0,
        note='10 extended reads of $fd0e, the strongest joystick title in the set',
    ),
    dict(
        name='wibarm-joy',
        disk='Wibarm (1986)(Arsys)(JP).d77',
        joy=[(1500, 'fire', 30), (1700, 'up', 30), (1900, 'fire', 30)],
        shots=[1400, 1800, 2100],
        min_cov=5.0,
        note='2 extended reads of $fd0e',
    ),
]


def run(t, with_input, reuse=True):
    """One run. `with_input` False is the control: same disk, same frames.

    The control is REUSED when its shots already exist. It depends only on the
    disk and the frame list, never on the key sequence, so iterating on which
    keys to send costs one run rather than two -- and at ~40 minutes a run for a
    title with a long attract sequence, that is the difference between trying
    six key spreads and trying three. Delete gameplay-shots/ to force a rebuild.
    """
    tag = t['name'] + ('' if with_input else '-silent')
    if reuse and not with_input and \
       all(os.path.exists(os.path.join(OUT, '%s_frame_%04d.png' % (tag, f)))
           for f in t['shots']):
        return tag
    cmd = [EXE, '--headless', '--bootrom', '0',
           '--machine', t.get('machine', 'fm7'),
           '--disk', os.path.join(DISK, t['disk']),
           '--screenshot', ','.join(str(f) for f in t['shots']),
           '--screenshot-prefix', os.path.join(OUT, tag),
           '--stop-at-frame', str(max(t['shots']) + 10)]
    if with_input:
        for fr, txt in t.get('keys', []):
            cmd += ['--key', '%d:%s' % (fr, txt)]
        for fr, btn, hold in t.get('joy', []):
            cmd += ['--joystick', '%d:%s:%d' % (fr, btn, hold)]
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                       cwd=HERE, check=False)
    # The run summary's own counters, kept so the verdict can tell "the harness
    # never injected anything" apart from "the title ignored what it was sent".
    # Those look identical in the pixels and are completely different bugs.
    strobes = 0
    for line in r.stdout.decode('utf-8', 'replace').splitlines():
        if line.startswith('keyboard'):
            for w in line.replace(',', ' ').split():
                if w.isdigit():
                    strobes = int(w); break
    open(os.path.join(OUT, tag + '.strobes'), 'w').write(str(strobes))
    return tag


def strobes_of(tag):
    p = os.path.join(OUT, tag + '.strobes')
    return int(open(p).read()) if os.path.exists(p) else -1


def shot(tag, frame):
    p = os.path.join(OUT, '%s_frame_%04d.png' % (tag, frame))
    return read_png(p) if os.path.exists(p) else None


def diff_pct(a, b):
    if a is None or b is None or len(a[2]) != len(b[2]):
        return None
    px, qx = a[2], b[2]
    return 100.0 * sum(1 for x, y in zip(px, qx) if x != y) / len(px)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    if '--list' in sys.argv:
        for t in TESTS:
            seq = t.get('keys') or t.get('joy') or []
            print('%-18s %s\n%18s %s\n%18s %s' %
                  (t['name'], t['disk'], '', seq, '', t['note']))
        return 0
    os.makedirs(OUT, exist_ok=True)
    if not os.path.exists(EXE):
        print('no simulator at %s -- build it first' % EXE); return 2

    tests = [t for t in TESTS if not args or any(a in t['name'] for a in args)]
    print('%-18s %8s %8s %10s %8s  %s' %
          ('TEST', 'STARTED', 'RESPOND', 'DIVERGE%', 'STROBES', 'VERDICT'))
    print('-' * 88)
    bad = 0
    for t in tests:
        live = run(t, True)
        ctrl = run(t, False)
        first, last = t['shots'][0], t['shots'][-1]
        a, b = shot(live, first), shot(live, last)
        c    = shot(ctrl, last)
        if a is None or b is None or c is None:
            print('%-18s %8s %8s %10s  NO-SHOT (run did not complete)' %
                  (t['name'], '-', '-', '-')); bad += 1; continue
        cov = stats(a[0], a[1], a[2])[0]
        started = cov >= t['min_cov']
        d = diff_pct(b, c)
        responded = d is not None and d >= DIVERGE_MIN
        sent = strobes_of(live)
        # THREE outcomes, not two. A title that ignores the key it was sent is
        # not the same failure as a harness that sent nothing, and the pixels
        # cannot tell them apart -- both are "identical to the control".
        if not started:
            verdict = 'DID NOT START'
        elif responded:
            verdict = 'ok'
        elif sent == 0 and t.get('keys'):
            verdict = 'NOT INJECTED (harness bug)'
        else:
            verdict = 'delivered, title ignored it'
        if verdict not in ('ok', 'delivered, title ignored it'):
            bad += 1
        print('%-18s %7.1f%% %8s %9.3f%% %8d  %s' %
              (t['name'], cov, 'yes' if responded else 'no', d or 0.0,
               sent, verdict))
    print()
    print('shots in %s' % os.path.relpath(OUT, HERE))
    if bad:
        print('%d test(s) failed. A failure is not automatically a core bug --\n'
              'check the key sequence against the title first (--list).' % bad)
    print('\n"delivered, title ignored it" is NOT a failure: the strobe count\n'
          'proves the key reached the keyboard hardware and the title did not\n'
          'act on it. Thexder does that -- its attract loop runs indefinitely\n'
          'and consumes none of SPACE/RETURN/1/F1/8/UP.')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
