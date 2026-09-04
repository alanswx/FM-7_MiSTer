#!/usr/bin/env python3
"""Resolve OSD menu row indices by PARSING CONF_STR, instead of hardcoding them.

Trap 4 has now fired three times in this project: `Mount Disk 2` shifted every
row down one, and `Disk 1 image` / `Disk 2 image` (4b447f3) shifted them down
two more. A hardcoded count does not error when it goes stale -- it silently
selects a different menu item, so the run "succeeds" having set the wrong
option. Deriving the count removes the class.

**This reads the WORKING TREE, so it describes the core you would build now.**
The OSD is drawn from the CONF_STR compiled into the core that is actually ON
THE BOARD. If the deployed rbf was built from a different commit, this map is
wrong for it -- which is why every caller prints the row it resolved.

usage:  osdrows.py              # print the whole map
        osdrows.py "Boot ROM"   # print one row's index
"""
import os, re, sys

# The joystick/version tail is not selectable, and MiSTer draws the J1 item at
# the bottom of the OSD regardless of where it appears in the string.
TAIL = ("J", "j", "v", "V")


def rows(sv_path=None):
    """Return the selectable OSD rows, in order, as a list of labels."""
    if sv_path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        sv_path = os.path.join(here, "..", "..", "FM-7_MiSTer.sv")
    src = open(sv_path).read()
    m = re.search(r"localparam CONF_STR\s*=\s*\{(.*?)^\};", src, re.S | re.M)
    if not m:
        raise SystemExit(f"no CONF_STR in {sv_path}")
    body = m.group(1)
    # Strip // comments BEFORE pulling quoted strings out: the comments in this
    # block quote menu values (`only "1" exists`) and would otherwise be read as
    # menu entries.
    body = re.sub(r"//[^\n]*", "", body)

    out = []
    for i, raw in enumerate(re.findall(r'"([^"]*)"', body)):
        if i == 0:              # "FM-7;;" -- the core name
            continue
        e = raw.rstrip(";")
        if not e or e == "-":   # separator: drawn, but skipped by navigation
            continue
        parts = e.split(",")
        code = parts[0]
        # The joystick/version tail is not selectable. MiSTer draws the J1 item
        # ("Fire mode.") at the bottom of the OSD wherever J1 sits in the
        # string, which is why this file keeps J1/jn/v/V last.
        if re.fullmatch(r"J\d*|jn|v|V", code):
            continue
        # F<n>/S<n> carry an extension field first: "F1,t77,Load Tape".
        # Everything else labels in field 1: "O[11:10],Boot ROM,0 disk,...".
        if re.fullmatch(r"[FS]\d*", code) and len(parts) > 2:
            out.append(parts[2])
        elif len(parts) > 1:
            out.append(parts[1])
        else:
            out.append(code)
    return out


def index_of(label, sv_path=None):
    """Downs from the top of the OSD to `label`. Exact match, then prefix."""
    r = rows(sv_path)
    if label in r:
        return r.index(label)
    hits = [i for i, x in enumerate(r) if x.startswith(label)]
    if len(hits) == 1:
        return hits[0]
    raise SystemExit(f"{label!r} not found (or ambiguous) in OSD rows: {r}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(index_of(sys.argv[1]))
    else:
        for i, label in enumerate(rows()):
            print(f"{i:3d}  {label}")
