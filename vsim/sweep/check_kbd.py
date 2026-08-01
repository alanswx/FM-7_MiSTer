#!/usr/bin/env python3
"""Cross-check rtl/KEYBOARD.v's CTRL/GRAPH/KANA tables against CSP's.

CSP keys its tables on the FM-7's own physical key number (an index into
vk_matrix_106); KEYBOARD.v is keyed on PS/2 set-2 codes. This walks the PS/2 ->
phy correspondence that the existing unshifted table establishes and diffs the
two, so a single mistyped byte in ~150 hand-transcribed entries cannot hide.
"""
import re
import sys

import os
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RTL = os.path.join(REPO, "rtl", "KEYBOARD.v")
CSP = os.path.join(REPO, "refs", "common-src-project", "src", "vm", "fm7",
                   "keyboard_tables.h")

# PS/2 set-2 code -> FM-7 physical key number, read off vk_matrix_106 by
# matching each key's identity against KEYBOARD.v's own unshifted table.
PS2_TO_PHY = {
    0x16: 0x02, 0x1e: 0x03, 0x26: 0x04, 0x25: 0x05, 0x2e: 0x06, 0x36: 0x07,
    0x3d: 0x08, 0x3e: 0x09, 0x46: 0x0a, 0x45: 0x0b, 0x4e: 0x0c, 0x55: 0x0d,
    0x5d: 0x0e, 0x66: 0x0f, 0x0d: 0x10,
    0x15: 0x11, 0x1d: 0x12, 0x24: 0x13, 0x2d: 0x14, 0x2c: 0x15, 0x35: 0x16,
    0x3c: 0x17, 0x43: 0x18, 0x44: 0x19, 0x4d: 0x1a, 0x54: 0x1b, 0x5b: 0x1c,
    0x5a: 0x1d,
    0x1c: 0x1e, 0x1b: 0x1f, 0x23: 0x20, 0x2b: 0x21, 0x34: 0x22, 0x33: 0x23,
    0x3b: 0x24, 0x42: 0x25, 0x4b: 0x26, 0x4c: 0x27, 0x52: 0x28, 0x0e: 0x29,
    0x1a: 0x2a, 0x22: 0x2b, 0x21: 0x2c, 0x2a: 0x2d, 0x32: 0x2e, 0x31: 0x2f,
    0x3a: 0x30, 0x41: 0x31, 0x49: 0x32, 0x4a: 0x33,
    0x29: 0x58, 0x14a: 0x37,
    0x170: 0x48, 0x17d: 0x49, 0x17a: 0x4a, 0x171: 0x4b,
    0x175: 0x4d, 0x16c: 0x4e, 0x16b: 0x4f, 0x172: 0x50, 0x174: 0x51,
    0x05: 0x5d, 0x06: 0x5e, 0x04: 0x5f, 0x0c: 0x60, 0x03: 0x61,
    0x0b: 0x62, 0x83: 0x63, 0x0a: 0x64, 0x01: 0x65, 0x09: 0x66,
}


def csp_table(name):
    src = open(CSP).read()
    m = re.search(r"(?:const\s+)?(?:struct\s+)?key_tbl_t\s+" + name +
                  r"\[\]\s*=\s*\{(.*?)\};", src, re.S)
    if not m:
        sys.exit("no CSP table " + name)
    out = {}
    for phy, code in re.findall(r"\{\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)\s*\}",
                                m.group(1)):
        p, c = int(phy, 16), int(code, 16)
        if p == 0xffff:
            continue
        out[p] = c
    return out


def rtl_branch(label):
    """Pull one modifier branch's `9'hXXX: ... = 9'hYYY` pairs out of KEYBOARD.v."""
    src = open(RTL).read()
    starts = {
        "ctrl":  r"if \(ctrl_h && press_btn\) begin",
        "graph": r"else if \(graph_h && press_btn\) begin",
        "kanas": r"else if \(kana_h && shift_h && press_btn\) begin",
        "kana":  r"else if \(kana_h && press_btn\) begin",
    }
    m = re.search(starts[label], src)
    if not m:
        sys.exit("no RTL branch " + label)
    body = src[m.end():]
    body = body[:body.index("endcase")]
    out = {}
    for code, val in re.findall(r"9'h([0-9a-fA-F]+)\s*:.*?=\s*(?:shift_h \?.*?:\s*)?9'h([0-9a-fA-F]+)",
                                body):
        out[int(code, 16)] = int(val, 16) & 0xff
    return out


def compare(label, csp_name, rtl_label):
    csp = csp_table(csp_name)
    rtl = rtl_branch(rtl_label)
    bad = 0
    for ps2, val in sorted(rtl.items()):
        phy = PS2_TO_PHY.get(ps2)
        if phy is None:
            print(f"  {label}: PS/2 ${ps2:03x} has no phy mapping")
            bad += 1
            continue
        want = csp.get(phy)
        if want is None:
            print(f"  {label}: PS/2 ${ps2:03x} (phy ${phy:02x}) not in CSP")
            bad += 1
        elif (want & 0xff) != val:
            print(f"  {label}: PS/2 ${ps2:03x} (phy ${phy:02x}) "
                  f"RTL ${val:02x} != CSP ${want & 0xff:02x}")
            bad += 1
    # And the other direction: CSP entries we could have covered but did not.
    phy_to_ps2 = {v: k for k, v in PS2_TO_PHY.items()}
    for phy, want in sorted(csp.items()):
        ps2 = phy_to_ps2.get(phy)
        if ps2 is not None and ps2 not in rtl:
            print(f"  {label}: phy ${phy:02x} (PS/2 ${ps2:03x}) "
                  f"= ${want & 0xff:02x} MISSING from RTL")
            bad += 1
    print(f"{label}: {len(rtl)} RTL entries, {bad} problems")
    return bad


total = 0
total += compare("CTRL", "ctrl_key", "ctrl")
total += compare("GRAPH", "graph_key", "graph")
total += compare("KANA", "kana_key", "kana")
total += compare("KANA+SHIFT", "kana_shift_key", "kanas")
print("TOTAL PROBLEMS:", total)
