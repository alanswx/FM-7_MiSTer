#!/usr/bin/env python3
"""Flip the OSD's Machine item to FM77AV and reset, without touching anything else.

Menu geometry at HEAD's CONF_STR (see trap 4 -- a hardcoded count silently
lands on the wrong row when CONF_STR changes):

    0 Load Tape   1 Mount Disk 1   2 Mount Disk 2   3 Tape Rewind
    4 Tape Audio  5 Boot ROM       6 Machine        7 Aspect ratio
    8 Reset       9 Reset and close OSD

so Machine is 6 downs from the top and "Reset and close OSD" is 3 more.
Raw down/up with a real hold, for the reason osdkey.py documents: the named
`kbd:` actions drop presses.

usage: avtoggle.py            # FM-7 -> FM77AV, then reset and close
"""
import os, sys, time
import websocket

WS = "ws://%s:8182/api/ws" % os.environ.get("MISTER", "192.168.1.75")
DOWN, ENTER = 108, 28
HOLD, GAP = 0.12, 0.75

def main():
    ws = websocket.create_connection(WS, timeout=10)
    def key(code, n=1):
        for _ in range(n):
            ws.send(f"kbdRawDown:{code}"); time.sleep(HOLD)
            ws.send(f"kbdRawUp:{code}");   time.sleep(GAP)
    try:
        ws.send("kbd:osd"); time.sleep(2.5)
        key(DOWN, 6)          # -> Machine
        key(ENTER, 1)         # FM-7 -> FM77AV
        key(DOWN, 3)          # -> Reset and close OSD
        key(ENTER, 1)
    finally:
        ws.close()
    print("machine -> FM77AV, reset", flush=True)

if __name__ == "__main__":
    main()
