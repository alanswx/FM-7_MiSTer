#!/usr/bin/env bash
# Run one disk image and emit one TSV row. Driven by sweep.sh via xargs -P.
# Kept as a standalone script rather than an exported shell function because
# macOS ships bash 3.2 and `export -f` + xargs is fragile across bash builds.
set -uo pipefail

img="$1"
base=$(basename "$img" .d77)
safe=$(echo "$base" | tr -c 'A-Za-z0-9._-' '_')
png="$SHOTS/$safe.png"
log=$(mktemp)

# MUST run from vsim/. The Verilog loads its ROMs with $readmem on the RELATIVE
# path ./roms/..., so from anywhere else every ROM silently comes up empty --
# Verilator prints "$readmem file not found" as a warning, not an error -- and
# the machine runs away into the $fdxx I/O window. The run still completes, still
# writes a screenshot, and still reports plausible-looking instruction counts
# (3355 main / 2923 sub for every title, blank 3790-byte PNG), so it reads as a
# uniform "nothing boots" result rather than as a broken harness.
cd "$VSIM" || exit 1

"$EXE" --headless --bootrom 0 --disk "$img" \
       --stop-at-frame "$FRAMES" --screenshot "$SHOT" \
       --screenshot-name "$png" >"$log" 2>&1

mainpf=$(grep -oE 'main 6809 *: [0-9]+ instructions  \([0-9]+ per frame\)' "$log" | grep -oE '\([0-9]+' | tr -d '(')
subpf=$(grep -oE 'sub 6809 *: [0-9]+ instructions  \([0-9]+ per frame\)' "$log" | grep -oE '\([0-9]+' | tr -d '(')
iocyc=$(grep -oE 'I/O cycles \(\$fdxx\): [0-9]+' "$log" | grep -oE '[0-9]+$')
frames=$(grep -oE '^frames  *: [0-9]+' "$log" | grep -oE '[0-9]+$')
if [ -f "$png" ]; then pngsz=$(stat -f %z "$png"); else pngsz=0; fi

# Guard rails. Both of these produce a complete, plausible-looking row when they
# fire, so they have to be reported as data rather than left to be noticed.
notes=""
grep -q 'readmem file not found' "$log" && notes="${notes}NOROM "
grep -q 'RUNAWAY' "$log"                && notes="${notes}RUNAWAY-INTO-IO "
[ "${frames:-0}" -lt "$FRAMES" ]        && notes="${notes}SHORT-RUN "

# One printf, so concurrent appends from xargs -P stay line-atomic.
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
   "${mainpf:-0}" "${subpf:-0}" "${pngsz:-0}" "${iocyc:-0}" "${notes:--}" "$base"
rm -f "$log"
