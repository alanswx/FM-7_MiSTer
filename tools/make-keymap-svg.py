#!/usr/bin/env python3
"""Draw docs/keyboard.svg -- what each PC key does on the FM-7.

The mapping is JIS-POSITIONAL: the FM-7's key *positions* are kept, so a key
often produces a different character than its US PC legend. This file's table
is transcribed from rtl/KEYBOARD.v's base (unshifted) and shift cases; the
PS/2 scancode is carried alongside each entry so the two can be diffed.

Regenerate with:  tools/make-keymap-svg.py
"""
import html

# (ps2, pc legend, FM-7 unshifted, FM-7 shifted or None, width in units)
# Rows mirror a US keyboard's physical layout.
R1 = [(0x76,"Esc","ESC",None,1.0)] + [
     (c,f"F{i+1}",f"PF{i+1}",None,1.0) for i,c in enumerate(
     [0x05,0x06,0x04,0x0c,0x03,0x0b,0x83,0x0a,0x01,0x09])]
R2 = [(0x0e,"`","]",None,1.0),
      (0x16,"1","1","!",1.0),(0x1e,"2","2",'"',1.0),(0x26,"3","3","#",1.0),
      (0x25,"4","4","$",1.0),(0x2e,"5","5","%",1.0),(0x36,"6","6","&",1.0),
      (0x3d,"7","7","'",1.0),(0x3e,"8","8","(",1.0),(0x46,"9","9",")",1.0),
      (0x45,"0","0",None,1.0),(0x4e,"-","-","=",1.0),(0x55,"=","^","~",1.0),
      (0x66,"Bksp","BS",None,2.0)]
R3 = [(0x0d,"Tab","TAB",None,1.5)] + [
      (c,l,l,l.upper(),1.0) for c,l in
      [(0x15,"q"),(0x1d,"w"),(0x24,"e"),(0x2d,"r"),(0x2c,"t"),(0x35,"y"),
       (0x3c,"u"),(0x43,"i"),(0x44,"o"),(0x4d,"p")]] + [
      (0x54,"[","@","`",1.0),(0x5b,"]","[","{",1.0),(0x5d,"\\","\\","|",1.5)]
R4 = [(0x58,"Caps","(none)",None,1.75)] + [
      (c,l,l,l.upper(),1.0) for c,l in
      [(0x1c,"a"),(0x1b,"s"),(0x23,"d"),(0x2b,"f"),(0x34,"g"),(0x33,"h"),
       (0x3b,"j"),(0x42,"k"),(0x4b,"l")]] + [
      (0x4c,";",";","+",1.0),(0x52,"'",":","*",1.0),
      (0x5a,"Enter","RETURN",None,2.25)]
R5 = [(0x12,"Shift","SHIFT",None,2.25)] + [
      (c,l,l,l.upper(),1.0) for c,l in
      [(0x1a,"z"),(0x22,"x"),(0x21,"c"),(0x2a,"v"),(0x32,"b"),(0x31,"n"),
       (0x3a,"m")]] + [
      (0x41,",",",","<",1.0),(0x49,".",".",">",1.0),(0x4a,"/","/","?",1.0),
      (0x59,"Shift","SHIFT",None,2.75)]
R6 = [(0x14,"Ctrl","CTRL",None,1.5),(0x11,"Alt","GRAPH",None,1.5),
      (0x29,"Space","SPACE",None,7.0),
      (0x111,"AltGr","KANA",None,1.5),(0x114,"Ctrl","BREAK",None,1.5)]
ROWS = [R1,R2,R3,R4,R5,R6]

# The editing cluster, drawn to the right.
CLUSTER = [[(0x170,"Ins","INS",None,1.0),(0x16c,"Home","HOME",None,1.0),
            (0x17d,"PgUp","EL",None,1.0)],
           [(0x171,"Del","DEL",None,1.0),(None,"","",None,1.0),
            (0x17a,"PgDn","CLS",None,1.0)],
           [(None,"","",None,1.0),(0x175,"Up","UP",None,1.0),(None,"","",None,1.0)],
           [(0x16b,"Left","LEFT",None,1.0),(0x172,"Down","DOWN",None,1.0),
            (0x174,"Right","RIGHT",None,1.0)]]

# What a US PC keyboard produces, so "differs" is a comparison and not a
# heuristic. Only keys listed here can differ; letters never do.
US = {"`":("`","~"), "1":("1","!"), "2":("2","@"), "3":("3","#"),
      "4":("4","$"), "5":("5","%"), "6":("6","^"), "7":("7","&"),
      "8":("8","*"), "9":("9","("), "0":("0",")"), "-":("-","_"),
      "=":("=","+"), "[":("[","{"), "]":("]","}"), "\\":("\\","|"),
      ";":(";",":"), "'":("'",'"'), ",":(",","<"), ".":(".",">"),
      "/":("/","?")}

def differs(pc, un, sh):
    """True when this key does not do what a US PC keyboard would."""
    if pc not in US:
        return False              # letters, Esc, F-keys, modifiers, cluster
    u_un, u_sh = US[pc]
    return (un != u_un) or ((sh or "") != u_sh)

U, GAP, PAD = 62, 6, 22
TOP = 104

def esc(s): return html.escape(s, quote=True)

def key(x, y, w, pc, un, sh, differs):
    fill = "var(--k-diff)" if differs else "var(--k)"
    o = [f'<g><rect x="{x:.1f}" y="{y:.1f}" width="{w*U-GAP:.1f}" height="{U-GAP:.1f}" '
         f'rx="7" fill="{fill}" stroke="var(--edge)" stroke-width="1"/>']
    cx = x + (w*U-GAP)/2
    # PC legend, small, top-left -- what is printed on the user's key
    o.append(f'<text x="{x+7:.1f}" y="{y+15:.1f}" class="pc">{esc(pc)}</text>')
    if sh:
        o.append(f'<text x="{cx:.1f}" y="{y+34:.1f}" class="sh">{esc(sh)}</text>')
        o.append(f'<text x="{cx:.1f}" y="{y+50:.1f}" class="un">{esc(un)}</text>')
    else:
        o.append(f'<text x="{cx:.1f}" y="{y+42:.1f}" class="un big">{esc(un)}</text>')
    o.append('</g>')
    return "".join(o)

def main():
    parts, y = [], TOP
    width = PAD*2 + int(15*U) + 40 + 3*U
    for row in ROWS:
        x = PAD
        for ps2, pc, un, sh, w in row:
            parts.append(key(x, y, w, pc, un, sh, differs(pc, un, sh)))
            x += w*U
        y += U
    # cluster
    cy = TOP + U
    for row in CLUSTER:
        cx = PAD + 15*U + 40
        for ps2, pc, un, sh, w in row:
            if ps2 is not None:
                parts.append(key(cx, cy, w, pc, un, sh, False))
            cx += w*U
        cy += U
    height = cy + 118

    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" role="img" aria-label="FM-7 keyboard map for MiSTer">
<title>FM-7 keyboard map</title>
<style>
  :root {{ --bg:#faf9f7; --k:#ffffff; --k-diff:#fdf0d5; --edge:#c9c4bc;
           --ink:#1d1d1f; --dim:#8a857d; --accent:#9a3412; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg:#17181a; --k:#25262a; --k-diff:#3a2f1c; --edge:#44464b;
             --ink:#f2f2f3; --dim:#9b9791; --accent:#f0a868; }}
  }}
  text {{ font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; }}
  .pc  {{ font-size:11px; fill:var(--dim); }}
  .un  {{ font-size:17px; fill:var(--ink); text-anchor:middle; font-weight:600; }}
  .un.big {{ font-size:14px; }}
  .sh  {{ font-size:14px; fill:var(--accent); text-anchor:middle; font-weight:600; }}
  .h1  {{ font-size:23px; fill:var(--ink); font-weight:700; }}
  .h2  {{ font-size:13px; fill:var(--dim); }}
  .lg  {{ font-size:12px; fill:var(--dim); }}
</style>
<rect width="100%" height="100%" fill="var(--bg)"/>
<text x="{PAD}" y="38" class="h1">FM-7 keyboard on MiSTer</text>
<text x="{PAD}" y="60" class="h2">The layout is JIS-positional: keys keep the FM-7's positions, so some type a different character than your PC cap says.</text>
<text x="{PAD}" y="78" class="h2">Small grey = your PC key. Large = what the FM-7 types. Orange = with SHIFT. Shaded keys differ from a US layout.</text>
{"".join(parts)}
<text x="{PAD}" y="{height-52}" class="lg">Alt = GRAPH (semigraphics $80-$FD)   |   Right Alt = KANA, a LOCKING toggle   |   Right Ctrl = BREAK   |   Caps Lock does nothing</text>
<text x="{PAD}" y="{height-34}" class="lg">PgUp = EL (erase line), PgDn = CLS. F1-F10 are PF1-PF10. Generated from rtl/KEYBOARD.v by tools/make-keymap-svg.py.</text>
<text x="{PAD}" y="{height-16}" class="lg">The numeric keypad is not mapped, except keypad / which types "/".</text>
</svg>
'''
    open("docs/keyboard.svg","w").write(svg)
    print(f"wrote docs/keyboard.svg ({width}x{height})")

if __name__ == "__main__":
    main()
