#!/usr/bin/env bash
# Machine screen: is this disk FM-7 software or FM77AV software?
#
# The FM-7 collection is not curated by machine, so a cohort drawn from it will
# contain AV titles. Swept as an FM-7 one of those renders blank here while the
# reference renders noise, which scores CORE-BLANK and reads as a core bug --
# and BOTH-BLANK is worse, because nothing ever revisits that verdict. About a
# quarter of the set is AV software (docs/TESTING.md), so this is not a rare
# correction: 11 of cohort 03's 40 disks were AV, and re-running them on the
# right machine moved three from BOTH-BLANK to MATCH.
#
# The tell needs no eyeballs. An AV title run as an FM-7 touches registers the
# FM-7 does not decode, and the run summary lists them:
#
#   $FD80-$FD93   the AV MMR and its mode/bank registers
#   $FD30-$FD34   the analog palette
#   $FD12         the AV display mode
#
# 300 frames is enough -- a title reaches its own init long before it draws --
# so the whole cohort is minutes against hours for a re-sweep.
#
# Prints one line per disk: "av <path>" or "fm7 <path>". Usage, from sweep/:
#
#   export VSIM=$PWD/.. EXE=$PWD/../obj_dir/Vemu
#   tr '\n' '\0' < images.txt | xargs -0 -P8 -n1 ./probe.sh
#
# MUST run the binary from vsim/ -- rtl/rom.v does $readmemh on the relative
# path ./roms/..., and from anywhere else every ROM comes up empty as a WARNING,
# the machine runs away into $fdxx, and every disk screens identically. Same
# trap as sweep_one.sh's, and it would poison the screen rather than fail it.
set -uo pipefail
img="$1"
log=$(mktemp)
( cd "${VSIM:?set VSIM to the vsim directory}" &&
  "${EXE:-./obj_dir/Vemu}" --headless --bootrom 0 --machine fm7 --disk "$img" \
        --stop-at-frame 300 >"$log" 2>&1 )
ports=$(grep -m1 '^UNDECODED ports' "$log")
rm -f "$log"
# $FD8x/$FD9x, $FD3x and $FD12 as the summary prints them: bare two-hex-digit
# port numbers, either alone or as the low end of an "$xx-$yy" range.
if printf '%s' "$ports" | grep -qE '\$(8[0-9a-f]|9[0-3]|3[0-4]|12)\b'; then
  echo "av	$img"
else
  echo "fm7	$img"
fi
