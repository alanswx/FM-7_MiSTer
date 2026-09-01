#!/usr/bin/env python3
"""Render run_tests.sh's gate on 77AVEMU at the SAME instant as the core's shot.

`ref-sweep.sh` renders the reference by 6809 INSTRUCTION COUNT, so a reference
picture and a core picture are different moments in a title and cannot be
compared rigorously (docs/REFERENCE.md traps 42 and 49: that mismatch reported a
32-point improvement as a 9-point regression). This renders each blessed gate
row at the machine-time frame the core's blessed PNG was taken at, and writes
the result to vsim/shots-ref-77avemu/<test>.png -- the same test names
shots-ref/ uses, so the two sets join on filename.

    ref-gate.py [--frames 620] [--only substring] [--list]

THE TWO FRAME UNITS ARE NOT THE SAME LENGTH.

  vsim      a real raster frame off the core's video timing: 16 MHz over a
            1024 x 262 raster (sim_main.cpp:73) = 59.63740 Hz.
  77AVEMU   exactly 1/60 s of vm->state.fm77avTime.

  reference_frame = vsim_frame * 60 * 1024 * 262 / 16000000
                  = vsim_frame * 1.00608        (exact, not a rounded constant)

+6 frames per 1000. The gate's screenshot instant is SHOT_AT = FRAMES - 20 =
vsim frame 600, which is reference frame 604 -- NOT 624, which is where the
core's RUN stops, twenty frames after the picture was taken.

These renders are informational, not a gate. The two renderers disagree on
output geometry (77AVEMU line-doubles 640x200 to 640x400) and on the DAC
(trap 27), so a byte comparison is meaningless; `sweep/compare-ref.py` is the
tool that scores core against reference.
"""
import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))

# Needs a harness built from the CURRENT tools/77avemu_headless.cpp -- an older
# refs/local/fm77av_headless has no --stop-at-frame and will read the option as
# a positional. FM77AV_HEADLESS points at a freshly built one without having to
# overwrite the checked-out binary.
REF = os.environ.get('FM77AV_HEADLESS') or \
    os.path.join(REPO, 'refs', 'local', 'fm77av_headless')
ROMS = os.path.join(REPO, 'refs', 'local', 'fm77av-roms')
SOFT = os.path.join(REPO, 'software')
OUTDIR = os.path.join(REPO, 'vsim', 'shots-ref-77avemu')

# Exact, from the two definitions above. Kept as the ratio rather than as
# 1.00608 so nobody has to trust a typed constant.
VSIM_TO_REF = 60.0 * 1024.0 * 262.0 / 16000000.0


def rf(vsim_frame):
    """vsim frame -> the 77AVEMU frame at the same instant."""
    return int(round(vsim_frame * VSIM_TO_REF))


# --- keyboard -------------------------------------------------------------
# vsim's --key takes a STRING and expands it; 77AVEMU's takes one PHYSICAL key
# per option. Reproducing a row therefore means expanding the string here, with
# the same character->key choice sim_main.cpp:ascii_to_ps2 makes (JIS: '+' is
# shift-';', '"' is shift-'2', '!' is shift-'1') and the same schedule
# sim_main.cpp:schedule_key_action lays down.
LABEL = {
    ' ': ('MID_SPACE', False),
    '-': ('MINUS', False),
    '@': ('AT', False),
    ';': ('SEMICOLON', False),
    ':': ('COLON', False),
    ',': ('COMMA', False),
    '.': ('DOT', False),
    '/': ('SLASH', False),
    '^': ('HAT', False),
    '!': ('1', True),
    '"': ('2', True),
    '#': ('3', True),
    '$': ('4', True),
    '%': ('5', True),
    '&': ('6', True),
    "'": ('7', True),
    '(': ('8', True),
    ')': ('9', True),
    '=': ('MINUS', True),
    '+': ('SEMICOLON', True),
    '*': ('COLON', True),
}
for _c in '0123456789':
    LABEL[_c] = (_c, False)
for _c in 'abcdefghijklmnopqrstuvwxyz':
    LABEL[_c] = (_c.upper(), False)
    # sim_main.cpp sends an upper-case letter as SHIFT + the same key, so the
    # reference has to press SHIFT too or "HI!" arrives as "hi!".
    LABEL[_c.upper()] = (_c.upper(), True)

NAMED = {'RETURN': 'RETURN', 'SPACE': 'MID_SPACE', 'ESC': 'ESC',
         'BS': 'BACKSPACE', 'BACKSPACE': 'BACKSPACE', 'TAB': 'TAB',
         'UP': 'UP', 'DOWN': 'DOWN', 'LEFT': 'LEFT', 'RIGHT': 'RIGHT',
         'HOME': 'HOME', 'INS': 'INS', 'DEL': 'DEL', 'BREAK': 'BREAK'}


def key_args(start, hold, text):
    """One vsim --key action -> a list of 77AVEMU --key options.

    Presses and releases are placed at the vsim frames sim_main.cpp would use,
    then each is converted individually. Converting the press and the release
    separately (rather than scaling the hold) keeps both ends on the instant
    they belong to; at these hold lengths the two agree anyway.
    """
    out = []

    def emit(label, down, up):
        out.extend(['--key',
                    '%d:%s:%d' % (rf(down), label, max(1, rf(up) - rf(down)))])

    if text.startswith('@'):
        name = text[1:].upper()
        if name not in NAMED:
            raise SystemExit('ref-gate.py: no 77AVEMU label for @%s' % name)
        emit(NAMED[name], start, start + hold)
        return out

    f = start
    for ch in text:
        if ch not in LABEL:
            raise SystemExit('ref-gate.py: no 77AVEMU label for %r' % ch)
        label, shift = LABEL[ch]
        # vsim holds a real SHIFT scancode around the key; 77AVEMU takes the
        # modifier as a FLAG on the press instead, so the equivalent is a
        # SHIFT+ prefix. Pressing LEFT_SHIFT as its own key there types the
        # unshifted character and looks like a keyboard bug.
        emit(('SHIFT+' if shift else '') + label,
             f + (1 if shift else 0), f + hold)
        f += hold * 2
    return out


# --- the gate -------------------------------------------------------------
# Mirrors run_tests.sh's TESTS table. Key frames are derived from FRAMES there
# and are derived from FRAMES here, so the two stay in step.
def build_tests(frames):
    k1, k2, k3, k4 = frames // 2, frames * 5 // 8, frames * 3 // 4, frames * 7 // 8
    thexder = os.path.join(SOFT, 'D77', 'Thexder [b].d77')
    avdemo = os.path.join(SOFT, 'FM77AV', '2019_FM77AVDEMO_CaptainYS_V2.D77')
    d77 = os.path.join(SOFT, 'D77')

    t = []
    # name, media, fm7?, key actions as (frame, hold, text)
    t.append(('boot-basic', '', True, []))
    t.append(('basic-print', '', True,
              [(k1, 6, 'print 12-3'), (k3, 6, '@RETURN')]))
    t.append(('basic-keys', '', True,
              [(k1, 6, '@RETURN'), (k2, 6, 'list'), (k3, 6, '@RETURN')]))
    t.append(('basic-shift', '', True,
              [(k1, 3, 'print 12+34'), (k2, 3, '@RETURN'),
               (k3, 3, 'print "HI!"'), (k4, 3, '@RETURN')]))
    t.append(('disk-Thexder [b]', thexder, True, []))
    t.append(('av-demo', avdemo, False, []))
    t.append(('av-kohakuiro',
              os.path.join(d77, 'Kohakuiro no Yuigon (FM77AV) (Disk 1).d77'),
              False, []))
    t.append(('av-wizardry4',
              os.path.join(d77, 'Wizardry IV (FM77AV) (Disk A).d77'),
              False, []))
    t.append(('av-luxsor1',
              os.path.join(d77, 'Luxsor (FM77AV) (Disk 1).d77'),
              False, []))
    return t


# boot-dos1/2/3 are deliberately absent. They select one of the MiSTer core's
# three DOS boot ROM images through status[11:10]; 77AVEMU has a single
# BASIC-or-DOS switch and this harness does not expose even that, and the
# BOOT_DOS.ROM under refs/local/fm77av-roms is a 480-byte AV loader padded to
# 512 (tools/README-77AVEMU.md), which is not the FM-7 DOS boot ROM at all. A
# render from it would be a picture of the staging, not of the machine.
SKIPPED = ('boot-dos1', 'boot-dos2', 'boot-dos3')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--frames', type=int, default=620,
                    help="run_tests.sh's FRAMES (default 620)")
    ap.add_argument('--shot-at', type=int, default=None,
                    help='vsim frame the core screenshot is taken at '
                         '(default FRAMES-20, which is run_tests.sh SHOT_AT)')
    ap.add_argument('--only', default=None, help='substring filter on test name')
    ap.add_argument('--out', default=OUTDIR)
    ap.add_argument('--list', action='store_true',
                    help='print the commands instead of running them')
    a = ap.parse_args()

    shot_at = a.frames - 20 if a.shot_at is None else a.shot_at
    stop = rf(shot_at)

    if not a.list:
        for p in (REF, ROMS):
            if not os.path.exists(p):
                raise SystemExit('missing %s -- see tools/README-77AVEMU.md' % p)
        os.makedirs(a.out, exist_ok=True)

    print('vsim frame %d  ->  77AVEMU frame %d   (x %.6f)'
          % (shot_at, stop, VSIM_TO_REF), file=sys.stderr)

    rc = 0
    for name, media, fm7, keys in build_tests(a.frames):
        if a.only and a.only not in name:
            continue
        png = os.path.join(a.out, name + '.png')
        cmd = [REF, ROMS, media, '--stop-at-frame', str(stop), png]
        if fm7:
            cmd.append('--fm7')
        for f, hold, text in keys:
            cmd += key_args(f, hold, text)
        if a.list:
            print(' '.join("'%s'" % c if ' ' in c else c for c in cmd))
            continue
        if media and not os.path.exists(media):
            print('%-18s SKIP  no media: %s' % (name, media), file=sys.stderr)
            continue
        p = subprocess.run(cmd, capture_output=True, text=True)
        # An early stop means the screenshot is NOT at the requested instant.
        # Never let that pass as a reference render.
        warn = [l for l in p.stderr.splitlines() if l.startswith('WARNING')]
        result = [l for l in p.stdout.splitlines() if l.startswith('RESULT')]
        note = ' '.join(warn) if warn else (result[0] if result else '')
        ok = p.returncode == 0 and not warn and os.path.exists(png)
        if not ok:
            rc = 1
        print('%-18s %-5s %s' % (name, 'ok' if ok else 'FAIL', note),
              file=sys.stderr)

    for n in SKIPPED:
        print('%-18s skipped (see SKIPPED in this file)' % n, file=sys.stderr)
    return rc


if __name__ == '__main__':
    sys.exit(main())
