#!/usr/bin/env python3
"""Compare rtl/KEYBOARD.v's key tables with XM7's FM-7 tables.

XM7 keys its tables on the FM-7's physical key number ("phy"); KEYBOARD.v keys
them on PS/2 scancodes. PHY below is the correspondence KEYBOARD.v's plain table
already uses. Every difference printed should be one docs/REFERENCE.md explains:

  CTRL on '-', '^' and yen   the manual's control-mode drawing overrules XM7
  CTRL+SHIFT+O               XM7 gives $09; SHIFT has no effect in control mode
  Caps Lock (PS/2 $58)       a $00 entry that is_modifier never lets through

Run from the repository root:

  tools/cmp-keytables.py [VM_keyboard.c.txt] [KEYBOARD.v]
"""
import re, sys

XM7 = sys.argv[1] if len(sys.argv) > 1 else "refs/fm7-docs/xm7-retropc/utf8/VM_keyboard.c.txt"
RTL = sys.argv[2] if len(sys.argv) > 2 else "rtl/KEYBOARD.v"

# phy -> (name, 9-bit PS/2 {E0, code}, or None where no PS/2 key is mapped)
PHY = {
 0x01:("ESC",0x076),0x02:("1",0x016),0x03:("2",0x01e),0x04:("3",0x026),0x05:("4",0x025),
 0x06:("5",0x02e),0x07:("6",0x036),0x08:("7",0x03d),0x09:("8",0x03e),0x0a:("9",0x046),
 0x0b:("0",0x045),0x0c:("-",0x04e),0x0d:("^",0x055),0x0e:("YEN",0x05d),0x0f:("BS",0x066),
 0x10:("TAB",0x00d),0x11:("Q",0x015),0x12:("W",0x01d),0x13:("E",0x024),0x14:("R",0x02d),
 0x15:("T",0x02c),0x16:("Y",0x035),0x17:("U",0x03c),0x18:("I",0x043),0x19:("O",0x044),
 0x1a:("P",0x04d),0x1b:("@",0x054),0x1c:("[",0x05b),0x1d:("RET",0x05a),0x1e:("A",0x01c),
 0x1f:("S",0x01b),0x20:("D",0x023),0x21:("F",0x02b),0x22:("G",0x034),0x23:("H",0x033),
 0x24:("J",0x03b),0x25:("K",0x042),0x26:("L",0x04b),0x27:(";",0x04c),0x28:(":",0x052),
 0x29:("]",0x00e),0x2a:("Z",0x01a),0x2b:("X",0x022),0x2c:("C",0x021),0x2d:("V",0x02a),
 0x2e:("B",0x032),0x2f:("N",0x031),0x30:("M",0x03a),0x31:(",",0x041),0x32:(".",0x049),
 0x33:("/",0x04a),0x34:("_RO",None),0x35:("SPACE",0x029),
 0x36:("KP*",0x07c),0x37:("KP/",0x14a),0x38:("KP+",0x079),0x39:("KP-",0x07b),
 0x3a:("KP7",0x06c),0x3b:("KP8",0x075),0x3c:("KP9",0x07d),0x3d:("KP=",None),
 0x3e:("KP4",0x06b),0x3f:("KP5",0x073),0x40:("KP6",0x074),0x41:("KP,",None),
 0x42:("KP1",0x069),0x43:("KP2",0x072),0x44:("KP3",0x07a),0x45:("KPRET",0x15a),
 0x46:("KP0",0x070),0x47:("KP.",0x071),
 0x48:("INS",0x170),0x49:("EL=PgUp",0x17d),0x4a:("CLS=PgDn",0x17a),0x4b:("DEL",0x171),
 0x4c:("DUP",None),0x4d:("UP",0x175),0x4e:("HOME",0x16c),0x4f:("LEFT",0x16b),
 0x50:("DOWN",0x172),0x51:("RIGHT",0x174),
 0x57:("SPACE-L(AV)",None),0x58:("SPACE-R(AV)",None),
 0x5d:("PF1",0x005),0x5e:("PF2",0x006),0x5f:("PF3",0x004),0x60:("PF4",0x00c),
 0x61:("PF5",0x003),0x62:("PF6",0x00b),0x63:("PF7",0x083),0x64:("PF8",0x00a),
 0x65:("PF9",0x001),0x66:("PF10",0x009),
}
PS2 = {v[1] for v in PHY.values() if v[1] is not None}

# XM7: "physical code, without SHIFT, with SHIFT" triples; 0xffff = no code.
src = open(XM7, encoding="utf-8", errors="replace").read().split("#if XM7_VER == 1")[0]
xm7 = {}
for name, body in re.findall(r"WORD (\w+)_key_table\[\] = \{(.*?)\};", src, re.S):
    nums = [int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]+)", body)]
    xm7[name] = {nums[i]: tuple(None if n == 0xffff else n for n in nums[i+1:i+3])
                 for i in range(0, len(nums), 3)}

# KEYBOARD.v: split the lookup block at each mode's branch.
rtl = open(RTL).read()
marks = [("ctrl",   r"if \(ctrl_h && press_btn\) begin"),
         ("graph",  r"else if \(graph_h && press_btn\) begin"),
         ("kana_s", r"else if \(kana_h && shift_h && press_btn\) begin"),
         ("kana",   r"else if \(kana_h && press_btn\) begin"),
         ("shift",  r"else if \(shift_h && press_btn\) begin"),
         ("norm",   r"else if \(press_btn\) begin"),
         ("END",    r"always @\(posedge CLKSYS\) begin\s*\n\s*reg old_state")]
pos = [(n, re.search(p, rtl).start()) for n, p in marks]
core = {}
for (n, a), (_, b) in zip(pos, pos[1:]):
    t = {}
    for m in re.finditer(r"9'h([0-9a-fA-F]+):\s*begin\s*(.*?)\s*end\b", rtl[a:b]):
        code, body = int(m.group(1), 16), m.group(2)
        c = re.search(r"=\s*shift_h\s*\?\s*9'h([0-9a-f]+)\s*:\s*9'h([0-9a-f]+)", body)
        if c:
            t[code] = (int(c.group(2), 16), int(c.group(1), 16)); continue
        c = re.search(r"if \(!shift_h\).*?=\s*9'h([0-9a-f]+)", body)
        if c:
            t[code] = (int(c.group(1), 16), None); continue
        v = int(re.search(r"=\s*9'h([0-9a-f]+)", body).group(1), 16)
        t[code] = (v, v)
    core[n] = t

def h(v): return "--" if v is None else "$%03x" % v

def compare(label, xt, xcol, ct, ccol):
    rows = [(phy, name, ps2, xt.get(phy, (None, None))[xcol], ct.get(ps2, (None, None))[ccol])
            for phy, (name, ps2) in sorted(PHY.items()) if ps2 is not None]
    rows = [r for r in rows if r[3] != r[4]]
    rows += [(None, "?", ps2, None, ct[ps2][ccol]) for ps2 in ct if ps2 not in PS2]
    print(f"\n== {label}: {len(rows)} difference(s)")
    for phy, name, ps2, xv, cv in rows:
        print(f"   phy {'--' if phy is None else '%02x' % phy} {name:10s} ps2 {ps2:03x}   XM7 {h(xv)}   KEYBOARD.v {h(cv)}")

compare("NORMAL",       xm7["norm"],  0, core["norm"],   0)
compare("NORMAL+SHIFT", xm7["norm"],  1, core["shift"],  0)
compare("KANA",         xm7["kana"],  0, core["kana"],   0)
compare("KANA+SHIFT",   xm7["kana"],  1, core["kana_s"], 0)
compare("GRAPH",        xm7["graph"], 0, core["graph"],  0)
compare("GRAPH+SHIFT",  xm7["graph"], 1, core["graph"],  1)
compare("CTRL",         xm7["ctrl"],  0, core["ctrl"],   0)
compare("CTRL+SHIFT",   xm7["ctrl"],  1, core["ctrl"],   1)

# KEYBOARD.v has no CAP mode; this is what XM7's would add.
caps = [phy for phy in sorted(xm7["caps"]) if xm7["caps"][phy] != xm7["norm"].get(phy)]
print(f"\n== CAP (not implemented): XM7 swaps the case of {len(caps)} letter keys")
