#!/usr/bin/env bash
#
# Run a sweep over an EXPLICIT list of disk images instead of the whole Neo Kobe
# archive. Same row format and same shot naming as sweep.sh, so ref-shots-at-frame.sh,
# compare-ref.py, classify.py and gallery.py all work on the result unchanged.
#
# WHY THIS EXISTS. sweep.sh always extracts the archive into <outdir>/disks and
# sweeps everything it finds. That is right for the full run and wrong for a
# sample, a re-check of a handful of titles, or a bisect -- all of which want a
# fixed, reproducible list. Re-running the full sweep to look at 40 disks costs
# a day.
#
#     sweep-list.sh <outdir> [jobs] [frames]
#
# Reads <outdir>/images.txt, one absolute path per line. Writes <outdir>/shots
# and <outdir>/results.tsv exactly where the joining tools expect them.
#
# MACHINE is inherited, defaulting to fm7 in sweep_one.sh. Set MACHINE=av for
# FM77AV titles -- they will not boot as an FM-7 and sweeping them without it
# reports a uniform "nothing boots".
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

OUT=${1:?usage: sweep-list.sh <outdir> [jobs] [frames]}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
JOBS=${2:-8}
FRAMES=${3:-2000}

[ -f "$OUT/images.txt" ] || { echo "no $OUT/images.txt -- one disk path per line" >&2; exit 1; }

export VSIM=$REPO/vsim
export EXE=$REPO/vsim/obj_dir/Vemu
export FRAMES
export SHOT=$((FRAMES - 20))
export SHOTS=$OUT/shots
mkdir -p "$SHOTS"

[ -x "$EXE" ] || { echo "no simulator at $EXE -- build it in vsim/ first" >&2; exit 1; }

n=$(wc -l < "$OUT/images.txt" | tr -d ' ')
echo "$n disk images, $JOBS jobs, $FRAMES frames, machine ${MACHINE:-fm7}" >&2

# TIMEOUT is per title. A title that runs away can otherwise hold a slot for the
# whole sweep; the shots it did write are still there and compare-ref.py reports
# the row as NO-SHOT rather than silently as a blank.
TMO=${TIMEOUT:-2400}

printf 'MAIN_PF\tSUB_PF\tPNG\tIO\tNOTES\tTITLE\n' > "$OUT/results.tsv"
tr '\n' '\0' < "$OUT/images.txt" \
  | xargs -0 -P "$JOBS" -n 1 timeout "$TMO" "$HERE/sweep_one.sh" \
  >> "$OUT/results.tsv"

echo "-> $OUT/results.tsv ($(($(wc -l < "$OUT/results.tsv") - 1)) rows), $OUT/shots" >&2
