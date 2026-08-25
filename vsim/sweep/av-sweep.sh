#!/usr/bin/env bash
#
# Breadth sweep over the FM77AV titles in the local collection.
#
# The AV set is identified by "(FM77AV)" in the file name, which is how the
# collection marks the AV releases of titles that also shipped for the FM-7 --
# Ys, Silpheed, Dragon Buster and so on exist as both, and the AV disk will not
# boot as an FM-7.
#
# Excluded, following the rules in docs/TESTING.md:
#   [b]        known-bad dumps
#   [Alt / [Set   duplicate dumps of the same title
#   AV40 / AV40SX  later machines this core does not model
#   data, user and save disks, which were never bootable
#
# Triage is the same as the FM-7 sweep: instruction rate first, screenshot
# second. See sweep.sh.
#
# Usage: av-sweep.sh <outdir> [jobs] [frames]
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

OUT=${1:?usage: av-sweep.sh <outdir> [jobs] [frames]}

# Make OUT absolute BEFORE anything uses it.
#
# sweep_one.sh has to run from vsim/ -- the Verilog loads its ROMs with
# $readmem on the relative path ./roms/..., and from anywhere else every ROM
# silently comes up empty. So a relative OUT resolves against vsim/ inside the
# worker and against vsim/sweep/ out here, and the two disagree: the TSV lands
# in one place while every --screenshot-prefix write vanishes into a directory
# that does not exist. The run still completes and still reports plausible
# instruction counts, with PNG=0 on every row -- which reads as "the core drew
# nothing" rather than "the sweep wrote nothing". Cost 16 minutes of a 68-title
# run before anyone looked at the PNG column.
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
JOBS=${2:-8}
FRAMES=${3:-700}
DISKDIR=${DISKDIR:-$REPO/software/D77}

export VSIM=$REPO/vsim
export EXE=$REPO/vsim/obj_dir/Vemu
export FRAMES
export SHOT=$((FRAMES - 20))

# Sample the run at SEVERAL points, not one.
#
# The reference renders every blessed shot at a fixed 20,000,000 6809 steps
# (~22 s of machine time) while this sweep samples at a fixed frame (2000 =
# 33 s). Those are different moments, and they only ever agreed by accident:
# while this core clocked its AV main CPU at the FM-8 rate it did roughly 22 s
# of work in 33 s of frames. `6a7030e` fixed the clock and the coincidence went
# with it -- suddenly a third of the set "regressed", and almost none of it had.
#
# Sampling the same run at a spread of frames costs nothing (one extra PNG write
# each, no extra emulation) and lets score.py take the best match instead of
# whichever moment the reference happens to be frozen at. Ys II is the case that
# makes the point: the reference is still on a near-blank loading screen at 20M
# steps, and a faster, more correct core has moved past it to the real artwork.
export SHOTLIST=$((FRAMES*55/100)),$((FRAMES*70/100)),$((FRAMES*85/100)),$SHOT
export SHOTS=$OUT/shots
export MACHINE=fm77av

mkdir -p "$SHOTS"

find "$DISKDIR" -maxdepth 1 -iname '*.d77' \
  | grep -i 'FM77AV' \
  | grep -viE '\[b\]|\[Alt|\[Set 1\]|AV40|User disk|Save disk|- Data|Disk B\)' \
  | sort > "$OUT/images.txt"

# DRAWN_ONLY=1 keeps only the titles 77AVEMU itself renders.
#
# Half the AV set is blank on BOTH machines -- 32 of 67 -- and those rows cost
# the same 2000 frames as any other while telling you almost nothing: two blank
# screens agree on 100% of their pixels whatever changes underneath them. For
# the common case, "did this change regress the set", they are dead weight and
# roughly half the wall clock.
#
# They are NOT worthless, which is why this is a switch and not a deletion. A
# title that is blank on both sides is exactly where a new win appears: World
# Golf II disk 1 sat blank-on-blank until `c2fc867` made this core draw its full
# title screen, and a drawn-only sweep would never have shown it. Run the full
# set after a fix that could plausibly unblank something, and drawn-only while
# iterating.
if [ "${DRAWN_ONLY:-0}" = 1 ]; then
  python3 "$HERE/drawn_only.py" "$OUT/images.txt" "$HERE/renders/ref-shots" > "$OUT/images.drawn" \
    && mv "$OUT/images.drawn" "$OUT/images.txt"
fi

echo "$(wc -l < "$OUT/images.txt") FM77AV images, $JOBS jobs, $FRAMES frames" >&2

printf 'MAIN_PF\tSUB_PF\tPNG\tIO\tNOTES\tTITLE\n' > "$OUT/results.tsv"
tr '\n' '\0' < "$OUT/images.txt" \
  | xargs -0 -P "$JOBS" -n 1 "$HERE/sweep_one.sh" \
  >> "$OUT/results.tsv"

echo "done -> $OUT/results.tsv" >&2
