#!/usr/bin/env python3
"""Drive the MiSTer OSD with explicit key down/up and holds.

The named `kbd:` actions drop presses often enough that a 4-down / 2-confirm
sequence lands correctly only about a third of the time. Sending raw Linux
keycodes as separate Down/Up messages with a real hold is far more reliable.

The row index is RESOLVED FROM CONF_STR by osdrows.py, not hardcoded. Trap 4
has fired three times here -- this file carried the pre-two-drive counts long
after "Mount Disk 2" shifted every row down one, and 4b447f3's "Disk 1 image" /
"Disk 2 image" shifted them two further. A stale count does not error; it
selects the wrong item and the run "succeeds" having set something else.

**The OSD is drawn by the core ON THE BOARD.** osdrows reads the working tree,
so if the deployed rbf came from another commit, point at that commit's top:

    git show <commit>:FM-7_MiSTer.sv > /tmp/top.sv
    FM7_TOP=/tmp/top.sv ./osdkey.py 2

The resolved row is printed on every run so a mismatch is visible.

usage: osdkey.py <bank>     # opens OSD, selects Boot ROM, sets bank, resets
"""
import os, sys, time
import websocket
from osdrows import index_of

WS = "ws://%s:8182/api/ws" % os.environ.get("MISTER", "192.168.1.75")
DOWN, ENTER = 108, 28          # KEY_DOWN, KEY_ENTER
HOLD, GAP = 0.12, 0.75
TOP = os.environ.get("FM7_TOP")

def main(bank):
    bootrom = index_of("Boot ROM", TOP)
    close = index_of("Reset and close OSD", TOP)
    print(f"OSD rows: Boot ROM={bootrom}, Reset and close OSD={close} "
          f"(from {TOP or 'working tree'})", flush=True)
    ws = websocket.create_connection(WS, timeout=10)
    def key(code, n=1):
        for _ in range(n):
            ws.send(f"kbdRawDown:{code}"); time.sleep(HOLD)
            ws.send(f"kbdRawUp:{code}");   time.sleep(GAP)
    try:
        ws.send("kbd:osd"); time.sleep(2.5)
        key(DOWN, bootrom)          # -> Boot ROM
        key(ENTER, bank)            # cycle 0 -> bank
        key(DOWN, close - bootrom)  # -> Reset and close OSD
        key(ENTER, 1)
    finally:
        ws.close()
    print(f"sent OSD sequence for bank {bank}", flush=True)

if __name__ == "__main__":
    main(int(sys.argv[1]))
