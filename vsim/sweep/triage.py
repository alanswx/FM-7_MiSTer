#!/usr/bin/env python3
"""Triage a sweep by instruction rate, per TODO.md P4-11/P4-12.

A screenshot cannot tell "crashed into a CWAI" from "idling at a screen it
already drew" from "running happily and choosing not to draw". main/frame can,
so the rate is the primary key and the PNG size is only a content proxy.

Healthy titles sit at 4400-5800 main/frame. A blank 640x200 screen compresses
to about 3790 bytes, so that is the floor, not zero.
"""
import collections
import hashlib
import os
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "sweep1/results.tsv"
SHOTS = os.path.join(os.path.dirname(PATH), "shots")

# Two screens are not "content" even though they are not blank, and both are
# common enough to swamp the buckets if they are not named:
#   - the cassette F-BASIC banner, i.e. the disk did not boot and the machine
#     fell through to ROM BASIC. Identical to vsim/shots/boot-basic.png.
#   - a completely blank raster.
# Identify them by hashing the PNG rather than by size, since size alone is a
# coincidence waiting to happen.
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REF = {}
for name, path in (
    ("F-BASIC banner (disk did not boot)",
     os.path.join(REPO, "vsim", "shots", "boot-basic.png")),
):
    try:
        REF[hashlib.sha1(open(path, "rb").read()).hexdigest()] = name
    except OSError:
        pass


def shot_hash(title):
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", title)
    p = os.path.join(SHOTS, safe + ".png")
    try:
        return hashlib.sha1(open(p, "rb").read()).hexdigest()
    except OSError:
        return None
BLANK = 4000          # PNG bytes: at or below this the screen is ~empty
RICH = 6000           # comfortably more than a few lines of text
LOW_RATE = 2500       # Arion crashed at 1087, Solitaire Royale at 1049
HEALTHY_LO = 4000

rows = []
with open(PATH) as f:
    header = f.readline()
    for line in f:
        p = line.rstrip("\n").split("\t")
        if len(p) < 6:
            continue
        try:
            rows.append((int(p[0]), int(p[1]), int(p[2]), int(p[3]), p[4], p[5]))
        except ValueError:
            continue


def bucket(main, sub, png, h):
    # The cassette F-BASIC banner -- "30530 Bytes Free / Ready" -- means the disk
    # did NOT boot and the machine fell through to ROM BASIC. It is by far the
    # most common outcome and it is not "partial content", so it gets its own
    # bucket. Exact hashing does not group these because the cursor blink phase
    # differs between runs, so this is a size band, spot-checked against the
    # actual screenshots (5197-5218 bytes, main 5350-5430, sub 9400-9600).
    if 5050 <= png <= 5350 and main > 4000:
        return "NO BOOT (fell back to cassette F-BASIC)"
    if main < LOW_RATE and png <= BLANK:
        return "CRASH (low rate, blank -- expect a CWAI in page zero)"
    if main < LOW_RATE:
        return "IDLE (low rate, but content on screen)"
    if png > RICH:
        return "RENDERS (healthy rate, rich screen)"
    if png > BLANK:
        return "PARTIAL (healthy rate, some content)"
    return "BLANK (healthy rate, drawing nothing)"


def is_av(title):
    """FM77AV software. A different machine -- MMR paging, the MB61VH010 drawing
    ALU, analog palette, 4096-colour mode, YM2203 -- none of which this core
    implements (TODO.md P5). Counting these as FM-7 failures is meaningless."""
    return "FM77AV" in title.upper()


ONLY = sys.argv[2] if len(sys.argv) > 2 else "fm7"
if ONLY == "fm7":
    rows = [r for r in rows if not is_av(r[5])]
elif ONLY == "av":
    rows = [r for r in rows if is_av(r[5])]

buckets = collections.defaultdict(list)
hashes = collections.Counter()
for main, sub, png, io, notes, title in rows:
    h = shot_hash(title)
    hashes[h] += 1
    buckets[bucket(main, sub, png, h)].append((png, main, sub, io, notes, title))

print(f"{len(rows)} images  (filter: {ONLY})\n")
order = ["RENDERS (healthy rate, rich screen)",
         "PARTIAL (healthy rate, some content)",
         "BLANK (healthy rate, drawing nothing)",
         "IDLE (low rate, but content on screen)",
         "CRASH (low rate, blank -- expect a CWAI in page zero)",
         "NO BOOT (fell back to cassette F-BASIC)"]
for b in order:
    items = sorted(buckets.get(b, []), reverse=True)
    print(f"== {b}: {len(items)}")
    for png, main, sub, io, notes, title in items[:40]:
        flag = "" if notes in ("-", "") else f"  [{notes.strip()}]"
        print(f"   {main:5d} {sub:5d} {png:7d}  {title}{flag}")
    if len(items) > 40:
        print(f"   ... and {len(items)-40} more")
    print()

# Identical screens, clustered. Far more informative than size alone: a large
# cluster is one shared outcome (blank raster, the cassette F-BASIC banner, a
# DOS prompt) reached by many titles, and one representative tells you which.
byhash = collections.defaultdict(list)
for main, sub, png, io, notes, title in rows:
    h = shot_hash(title)
    if h:
        byhash[h].append((png, title))
print("== identical-screen clusters (>=3 titles)")
for h, items in sorted(byhash.items(), key=lambda kv: -len(kv[1])):
    if len(items) < 3:
        continue
    label = REF.get(h, "")
    print(f"   {len(items):4d} titles  {items[0][0]:6d}B  "
          f"e.g. {items[0][1]}  {label}")
print()

bad = [r for r in rows if r[4] not in ("-", "")]
if bad:
    print(f"!! {len(bad)} rows carry harness flags (NOROM/RUNAWAY/SHORT-RUN)")
    for r in bad[:20]:
        print("   ", r[4].strip(), r[5])
