#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build the MiSTer core with Quartus 17.0.2 inside the raetro/quartus:mister
# container. Produces output_files/FM-7_MiSTer.rbf.
#
#   tools/quartus-build.sh              # full build: map, fit, asm, sta
#   tools/quartus-build.sh map          # analysis & synthesis only
#   tools/quartus-build.sh fit          # map + fit, for a resource check
#   tools/quartus-build.sh clean        # remove Quartus output
#
# IMPORTANT -- why this does not just run "quartus_sh --flow compile":
# The image is linux/amd64 and runs under emulation on Apple Silicon. The qsf
# sets NUM_PARALLEL_PROCESSORS ALL, and Quartus' parallel helper processes
# crash under emulation (they show up as <defunct> alongside [crashreporter]).
# The parent then deadlocks forever on named pipes from the dead helpers at
# ~0% CPU, which looks like a slow build but never finishes -- the give-away is
# a log file whose mtime stops advancing while `docker` sits at 0% CPU. Passing
# --parallel=1 to each stage avoids spawning them; a healthy build sits at
# ~100% CPU.
#
# Borrowed verbatim from the RCAStudioII_Mister core, which hit this first.
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${QUARTUS_IMAGE:-raetro/quartus:mister}"
PROJ=FM-7_MiSTer
STAGE="${1:-all}"

docker image inspect "$IMAGE" >/dev/null 2>&1 || {
    echo "error: docker image $IMAGE not found" >&2; exit 1; }

run() { docker run --rm --platform linux/amd64 -v "$ROOT":/build "$IMAGE" bash -c "cd /build && $1"; }

case "$STAGE" in
    clean) rm -rf "$ROOT"/output_files "$ROOT"/db "$ROOT"/incremental_db
           echo "cleaned"; exit 0 ;;
    map)   run "quartus_map --parallel=1 $PROJ" ;;
    fit)   run "quartus_map --parallel=1 $PROJ && \
                quartus_fit --parallel=1 $PROJ" ;;
    all)   run "quartus_map --parallel=1 $PROJ && \
                quartus_fit --parallel=1 $PROJ && \
                quartus_asm $PROJ && \
                quartus_sta $PROJ" ;;
    *)     echo "usage: $0 [all|map|fit|clean]" >&2; exit 1 ;;
esac

echo
if [[ -f "$ROOT/output_files/$PROJ.rbf" ]]; then
    ls -l "$ROOT/output_files/$PROJ.rbf" "$ROOT/output_files/$PROJ.sof" 2>/dev/null
fi
grep -hE "was successful|was unsuccessful" "$ROOT/output_files/$PROJ".{map,fit,asm,sta}.rpt 2>/dev/null || true
