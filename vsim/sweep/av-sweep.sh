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
JOBS=${2:-8}
FRAMES=${3:-700}
DISKDIR=${DISKDIR:-$REPO/software/D77}

export VSIM=$REPO/vsim
export EXE=$REPO/vsim/obj_dir/Vemu
export FRAMES
export SHOT=$((FRAMES - 20))
export SHOTS=$OUT/shots
export MACHINE=fm77av

mkdir -p "$SHOTS"

find "$DISKDIR" -maxdepth 1 -iname '*.d77' \
  | grep -i 'FM77AV' \
  | grep -viE '\[b\]|\[Alt|\[Set 1\]|AV40|User disk|Save disk|- Data|Disk B\)' \
  | sort > "$OUT/images.txt"

echo "$(wc -l < "$OUT/images.txt") FM77AV images, $JOBS jobs, $FRAMES frames" >&2

printf 'MAIN_PF\tSUB_PF\tPNG\tIO\tNOTES\tTITLE\n' > "$OUT/results.tsv"
tr '\n' '\0' < "$OUT/images.txt" \
  | xargs -0 -P "$JOBS" -n 1 "$HERE/sweep_one.sh" \
  >> "$OUT/results.tsv"

echo "done -> $OUT/results.tsv" >&2
