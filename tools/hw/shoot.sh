#!/usr/bin/env bash
# Screenshot whatever the MiSTer is showing and fetch it.  usage: shoot.sh <label>
set -u
MISTER=${MISTER:-192.168.1.75}
SP="$(cd "$(dirname "$0")" && pwd)"
OUT="$SP/shots"; mkdir -p "$OUT"
LABEL=$1

CORE=$(ssh -n -o BatchMode=yes root@$MISTER 'cat /tmp/CORENAME 2>/dev/null')
curl -s -m 20 -X POST "http://$MISTER:8182/api/screenshots" >/dev/null
sleep 3
NEW=$(ssh -n -o BatchMode=yes root@$MISTER "ls -t /media/fat/screenshots/$CORE/*.png 2>/dev/null | head -1")
[ -z "$NEW" ] && { echo "$LABEL: NO SCREENSHOT (core=$CORE)"; exit 2; }
ssh -n -o BatchMode=yes root@$MISTER "cat '$NEW'" > "$OUT/$LABEL.png" || exit 3
echo "$LABEL: core=$CORE $(stat -c%s "$OUT/$LABEL.png") bytes -> $OUT/$LABEL.png"
