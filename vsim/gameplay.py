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

The list, the scan that produced it and its limits live in `docs/IO_MAP.md`
under "Which titles actually read the stick" -- kept there rather than here
because it is a fact about the collection, not about this harness. The short
version: an extended READ of $fd0e is the signature, 42 of 525 images have one,
and **Death Force** (10 reads) and **Wibarm** (2) are the only ones with more
than a single call site.

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
    # ------------------------------------------------------------------
    # VERIFIED input-driven. Each was confirmed against its own silent
    # control before being written down here; the divergence figure quoted
    # is the measured one, not a target.
    # ------------------------------------------------------------------
    dict(
        name='frontline-key',
        disk='Front Line (1983)(Nidecom Carry Soft)(Taito)(Hiroshi Hasegawa)'
             '(Tetsuya Sasaki).d77',
        keys=[(1200, '@SPACE'), (1500, '@RETURN'), (1800, '1')],
        joy=[(2000, 'fire', 40), (2200, 'right', 40), (2400, 'fire', 40)],
        shots=[1100, 1900, 2600],
        min_cov=50.0,
        note='REAL GAMEPLAY: 90.58% against a silent run stuck at 3.49%, '
             'divergence 89.98%. Score/HI-SCORE/LEFT=8 HUD on screen.',
    ),
    dict(
        name='wibarm-2disk',
        disk='Wibarm (1986)(Arsys)(JP).d77',
        # THE POINT OF THIS TEST. Wibarm's .d77 is a two-disk CONTAINER --
        # disk 0 "WiBArM", disk 1 "DATA DISK" -- and with only disk 0 the
        # game stops dead on "SET DATA DISKETTE ON DRIVE 1 / HIT ANY KEY".
        # Mounting the same file on both drives and selecting sub-disk 1 for
        # drive 1 is what gets it into play, so this is the container feature
        # exercised by a real title that cannot proceed without it.
        disk1='Wibarm (1986)(Arsys)(JP).d77',
        disk1_index=1,
        keys=[(1200, '@SPACE'), (1500, '@RETURN'),
              (2700, '@SPACE'), (3000, '@RETURN'), (3300, '1')],
        joy=[(3600, 'fire', 40), (3800, 'right', 40)],
        shots=[2500, 3500, 4200],
        min_cov=30.0,
        note='REAL GAMEPLAY: 57.57% against a silent 0.00%, divergence 57.57%. '
             'ENERGY/MEDAL/ABILITY and MACHINE ABILITY panels on screen. '
             'With one disk it reaches only 1.29% and sits on the prompt.',
    ),
    dict(
        name='archon-key',
        disk='Archon.d77',
        keys=[(1200, '@SPACE'), (1500, '@RETURN'), (1800, '1')],
        shots=[1100, 1900, 2600],
        min_cov=30.0,
        note='reaches its MENU (START GAME / LIGHT SIDE / DARK SIDE): 57.00% '
             'against a silent 3.41%, divergence 57.40%. Menu, not play.',
    ),
    # ------------------------------------------------------------------
    # Kept deliberately, because it fails in the interesting way.
    # ------------------------------------------------------------------
    dict(
        name='thexder-key',
        disk='Thexder [b].d77',
        # A SPREAD, not a guess: Thexder's FM-7 start key is not documented
        # anywhere I could find, and each attempt costs a ~40-minute run.
        # Placed late because the title is still drawing its logo at f1450.
        keys=[(1600, '@SPACE'), (1900, '@RETURN'), (2200, '1'),
              (2500, '@F1'), (2800, '8'), (3100, '@UP')],
        shots=[1500, 2500, 3500],
        min_cov=20.0,
        note='6 strobes delivered, 0.000% divergence -- the keyboard reaches '
             'the hardware and the attract loop consumes none of it. NOT a '
             'core bug. Thexder also never touches PSG 14/15, so it can never '
             'be a joystick test.',
    ),
]

# NOT tests, and here so nobody adds them as ones:
#
#   Topple Zip  renders a full gameplay screen -- SCENE/MISSILE/MODE panels,
#               player craft, radar -- BIT-IDENTICALLY WITH NO INPUT. It is an
#               attract demo. It was written up here as a success on the
#               strength of that screenshot and 66.3% frame-to-frame change,
#               and the silent control is the only thing that disproved it.
#               This is the exact false positive the harness exists to catch,
#               and it caught its author twice (Thexder's 8.75% was the first).
#   Death Force the strongest joystick title by static scan (10 reads of
#               $fd0e), but it drew 0.00% through f2600 here. Cohort 08 scores
#               it 2.58% at f1980 as fm77av, so the machine routing or the
#               frame window is wrong -- diagnose before using it.
#   Space Harrier  static 1.99% text screen through f2600.


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
    # The second drive is part of the MEDIA, not part of the input, so it is
    # mounted for the control run too -- otherwise the comparison would be
    # measuring the extra disk rather than the keys.
    if t.get('disk1'):
        cmd += ['--disk1', os.path.join(DISK, t['disk1'])]
        if t.get('disk1_index'):
            cmd += ['--disk1-index', str(t['disk1_index'])]
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
        # Coverage of the LAST sample, not the first: "did it get somewhere"
        # is a question about where the run ended up. Front Line is 3.5% at its
        # first sample and 90.6% at its last.
        cov = stats(b[0], b[1], b[2])[0]
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
