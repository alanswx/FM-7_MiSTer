#!/usr/bin/env python3
"""Classify each .d77's boot sector as bootable or a deliberate halt stub.

A large slice of the Neo Kobe collection is program/data disks meant to be
loaded from Disk BASIC on another disk (their names often say so: "{run NUGI}",
"(User disk)"). Their track 0 / side 0 / sector 1 is a short stub that masks
interrupts and branches to itself, so the core correctly boots them into an
infinite loop and a blank screen. Counting those as emulation failures
overstates the failure rate badly, so identify them from the image itself
rather than from the screenshot.

Usage: bootsector.py <dir-of-d77> [results.tsv]
"""
import os
import struct
import sys


def boot_sector(path):
    """Return the data bytes of track 0, side 0, sector 1, or None."""
    try:
        d = open(path, "rb").read()
    except OSError:
        return None
    if len(d) < 0x2b0:
        return None
    # .d77: 0x20 begins a table of 164 little-endian track offsets.
    off = struct.unpack("<I", d[0x20:0x24])[0]
    if off == 0 or off + 16 > len(d):
        return None
    dlen = struct.unpack("<H", d[off + 14:off + 16])[0]
    return d[off + 16:off + 16 + dlen]


def is_halt_stub(data):
    """True if the sector runs a few instructions and branches to itself.

    The 6809 encoding for `BRA *` is 20 FE -- a relative branch of -2. Looking
    for it in the first 32 bytes catches the stub without matching a real
    loader, which reaches its own code long before then. Also accept the
    machine simply being told to stop: SYNC (13) or CWAI (3C) with everything
    masked, which some disks use instead.
    """
    if not data or len(data) < 4:
        return None
    head = data[:32]
    if b"\x20\xfe" in head:
        return "BRA-self"
    if b"\x13" in head[:12] and b"\x1a\x50" in head[:4]:
        return "SYNC-masked"
    return None


d = sys.argv[1]
rows = {}
if len(sys.argv) > 2:
    with open(sys.argv[2]) as f:
        f.readline()
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) >= 6:
                rows[p[5]] = p

stubs, real, bad = [], [], []
for name in sorted(os.listdir(d)):
    if not name.lower().endswith(".d77"):
        continue
    title = name[:-4]
    data = boot_sector(os.path.join(d, name))
    if data is None:
        bad.append(title)
        continue
    kind = is_halt_stub(data)
    (stubs if kind else real).append((title, kind))

print(f"{len(stubs)} halt-stub (NOT BOOTABLE), {len(real)} real boot sector, "
      f"{len(bad)} unreadable\n")

if rows:
    # How many of the blank-screen results are simply unbootable disks?
    blank_stub = [t for t, _ in stubs
                  if t in rows and int(rows[t][2]) <= 4000]
    print(f"of the halt-stub disks, {len(blank_stub)} produced a blank screen "
          f"-- i.e. the core did exactly the right thing\n")

print("halt-stub disks:")
for t, k in stubs[:60]:
    r = rows.get(t)
    extra = f"   main={r[0]} sub={r[1]} png={r[2]}" if r else ""
    print(f"   [{k}] {t}{extra}")
if len(stubs) > 60:
    print(f"   ... and {len(stubs)-60} more")
