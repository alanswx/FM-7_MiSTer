#!/usr/bin/env bash
#
# Breadth sweep over the Neo Kobe floppy collection.
#
# Triage is by INSTRUCTION RATE, not by screenshot -- see TODO.md P4-11/P4-12.
# A screenshot cannot tell "crashed into a CWAI" from "idling at a screen it
# already drew" from "running happily and choosing not to draw"; main/frame can.
#
#   low rate  + blank   -> crash (expect a CWAI in page zero)
#   low rate  + content -> title idling at a screen it already finished
#   high rate + blank   -> executing fine, not drawing
#
# Usage: sweep.sh <outdir> [jobs] [frames]
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
ZIP=${ZIP:-"$REPO/software/Neo Kobe - Fujitsu FM-7 (2016-02-25).zip"}

OUT=${1:?usage: sweep.sh <outdir> [jobs] [frames]}
JOBS=${2:-10}
FRAMES=${3:-700}

export VSIM=$REPO/vsim
export EXE=$REPO/vsim/obj_dir/Vemu
export FRAMES
export SHOT=$((FRAMES - 20))
export SHOTS=$OUT/shots

DISKS=$OUT/disks
mkdir -p "$DISKS" "$SHOTS"

# ---------------------------------------------------------------- extract
# NOTE the bracket-free pattern. '[FD]' is a shell/unzip CHARACTER CLASS, so
# "*[FD]*.7z" silently matches entries containing an F or a D -- i.e. the wrong
# ones -- rather than the literal string "[FD]". This has burned this project
# before (TODO.md P4-9), so extract every .7z and filter by name afterwards.
if [ ! -f "$OUT/.extracted" ]; then
  echo "extracting archives..." >&2
  ( cd "$DISKS" && unzip -o -j -q "$ZIP" '*.7z' -d . )
  echo "keeping the [FD] floppy sets..." >&2
  ( cd "$DISKS" && for f in *.7z; do
      case "$f" in *"[FD]"*) ;; *) rm -f "$f" ;; esac
    done )
  echo "unpacking..." >&2
  ( cd "$DISKS" && for f in *.7z; do 7z x -y -o. "$f" >/dev/null 2>&1; done; rm -f ./*.7z )
  touch "$OUT/.extracted"
fi

find "$DISKS" -iname '*.d77' | sort > "$OUT/images.txt"
echo "$(wc -l < "$OUT/images.txt") disk images, $JOBS jobs, $FRAMES frames" >&2

printf 'MAIN_PF\tSUB_PF\tPNG\tIO\tNOTES\tTITLE\n' > "$OUT/results.tsv"
tr '\n' '\0' < "$OUT/images.txt" \
  | xargs -0 -P "$JOBS" -n 1 "$HERE/sweep_one.sh" \
  >> "$OUT/results.tsv"

echo "done -> $OUT/results.tsv" >&2
