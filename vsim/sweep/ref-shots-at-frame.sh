#!/usr/bin/env bash
#
# Render every title's 77AVEMU picture at the SAME MACHINE-TIME INSTANT as the
# core's canonical sweep shot, and write them where compare-ref.py expects.
#
# WHY THIS EXISTS. `ref-sweep.sh` renders by 6809 INSTRUCTION COUNT, and says so
# in its own header: that is the right unit for "does this disk boot for
# anybody", and the WRONG unit the moment the picture is scored against a vsim
# screenshot, because the two are different moments in a title (traps 42, 49).
# `compare-ref.py` scores exactly that way, so a sweep joined against
# `ref-sweep.sh` output silently mixes the two. Measured cost on the 68-title AV
# set: it reported 4 CORE-BLANK + 2 CORE-WORSE where the frame-matched score
# says 5 CORE-BLANK + 0 CORE-WORSE, and 22 MATCH where the truth is 27. Two of
# the six "actionable" rows -- How Many Robot and Gambler Jikochuushinha -- were
# the attract sequence photographed at different moments, not bugs.
#
#     ref-shots-at-frame.sh <sweep-outdir> [vsim-frame] [jobs]
#
# Default frame is the sweep's canonical SHOT (FRAMES - 20 = 1980 at the usual
# 2000). Writes <outdir>/ref-shots, so compare-ref.py picks it up unchanged;
# any existing ref-shots is moved aside to ref-shots-bystep.
#
# THE TWO FRAME UNITS ARE NOT THE SAME LENGTH -- a vsim frame is a real raster
# frame at 16 MHz / (1024 x 262) = 59.6374 Hz, a 77AVEMU frame is exactly 1/60 s
# of machine time, so reference_frame = round(vsim_frame * 1.00608).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

OUT=${1:?usage: ref-shots-at-frame.sh <sweep-outdir> [vsim-frame] [jobs]}
VFRAME=${2:-1980}
JOBS=${3:-6}
RFRAME=$(python3 -c "print(round($VFRAME * 60 * 1024 * 262 / 16000000))")

REF=$REPO/refs/local/fm77av_headless
ROMS=$REPO/refs/local/fm77av-roms
[ -x "$REF" ] || { echo "no reference runner at $REF -- see tools/README-77AVEMU.md" >&2; exit 1; }
[ -f "$OUT/images.txt" ] || { echo "no $OUT/images.txt -- run the sweep first" >&2; exit 1; }

DEST=$OUT/ref-shots-frame$VFRAME
mkdir -p "$DEST"
echo "vsim frame $VFRAME -> reference frame $RFRAME, $JOBS jobs"

render() {
  img="$1"; base=$(basename "$img" .d77)
  # safe-name rule copied VERBATIM from sweep_one.sh:9 so the two sets join on
  # filename. They differ if you retype it: '-' is KEPT.
  safe=$(echo "$base" | tr -c 'A-Za-z0-9._-' '_')
  out="$DEST/$safe.png"
  [ -f "$out" ] && return 0
  timeout 300 "$REF" "$ROMS" "$img" 800000000 "$out" --stop-at-frame "$RFRAME" >/dev/null 2>&1
}
export -f render; export DEST REF ROMS RFRAME
xargs -P "$JOBS" -I{} bash -c 'render "$@"' _ {} < "$OUT/images.txt"

n=$(ls "$DEST"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "rendered $n"
[ -d "$OUT/ref-shots" ] && [ ! -d "$OUT/ref-shots-bystep" ] && mv "$OUT/ref-shots" "$OUT/ref-shots-bystep"
rm -rf "$OUT/ref-shots"; cp -r "$DEST" "$OUT/ref-shots"
echo "-> $OUT/ref-shots  (compare-ref.py will use it; by-step set kept as ref-shots-bystep)"
