#!/usr/bin/env bash
# Report the sub-system handshake state at the end of a run, one TSV row.
# Looking for the signature described in TODO.md P4-13: BUSY stuck at 1 with the
# sub NOT halted and almost no $d40a traffic, i.e. the sub never returned to its
# ROM idle loop and the main is hard-blocked polling $fd05 bit 7.
set -uo pipefail
img="$1"
base=$(basename "$img" .d77)
cd "$VSIM" || exit 1
log=$(mktemp)
"$EXE" --headless --bootrom 0 --disk "$img" --stop-at-frame 700 >"$log" 2>&1
hs=$(grep -E 'sub handshake' "$log")
d40a=$(grep -E '\$d40a access' "$log")
busy=$(echo "$hs" | grep -oE 'BUSY=[01]' | cut -d= -f2)
hac=$(echo "$hs" | grep -oE 'SHALTACn=[01]' | cut -d= -f2)
rd=$(echo "$d40a" | grep -oE '[0-9]+ reads' | grep -oE '^[0-9]+')
wr=$(echo "$d40a" | grep -oE '[0-9]+ writes' | grep -oE '^[0-9]+')
printf '%s\t%s\t%s\t%s\t%s\n' \
  "${busy:-?}" "${hac:-?}" "${rd:-0}" "${wr:-0}" "$base"
rm -f "$log"
