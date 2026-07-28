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
# Output goes to shots/. Compare against shots-ref/ after making a change:
#   ./run_tests.sh && cp -r shots shots-ref
#
# Usage:
#   ./run_tests.sh                 # every test
#   ./run_tests.sh basic tape      # only tests matching these substrings
#   FRAMES=1200 ./run_tests.sh     # run longer
#
set -uo pipefail
cd "$(dirname "$0")"

EXE=./obj_dir/Vemu
OUT=shots
TAPEDIR=${TAPEDIR:-../software}
FRAMES=${FRAMES:-620}
SHOT_AT=${SHOT_AT:-$((FRAMES - 20))}

[ -x "$EXE" ] || { echo "Build first: make"; exit 1; }
mkdir -p "$OUT"

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
  # '-' is one of the few operators that needs no shift, and KEYBOARD.v has
  # no shift tables yet (P2-1), so use it: this should print 9.
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
DISKDIR=${DISKDIR:-../software}
if [ -d "$DISKDIR" ]; then
  while IFS= read -r d; do
    base=$(basename "$d"); base=${base%.*}
    TESTS+=("disk-$base|--bootrom 0 --disk '$d'")
  done < <(find "$DISKDIR" -maxdepth 3 -iname '*.d77' | sort)
fi

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

printf "%-20s %7s %10s %10s %9s  %s\n" TEST FRAMES MAIN/frame SUB/frame IO-CYCLES NOTES
printf -- "---------------------------------------------------------------------------------\n"

fail=0
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

  printf "%-20s %7s %10s %10s %9s  %s\n" \
     "$name" "${frames:-?}" "${mainpf:-?}" "${subpf:-?}" "${iocyc:-?}" "$notes"
  rm -f "$log"
done

echo
echo "Screenshots in $OUT/. To set a reference: cp -r $OUT shots-ref"
exit $fail
