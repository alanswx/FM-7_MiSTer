#!/usr/bin/env bash
#
# Headless regression sweep.
#
# The FM-7 has no cartridge library to sweep, so the fixed tests below cover the
# four boot ROM selections and a couple of keyboard/BASIC round trips.
#
# Any .t77 in $TAPEDIR (default ../software) is added as a load test, but those
# are NOT part of the default sweep -- a tape plays in real time, so a single
# 240 KB image is a few thousand frames and minutes of wall clock. Run them
# explicitly:  ./run_tests.sh tape
#
# Each test prints its liveness counters. The counters are the point -- a
# screenshot alone cannot tell "F-BASIC prompt, as designed" apart from "CPU
# wedged with a prompt left in VRAM".
#
# THIS SCRIPT NOW JUDGES ITSELF. It used to print a table and tell you to run
# `cp -r shots shots-ref` by hand, and it compared nothing: `fail` was set only
# by NO-KEYSTROKE and NO-SCREENSHOT, so a change that altered every pixel of
# every screen still exited 0. Worse, the reference it pointed at went stale --
# by the time this was noticed shots-ref/ was three months behind the core and
# read as "8 failures" that were all intentional improvements.
#
# Both halves are now compared against $REF (default shots-ref/):
#
#   * the SCREENSHOT, byte for byte
#   * the COUNTERS -- frames, main/frame, sub/frame, I/O cycles -- exactly.
#     The sim is deterministic, so these do not drift on their own; if one
#     moves, something in the RTL moved it. The delta is printed so you can see
#     how far.
#
# A test with no reference is reported `new` and does not fail the run, so
# dropping a new .d77 into ../software does not break the suite.
#
# When a change is intentional, bless it:
#
#   BLESS=1 ./run_tests.sh          # update screenshots AND counters
#
# Blessing is the moment to record WHY in TODO.md -- a blessed reference with
# no matching note is indistinguishable from an unnoticed regression later.
#
# Usage:
#   ./run_tests.sh                 # every test
#   ./run_tests.sh basic tape      # only tests matching these substrings
#   FRAMES=1200 ./run_tests.sh     # run longer
#   BLESS=1 ./run_tests.sh         # accept current behaviour as the reference
#   REF=other-ref ./run_tests.sh   # compare against a different reference dir
#
set -uo pipefail
cd "$(dirname "$0")"

EXE=./obj_dir/Vemu
OUT=shots
REF=${REF:-shots-ref}
BLESS=${BLESS:-0}
TAPEDIR=${TAPEDIR:-../software}
FRAMES=${FRAMES:-620}
SHOT_AT=${SHOT_AT:-$((FRAMES - 20))}

# The counter reference lives beside the screenshots so the two cannot drift
# apart: one `cp -r`, or one BLESS run, moves both together.
COUNTERS="$REF/counters.tsv"

[ -x "$EXE" ] || { echo "Build first: make"; exit 1; }
mkdir -p "$OUT"
[ "$BLESS" = 1 ] && mkdir -p "$REF"

# Counters are only comparable at the frame count they were recorded at, so key
# the reference on FRAMES. Running FRAMES=1200 against a 620-frame reference
# compares nothing rather than reporting eight bogus failures.
ref_lookup() {   # $1 = test name -> "frames mainpf subpf iocyc" or empty
  [ -f "$COUNTERS" ] || return 0
  awk -F'\t' -v n="$1" -v f="$FRAMES" \
    '$1==n && $2==f { print $2, $3, $4, $5; exit }' "$COUNTERS"
}

# Key frames are derived from FRAMES rather than hardcoded, so a short
# FRAMES=200 smoke run still exercises the keyboard instead of stopping before
# the keys are due and reporting a spurious NO-KEYSTROKE.
#
# They are also deliberately late and repeated. The FM-7 boot ROM scans for
# extension ROMs before handing over to F-BASIC, and how long that takes moves
# whenever the clock dividers in rtl/clocks.svh change -- so a key pressed at
# one fixed frame can miss for reasons that have nothing to do with the change
# under test.
K1=$((FRAMES / 2))
K2=$((FRAMES * 5 / 8))
K3=$((FRAMES * 3 / 4))
K4=$((FRAMES * 7 / 8))

# name|extra args
TESTS=(
  "boot-basic|--bootrom 0"
  "boot-dos1|--bootrom 1"
  "boot-dos2|--bootrom 2"
  "boot-dos3|--bootrom 3"
  # Deliberately shift-free: '-' needs no modifier, so this row still passes
  # even if the shift tables regress, which keeps it independent of basic-shift
  # below. (It was originally written this way because KEYBOARD.v had no shift
  # tables at all -- P2-1 has since added them.) Should print 9.
  "basic-print|--bootrom 0 --key '$K1:print 12-3' --key '$K3:@RETURN'"
  "basic-keys|--bootrom 0 --key '$K1:@RETURN' --key '$K2:list' --key '$K3:@RETURN'"
  # Exercises the SHIFT table: '+' is shift-';' and '"' is shift-2 on JIS.
  # Expect "print 12+34" -> " 46", then "print \"HI!\"" -> "HI!".
  #
  # --key-hold 3 matters here: each character costs 2*hold frames, so at the
  # default hold of 6 an 11-character line takes 132 frames and runs past the
  # next key slot, and the @RETURN lands mid-line and splits it.
  "basic-shift|--bootrom 0 --key-hold 3 --key '$K1:print 12+34' --key '$K2:@RETURN' --key '$K3:print \"HI!\"' --key '$K4:@RETURN'"
)

# One entry per loose .d77 found under $DISKDIR. These ARE part of the default
# sweep: the mount-time scan is a few frames, not the thousands a tape takes.
#
# Note --bootrom 0, not 1. Bank 0 of the boot ROM is the one that loads a boot
# sector at $0100, which is what real disks require; the image currently wired
# to settings 1-3 loads at $0300 and no disk can boot from it. See TODO.md
# P3-6b.
#
# The scan itself is what to watch. `make DEBUG_FDC=1` makes rtl/wd1793.sv print
# one line per sector it puts in the table, which is how the parse was checked
# against a reference decode of the same file (TODO.md P4-1).
#
# Two guards, both added when a ~570-image collection landed in software/ and
# turned this gate into a six-hour sweep:
#
#  * `software/FM77AV/` is skipped -- the AV demo above already runs it, in AV
#    mode, and running it again with --bootrom 0 tests nothing.
#  * By default only disks that already have a blessed screenshot in $REF are
#    run, so the gate stays a gate. `ALLDISKS=1` runs every image found, which
#    is what you want when adding titles; for a whole collection use
#    `vsim/sweep/sweep.sh`, which is built for that and parallelises.
#  * A test name is the disk's BASENAME, and the reference set is keyed on it,
#    so two images with the same file name in different directories would run
#    as one test name and compare against one reference -- the second silently
#    overwriting the first's screenshot. Collections do contain such pairs
#    (`Thexder [b].d77` arrived a second time under software/D77/). Keep the
#    first and say which ones were dropped; do not drop them silently.
DISKDIR=${DISKDIR:-../software}
ALLDISKS=${ALLDISKS:-0}
disk_seen=""
disk_dupes=()
if [ -d "$DISKDIR" ]; then
  while IFS= read -r d; do
    case "$d" in */FM77AV/*) continue ;; esac
    base=$(basename "$d"); base=${base%.*}
    case "$disk_seen" in *"|$base|"*) disk_dupes+=("$d"); continue ;; esac
    disk_seen="$disk_seen|$base|"
    if [ "$ALLDISKS" != 1 ] && [ ! -f "$REF/disk-$base.png" ]; then continue; fi
    TESTS+=("disk-$base|--bootrom 0 --disk '$d'")
  done < <(find "$DISKDIR" -maxdepth 3 -iname '*.d77' | sort)
fi
if [ ${#disk_dupes[@]} -gt 0 ]; then
  echo "note: skipped ${#disk_dupes[@]} disk(s) whose basename was already taken:"
  for d in "${disk_dupes[@]}"; do echo "      $d"; done
fi

# FM77AV coverage. The suite had none until the AV video path was finished, and
# that is precisely why a broken $D430 page select and a missing drawing ALU
# both survived: nothing in CI ever rendered an AV frame. CaptainYS's 2019 demo
# is the sharpest single check available -- by the shot frame it has programmed
# all 4096 palette entries, filled all twelve 320-mode bit planes through the
# main CPU's MMR aperture, driven $D430/$D410 from the main CPU while the sub
# CPU is halted, and started drawing text through the drawing ALU. A blank or
# vertically-barred screenshot means one of those is broken.
#
# The image lives under the gitignored refs/ tree, so this test is present only
# for people who have the reference emulator checked out, exactly like the disk
# and tape groups above. Its absence is silent, not a failure.
AVDISK=${AVDISK:-../software/FM77AV/2019_FM77AVDEMO_CaptainYS_V2.D77}
if [ -f "$AVDISK" ]; then
  TESTS+=("av-demo|--machine fm77av --disk '$AVDISK'")
fi

# Curated AV titles. Chosen from the 68-image breadth sweep (see
# vsim/sweep/av-sweep.sh and docs/TESTING.md) on two criteria: they render real
# graphics, and they render the SAME thing at 700 and 2000 frames. The second
# one matters -- most AV titles are still drawing at the gate's frame count, and
# a reference blessed mid-draw would fail on any timing change for no reason.
#
#   Kohakuiro no Yuigon  81% coverage, 18 colours -- the strongest exercise of
#                        the 320-mode plane path outside the demo
#   Wizardry IV          colour sprites over text, a different draw path
#
# Deliberately NOT here: Tetris, which renders its title screen but goes from
# 21% to 57% coverage between 700 and 2000 frames, so it is mid-draw at the
# gate's 620. It belongs in the sweep, not the gate.
# Short test names on purpose: the name becomes the reference file name, and
# "av-Kohakuiro no Yuigon (FM77AV) (Disk 1).png" is a poor thing to have in git.
AVTITLES=${AVTITLES:-../software/D77}
av_add() {   # <short-name> <disk basename>
  [ -f "$AVTITLES/$2.d77" ] && TESTS+=("$1|--machine fm77av --disk '$AVTITLES/$2.d77'")
}
av_add av-kohakuiro "Kohakuiro no Yuigon (FM77AV) (Disk 1)"
av_add av-wizardry4 "Wizardry IV (FM77AV) (Disk A)"

# One entry per tape image found. Types LOAD"" + RETURN, which is what F-BASIC
# needs before it will start the motor -- t77_decode.v only advances while
# PERIPHERAL.v has the motor relay on.
if [ -d "$TAPEDIR" ]; then
  for t in "$TAPEDIR"/*.t77 "$TAPEDIR"/*.T77; do
    [ -f "$t" ] || continue
    base=$(basename "$t"); base=${base%.*}
    TESTS+=("tape-$base|--bootrom 0 --tape '$t' --key-hold 3 --key '320:load\"\"' --key '420:@RETURN'")
  done
fi

filter=("$@")
matches() {
  # Tape tests are opt-in: they run in real time and dominate the sweep.
  if [ ${#filter[@]} -eq 0 ]; then
    case "$1" in tape-*) return 1 ;; *) return 0 ;; esac
  fi
  for f in "${filter[@]}"; do [[ "$1" == *"$f"* ]] && return 0; done
  return 1
}

printf "%-20s %7s %10s %10s %9s  %-9s %s\n" \
       TEST FRAMES MAIN/frame SUB/frame IO-CYCLES VS-REF NOTES
printf -- "-------------------------------------------------------------------------------------------\n"

fail=0
diffs=0
newly=0
blessed_rows=()
for entry in "${TESTS[@]}"; do
  IFS='|' read -r name extra <<< "$entry"
  matches "$name" || continue

  log=$(mktemp)
  # `extra` carries quoted arguments (a --key value contains spaces), so build a
  # real argv array from it rather than relying on word splitting -- that used to
  # chop "--key 300:print 12-3" into "--key" "300:print" "12-3" and silently drop
  # everything after the space.
  eval "args=($extra)"
  "$EXE" --headless "${args[@]}" \
         --screenshot-name "$OUT/$name.png" --screenshot "$SHOT_AT" \
         --stop-at-frame "$FRAMES" >"$log" 2>&1

  frames=$(grep -oE '^frames  *: [0-9]+' "$log" | grep -oE '[0-9]+$')
  mainpf=$(grep -oE 'main 6809 *: [0-9]+ instructions  \([0-9]+ per frame\)' "$log" | grep -oE '\([0-9]+' | tr -d '(')
  subpf=$(grep -oE 'sub 6809 *: [0-9]+ instructions  \([0-9]+ per frame\)' "$log" | grep -oE '\([0-9]+' | tr -d '(')
  iocyc=$(grep -oE 'I/O cycles \(\$fdxx\): [0-9]+' "$log" | grep -oE '[0-9]+$')
  runaway=$(grep -c 'RUNAWAY' "$log")
  strobes=$(grep -oE 'keyboard  *: [0-9]+ strobes' "$log" | grep -oE '[0-9]+')

  notes=""
  # A 6809 at 1.2 MHz retires very roughly 5000 instructions per 60 Hz frame.
  # An order of magnitude below that means it is not running code.
  [ "${mainpf:-0}" -lt 500 ] && notes="MAIN-STALLED"
  [ "${subpf:-0}" -lt 500 ]  && notes="$notes SUB-STALLED"
  [ "${runaway:-0}" -gt 0 ]  && notes="$notes RUNAWAY-INTO-IO"
  case "$name" in
    basic-print|basic-keys)
      [ "${strobes:-0}" -eq 0 ] && { notes="$notes NO-KEYSTROKE"; fail=1; } ;;
  esac
  [ -f "$OUT/$name.png" ] || { notes="$notes NO-SCREENSHOT"; fail=1; }

  # ---- compare against the reference -------------------------------------
  # Two independent checks. A change can move the counters while leaving the
  # screen identical (an extra interrupt firing) or repaint the screen without
  # touching the rates, so neither subsumes the other and both are reported.
  vs="ok"
  refline=$(ref_lookup "$name")

  if [ -f "$REF/$name.png" ]; then
    cmp -s "$OUT/$name.png" "$REF/$name.png" || { vs="SCREEN"; diffs=1; }
  else
    vs="new"; newly=1
  fi

  if [ -n "$refline" ]; then
    read -r r_fr r_main r_sub r_io <<< "$refline"
    cdelta=""
    [ "${mainpf:-?}" != "$r_main" ] && cdelta="$cdelta main:$r_main->${mainpf:-?}"
    [ "${subpf:-?}"  != "$r_sub"  ] && cdelta="$cdelta sub:$r_sub->${subpf:-?}"
    [ "${iocyc:-?}"  != "$r_io"   ] && cdelta="$cdelta io:$r_io->${iocyc:-?}"
    if [ -n "$cdelta" ]; then
      [ "$vs" = "SCREEN" ] && vs="SCREEN+CNT" || vs="COUNTERS"
      notes="$notes$cdelta"
      diffs=1
    fi
  elif [ "$vs" = "ok" ]; then
    vs="new"; newly=1     # screenshot matched but no counter reference yet
  fi

  # Key on the REQUESTED frame count ($FRAMES), not the reported one. The sim
  # reports 621 for --stop-at-frame 620 (it counts the frame it stops on), and
  # keying the row on 621 while ref_lookup() searches for 620 made every test
  # report `new` against a reference that was sitting right there.
  blessed_rows+=("$(printf '%s\t%s\t%s\t%s\t%s' \
      "$name" "$FRAMES" "${mainpf:-0}" "${subpf:-0}" "${iocyc:-0}")")

  printf "%-20s %7s %10s %10s %9s  %-9s %s\n" \
     "$name" "${frames:-?}" "${mainpf:-?}" "${subpf:-?}" "${iocyc:-?}" "$vs" "$notes"
  rm -f "$log"
done

echo
if [ "$BLESS" = 1 ]; then
  # Only the tests that actually ran are blessed; a filtered run must not
  # silently drop the reference for everything it skipped.
  tmp=$(mktemp)
  [ -f "$COUNTERS" ] && cat "$COUNTERS" > "$tmp"
  for row in "${blessed_rows[@]}"; do
    nm=${row%%$'\t'*}
    fr=$(printf '%s' "$row" | cut -f2)
    # awk, not `grep -P`: BSD grep on macOS has no -P, and the names contain
    # regex metacharacters ("Thexder [b]") that a plain grep would misread.
    awk -F'\t' -v n="$nm" -v f="$fr" '!($1==n && $2==f)' "$tmp" > "$tmp.new"
    mv "$tmp.new" "$tmp"
    printf '%s\n' "$row" >> "$tmp"
  done
  mkdir -p "$REF"
  sort -o "$COUNTERS" "$tmp"; rm -f "$tmp"
  for row in "${blessed_rows[@]}"; do
    nm=${row%%$'\t'*}
    [ -f "$OUT/$nm.png" ] && cp "$OUT/$nm.png" "$REF/$nm.png"
  done
  echo "BLESSED ${#blessed_rows[@]} test(s) into $REF/ (screenshots + counters.tsv)."
  echo "Record why in TODO.md -- an unexplained bless reads as a missed regression later."
  exit 0
fi

if [ "$diffs" = 1 ]; then
  echo "REGRESSION: at least one test differs from $REF/."
  echo "If the change is intentional:  BLESS=1 ./run_tests.sh"
  fail=1
elif [ "$newly" = 1 ]; then
  echo "Some tests have no reference yet (marked 'new'). BLESS=1 ./run_tests.sh to record them."
  echo "All tests that DO have a reference match it."
else
  echo "All tests match $REF/ (screenshots and counters)."
fi
exit $fail
