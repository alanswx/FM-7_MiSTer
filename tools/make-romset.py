#!/usr/bin/env python3
"""Build a system ROM set file (boot1.rom) for the FM-7 core.

The core pages one set out of SDRAM into block RAM at reset; rtl/ROMLOAD.v
reads it with the layout below and docs/ROMSETS.md documents it for users.
All three have to agree, so the offsets live here as one table.

  offset   size    ROM    what
  $00000   32768   m151   main ROM / F-BASIC        ($8000-$FBFF, 31744 used)
  $08000    2048   m152   boot ROM, 4 banks of 512
  $08800    2048   m153   character generator
  $09000    8192   m154   sub-system monitor
                          -- 45056 bytes, padded to a 65536-byte stride

Usage:
  tools/make-romset.py -o releases/boot1.rom \\
      --set fbasic300.rom,TL11_11_M152.rom,subsys_m153.rom,subsys_m154.rom \\
      --set secoinsa_fbasic.rom,TL11_11_M152.rom,secoinsa_cg.rom,subsys_m154.rom

Each --set is four comma-separated paths in m151,m152,m153,m154 order,
resolved against --romdir (default rtl/roms). A short file is padded with
$FF; a long one is an error rather than a silent truncation.
"""
import argparse, os, re, sys

STRIDE = 0x10000
REGIONS = [("m151", 0x00000, 32768),
           ("m152", 0x08000,  2048),
           ("m153", 0x08800,  2048),
           ("m154", 0x09000,  8192)]

def load(path):
    """Read a ROM image. Accepts a raw binary or a `.mem` file -- the hex-text
    form $readmemh eats, one byte per line -- because rtl/roms/ carries some
    ROMs only in that form (subsys_m153/m154 are split out of subsys_c.rom as
    .mem and never existed as separate binaries)."""
    raw = open(path, "rb").read()
    if path.endswith(".mem") or path.endswith(".hex"):
        txt = raw.decode("ascii", "replace")
        toks = re.findall(r"[0-9A-Fa-f]{2}", txt)
        return bytes(int(t, 16) for t in toks)
    return raw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--romdir", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "rtl", "roms"))
    ap.add_argument("--set", action="append", required=True,
                    help="m151,m152,m153,m154 (comma separated)")
    a = ap.parse_args()

    blob = bytearray()
    for n, spec in enumerate(a.set):
        paths = [p.strip() for p in spec.split(",")]
        if len(paths) != 4:
            sys.exit(f"set {n}: expected 4 paths, got {len(paths)}")
        buf = bytearray(b"\xff" * STRIDE)
        for (name, off, size), path in zip(REGIONS, paths):
            full = path if os.path.isabs(path) else os.path.join(a.romdir, path)
            data = load(full)
            if len(data) > size:
                sys.exit(f"set {n} {name}: {full} is {len(data)} B, "
                         f"region holds {size}")
            buf[off:off + len(data)] = data
            print(f"  set {n} {name}  {len(data):6} B  <- {os.path.basename(full)}"
                  + ("" if len(data) == size else f"  (padded to {size})"))
        blob += buf

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    open(a.out, "wb").write(blob)
    print(f"wrote {a.out}: {len(blob)} B, {len(a.set)} set(s)")

if __name__ == "__main__":
    main()
