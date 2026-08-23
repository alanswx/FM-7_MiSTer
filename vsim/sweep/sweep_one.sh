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

# MACHINE selects the family. FM77AV titles will not boot as an FM-7 -- they
# need the initiator ROM and the AV memory map -- so sweeping them without it
# reports a uniform "nothing boots", which reads as a core failure rather than
# as the wrong switch.
# One run, several screenshots. $SHOTLIST is a spread of frames rather than a
# single moment -- see the comment on it in av-sweep.sh. The last entry is $SHOT,
# and that one is also copied to the canonical $safe.png so gallery.py and
# anything else expecting one image per title keeps working unchanged.
"$EXE" --headless --bootrom 0 --machine "${MACHINE:-fm7}" --disk "$img" \
       --stop-at-frame "$FRAMES" --screenshot "${SHOTLIST:-$SHOT}" \
       --screenshot-prefix "$SHOTS/$safe" >"$log" 2>&1
# Fall back to the latest sample that DID get written. A run that is cut short --
# by a timeout, or by a title that hangs -- otherwise leaves no canonical PNG at
# all, and the title silently vanishes from gallery.py and from any tool keyed on
# one image per title, which reads as "not swept" rather than "swept and stopped".
canon="$SHOTS/${safe}_frame_${SHOT}.png"
[ -f "$canon" ] || canon=$(ls "$SHOTS/${safe}_frame_"*.png 2>/dev/null | sort -t_ -k3 -n | tail -1)
[ -n "${canon:-}" ] && [ -f "$canon" ] && cp "$canon" "$png"

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
