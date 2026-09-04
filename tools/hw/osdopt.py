#!/usr/bin/env python3
"""Set one OSD option by label, then reset and close.

Generalises osdkey.py to any cycling option row. The row index comes from
osdrows.py, so it survives CONF_STR changes -- see trap 4 in the README.

    osdopt.py "Disk 1 image" 2     # press ENTER twice on that row -> value "3"

An option row cycles through its values, so `presses` is an OFFSET from
whatever the row currently shows, not an absolute value. The OSD does not
persist, so after a fresh core load every row is back at its first value and
presses == the index you want.

usage: osdopt.py <label> <presses> [--no-reset]
"""
import os, sys, time
import websocket
from osdrows import index_of

WS = "ws://%s:8182/api/ws" % os.environ.get("MISTER", "192.168.1.75")
DOWN, ENTER = 108, 28
HOLD, GAP = 0.12, 0.75
TOP = os.environ.get("FM7_TOP")


def main(label, presses, do_reset=True):
    row = index_of(label, TOP)
    close = index_of("Reset and close OSD", TOP)
    print(f"OSD rows: {label!r}={row}, Reset and close OSD={close} "
          f"(from {TOP or 'working tree'})", flush=True)

    ws = websocket.create_connection(WS, timeout=10)
    def key(code, n=1):
        for _ in range(n):
            ws.send(f"kbdRawDown:{code}"); time.sleep(HOLD)
            ws.send(f"kbdRawUp:{code}");   time.sleep(GAP)
    try:
        ws.send("kbd:osd"); time.sleep(2.5)
        key(DOWN, row)
        if presses:
            key(ENTER, presses)
        if do_reset:
            key(DOWN, close - row)
            key(ENTER, 1)
    finally:
        ws.close()
    print(f"set {label!r} +{presses}" + (", reset" if do_reset else ""), flush=True)


if __name__ == "__main__":
    a = [x for x in sys.argv[1:] if x != "--no-reset"]
    main(a[0], int(a[1]), "--no-reset" not in sys.argv)
