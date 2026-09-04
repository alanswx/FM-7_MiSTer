#!/usr/bin/env python3
"""Drive the MiSTer OSD with explicit key down/up and holds.

The named `kbd:` actions drop presses often enough that a 4-down / 2-confirm
sequence lands correctly only about a third of the time. Sending raw Linux
keycodes as separate Down/Up messages with a real hold is far more reliable.

Row map at HEAD's CONF_STR -- trap 4: a hardcoded count silently lands on the
wrong row when CONF_STR gains an entry, and this file carried the pre-two-drive
counts (4 then 3) long after "Mount Disk 2" shifted everything down one:

    0 Load Tape   1 Mount Disk 1   2 Mount Disk 2   3 Tape Rewind
    4 Tape Audio  5 Boot ROM       6 Machine        7 Aspect ratio
    8 Reset       9 Reset and close OSD

usage: osdkey.py <bank>     # opens OSD, selects Boot ROM, sets bank, resets
"""
import os, sys, time
import websocket

WS = "ws://%s:8182/api/ws" % os.environ.get("MISTER", "192.168.1.75")
DOWN, ENTER = 108, 28          # KEY_DOWN, KEY_ENTER
HOLD, GAP = 0.12, 0.75

def main(bank):
    ws = websocket.create_connection(WS, timeout=10)
    def key(code, n=1):
        for _ in range(n):
            ws.send(f"kbdRawDown:{code}"); time.sleep(HOLD)
            ws.send(f"kbdRawUp:{code}");   time.sleep(GAP)
    try:
        ws.send("kbd:osd"); time.sleep(2.5)
        key(DOWN, 5)          # -> Boot ROM  (see the row map above)
        key(ENTER, bank)      # cycle 0 -> bank
        key(DOWN, 4)          # -> Reset and close OSD
        key(ENTER, 1)
    finally:
        ws.close()
    print(f"sent OSD sequence for bank {bank}", flush=True)

if __name__ == "__main__":
    main(int(sys.argv[1]))
