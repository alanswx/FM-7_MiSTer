#!/usr/bin/env python3
"""Grep OCR'd text without trusting the OCR.

    tools/ocrgrep.py '$FD05' refs/fm7-docs/**/*.txt
    tools/ocrgrep.py --context 2 'MB61VH010' refs/fm7-docs

A plain grep over a scanned book answers a question about your pattern, not
about the book. Two things go wrong at once:

* **Character confusion.** OCR routinely swaps 0/O/Q/D, 1/l/I/|, 5/S, 8/B, 6/G,
  2/Z, and in Japanese scans 力/カ, 口/ロ, 一/ー/-, 二/ニ. `$FD05` may be sitting
  on the page as `SFDO5`, `$FDO5`, `$FD０5` or `$FDOS`.
* **Spurious spacing.** Scanned tables and Japanese text come out with spaces
  inserted between characters, so `FD05` becomes `F D 0 5` and a contiguous
  match never fires.

This builds one regex per query that is tolerant of both: every character
becomes a class of its plausible OCR confusions, and optional whitespace is
allowed between characters. Hits are reported with the page banner that
`tools/reocr.sh` writes, so a result can be checked against the scan.

**Still not proof of absence.** If this finds nothing, render the page range and
look at it before concluding the book is silent -- and if the text came from an
archive.org `_djvu.txt`, re-OCR it first: those are often English OCR run over
Japanese pages and are close to worthless (see tools/reocr.sh).
"""
import os
import re
import sys
import glob

# Deliberately conservative and symmetric: only pairs actually seen confused in
# this project's scans. A wider table matches everything and reports nothing.
CONFUSE = [
    "0OQD０", "1lI|１", "5S５", "8B８", "6G６",
    "2Z２", "7T７", "9g９", "4A４", "3３",
    "力カ", "口ロ", "一ー-—―", "二ニ", "十ト", "夕タ", "工エ", "八ハ",
]


def char_class(c):
    for grp in CONFUSE:
        if c in grp:
            return "[" + re.escape(grp) + "]"
    if c.isalpha():
        return "[" + re.escape(c.lower() + c.upper()) + "]"
    return re.escape(c)


def build(pattern):
    """One regex tolerant of OCR confusion AND of spaces inserted mid-token."""
    parts = [char_class(c) for c in pattern if not c.isspace()]
    return re.compile(r"\s*".join(parts))


def files_from(args):
    out = []
    for a in args:
        if os.path.isdir(a):
            out += glob.glob(os.path.join(a, "**", "*.txt"), recursive=True)
        else:
            out += glob.glob(a, recursive=True)
    return [f for f in out if os.path.isfile(f)]


def main():
    argv = sys.argv[1:]
    ctx = 0
    if "--context" in argv:
        i = argv.index("--context")
        ctx = int(argv[i + 1])
        del argv[i:i + 2]
    if len(argv) < 2:
        print(__doc__)
        return 2
    pattern, targets = argv[0], argv[1:]
    rx = build(pattern)
    print(f"pattern {pattern!r} -> {rx.pattern}\n")

    total = 0
    for path in sorted(files_from(targets)):
        try:
            lines = open(path, errors="replace").read().split("\n")
        except OSError:
            continue
        page = "?"
        hits = []
        for n, line in enumerate(lines):
            m = re.match(r"=== page (\d+) ===", line)
            if m:
                page = m.group(1)
                continue
            if rx.search(line):
                hits.append((page, n, line.strip()))
        if hits:
            print(f"--- {path} ({len(hits)} hits) ---")
            for page, n, line in hits[:40]:
                print(f"  p{page:>4} : {line[:150]}")
                for k in range(1, ctx + 1):
                    if n + k < len(lines):
                        print(f"          {lines[n + k].strip()[:150]}")
            if len(hits) > 40:
                print(f"  ... {len(hits) - 40} more")
            total += len(hits)
    print(f"\n{total} hits. Zero is NOT proof of absence -- see this file's docstring.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
