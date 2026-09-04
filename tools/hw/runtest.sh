#!/usr/bin/env bash
# One hardware test: load an MGL, optionally switch the machine to FM77AV,
# let it settle, screenshot.  usage: runtest.sh <label> <mgl-name> [av] [settle]
#
# Trap 5 applies: do NOT insert an OSD capture between the toggle and the
# reset -- the 10-60 s it costs has produced false failures before.
set -u
MISTER=${MISTER:-192.168.1.75}
SP="$(cd "$(dirname "$0")" && pwd)"
LABEL=$1; MGL=$2; MODE=${3:-fm7}; SETTLE=${4:-25}

ssh -n -o BatchMode=yes root@$MISTER \
    "echo 'load_core /media/fat/games/fm-7/_hwtest/$MGL' > /dev/MiSTer_cmd"
sleep 8
if [ "$MODE" = "av" ]; then
    python3 "$SP/avtoggle.py" >/dev/null || { echo "$LABEL: OSD TOGGLE FAILED"; exit 1; }
fi
sleep "$SETTLE"
"$SP/shoot.sh" "$LABEL"
