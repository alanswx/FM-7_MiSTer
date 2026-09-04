#!/usr/bin/env python3
"""Flip the OSD's Machine item to FM77AV and reset, without touching anything else.

The row index is RESOLVED FROM CONF_STR by osdrows.py, not hardcoded: trap 4
has fired three times here (Mount Disk 2 shifted every row down one; Disk 1/2
image shifted them two more in 4b447f3) and a stale count does not error, it
just selects the wrong menu item.

**The OSD is drawn by the core ON THE BOARD.** osdrows reads the working tree,
so if the deployed rbf was built from another commit, point at that commit's
top file:

    git show <commit>:FM-7_MiSTer.sv > /tmp/top.sv
    FM7_TOP=/tmp/top.sv ./avtoggle.py

The resolved row is printed on every run so a mismatch is visible rather than
silent.

Raw down/up with a real hold, for the reason osdkey.py documents: the named
`kbd:` actions drop presses.

usage: avtoggle.py            # FM-7 -> FM77AV, then reset and close
"""
import os, sys, time
import websocket
from osdrows import index_of

WS = "ws://%s:8182/api/ws" % os.environ.get("MISTER", "192.168.1.75")
DOWN, ENTER = 108, 28
HOLD, GAP = 0.12, 0.75
TOP = os.environ.get("FM7_TOP")


def main():
    machine = index_of("Machine", TOP)
    close = index_of("Reset and close OSD", TOP)
    print(f"OSD rows: Machine={machine}, Reset and close OSD={close} "
          f"(from {TOP or 'working tree'})", flush=True)

    ws = websocket.create_connection(WS, timeout=10)
    def key(code, n=1):
        for _ in range(n):
            ws.send(f"kbdRawDown:{code}"); time.sleep(HOLD)
            ws.send(f"kbdRawUp:{code}");   time.sleep(GAP)
    try:
        ws.send("kbd:osd"); time.sleep(2.5)
        key(DOWN, machine)        # -> Machine
        key(ENTER, 1)             # FM-7 -> FM77AV
        key(DOWN, close - machine)
        key(ENTER, 1)
    finally:
        ws.close()
    print("machine -> FM77AV, reset", flush=True)


if __name__ == "__main__":
    main()
