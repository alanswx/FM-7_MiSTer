#!/usr/bin/env bash
# Capture the OSD through the HDMI capture card. Discards ~40 warmup frames:
# the MiraBox emits black until it syncs, which reads as "nothing on screen".
SP="$(cd "$(dirname "$0")" && pwd)"
timeout 60 ffmpeg -hide_banner -loglevel error -f v4l2 -i /dev/video4 \
    -vf "select=gte(n\,40)" -frames:v 1 -y "$SP/shots/$1.png" 2>/dev/null
echo "$1: $(stat -c%s "$SP/shots/$1.png" 2>/dev/null)b"
