#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
log=$(mktemp)
trap 'rm -f "$log"' EXIT

./obj_dir/Vemu --headless --machine fm77av --stop-at-frame 1 >"$log" 2>&1
cat "$log"

awk '
  /^frames[[:space:]]*:/ { frames=$3+0 }
  /^main 6809[[:space:]]*:/ { main=$4+0 }
  /^sub 6809[[:space:]]*:/ { subinstr=$4+0 }
  END {
    if (frames < 1 || main < 500 || subinstr < 500) exit 1
  }
' "$log"

echo "FM77AV BOOT TEST PASS"
