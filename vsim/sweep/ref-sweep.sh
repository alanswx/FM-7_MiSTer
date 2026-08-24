#!/usr/bin/env bash
#
# Render every image of a sweep on 77AVEMU, so each title has a reference
# picture to compare the core's own render against.
#
# A sweep on its own says "this title is blank". It cannot say whether that is
# our bug or a disk that boots for nobody -- and the AV set is full of data,
# scenario and save disks that were never bootable alone. The reference answers
# exactly that question, per title, without anyone having to know the title.
#
# Reads the SAME images.txt the sweep produced, so the two tables join on title
# and neither can drift into covering a different set.
#
#   ref-sweep.sh <sweep-outdir> [jobs] [steps] [--fm7]
#
# steps are 6809 instructions, not frames. 20,000,000 is about 22 s of machine
# time, which is past every title's loader in the set. The core's 2000-frame
# sweep is 33 s, so the reference is if anything given LESS time -- deliberately,
# so "the reference drew it and we did not" cannot be an artifact of letting the
# reference run longer.
#
# (Superseded claim, corrected: this used to add "the reference has no frame
# counter". It does -- vm->state.fm77avTime / FRAME_NS -- and the harness now
# takes --stop-at-frame. Instruction counts are still the right unit for a
# breadth sweep asking only "does this disk boot for anybody", because they cost
# a fixed amount of wall clock per title. They are the WRONG unit the moment a
# render is going to be scored against a vsim screenshot: those are different
# moments in a title, which is traps 42 and 49. For that, see
# vsim/sweep/ref-gate.py.)
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

OUT=${1:?usage: ref-sweep.sh <sweep-outdir> [jobs] [steps] [--fm7]}
JOBS=${2:-6}
STEPS=${3:-20000000}
FM7=${4:-}

REF=$REPO/refs/local/fm77av_headless
ROMS=$REPO/refs/local/fm77av-roms

[ -x "$REF" ] || { echo "no reference runner at $REF -- see tools/README-77AVEMU.md" >&2; exit 1; }
[ -d "$ROMS" ] || { echo "no reference ROM dir at $ROMS" >&2; exit 1; }
[ -f "$OUT/images.txt" ] || { echo "no $OUT/images.txt -- run the sweep first" >&2; exit 1; }

mkdir -p "$OUT/ref-shots" "$OUT/ref-logs"

one() {
    img=$1
    base=$(basename "$img" .d77)
    # sweep_one.sh's sanitiser, so the two tables join on the same key.
    san=$(echo "$base" | tr -c 'A-Za-z0-9._-' '_')
    png="$OUT/ref-shots/$san.png"
    log="$OUT/ref-logs/$san.log"
    [ -s "$png" ] && return 0
    # The reference prints a lot of archive-decompression noise on stdout; the
    # only lines worth keeping are its own REF/RESULT checkpoints.
    "$REF" "$ROMS" "$img" "$STEPS" "$png" $FM7 2>/dev/null \
        | grep -E '^(REF|RESULT)' > "$log"
}
export -f one
export OUT REF ROMS STEPS FM7

tr '\n' '\0' < "$OUT/images.txt" \
  | xargs -0 -P "$JOBS" -I{} bash -c 'one "$@"' _ {}

echo "done -> $OUT/ref-shots/" >&2
