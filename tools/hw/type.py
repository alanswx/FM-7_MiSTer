#!/usr/bin/env python3
"""Type ASCII into the FM-7 over mrext, using this JIS layout's real positions.
`:` is keycode 40 (US apostrophe slot) and `"` is Shift+2 -- both established by
experiment, not assumed. usage: type.py '<text>' [--enter]"""
import os, sys, time, websocket
WS="ws://%s:8182/api/ws" % os.environ.get("MISTER", "192.168.1.75")
M={**{c:k for c,k in zip("1234567890",[2,3,4,5,6,7,8,9,10,11])},
   **{c:k for c,k in zip("qwertyuiop",range(16,26))},
   **{c:k for c,k in zip("asdfghjkl",range(30,39))},
   **{c:k for c,k in zip("zxcvbnm",range(44,51))},
   ',':51,'.':52,'/':53,';':39,':':40,'-':12,'=':13,' ':57}
SH={'(':9,')':10,'?':53,'"':3,'*':9,'+':13}
def main(txt, enter):
    ws=websocket.create_connection(WS,timeout=10)
    def k(c,shift=False):
        if shift: ws.send("kbdRawDown:42"); time.sleep(.03)
        ws.send(f"kbdRawDown:{c}"); time.sleep(.03); ws.send(f"kbdRawUp:{c}"); time.sleep(.03)
        if shift: ws.send("kbdRawUp:42"); time.sleep(.03)
        time.sleep(.045)
    for ch in txt.lower():
        if ch in M: k(M[ch])
        elif ch in SH: k(SH[ch], True)
        else: print("skip", repr(ch))
    if enter: k(28)
    ws.close()
main(sys.argv[1], "--enter" in sys.argv)
