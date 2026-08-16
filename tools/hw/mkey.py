#!/usr/bin/env python3
"""Send mrext Remote kbd messages over its websocket.  usage: mkey.py osd down down confirm"""
import os, sys, time
import websocket

WS = "ws://%s:8182/api/ws" % os.environ.get("MISTER", "192.168.1.75")

def main(keys):
    ws = websocket.create_connection(WS, timeout=10)
    try:
        for k in keys:
            if k.startswith("sleep"):
                time.sleep(float(k.split("=", 1)[1]))
                continue
            msg = k if ":" in k else "kbd:" + k
            ws.send(msg)
            print("sent", msg, flush=True)
            time.sleep(0.45)
    finally:
        ws.close()

if __name__ == "__main__":
    main(sys.argv[1:])
