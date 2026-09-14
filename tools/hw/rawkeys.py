#!/usr/bin/env python3
"""Drive the FM-7 with raw Linux keycodes and REAL holds, as a token sequence.

type.py covers plain ASCII on the JIS layout, but it cannot type capitals, hold
a key for a measured time, chord modifiers, or reach the numeric keypad -- and
testing auto-repeat, GRAPH, KANA and BREAK needs all four.

    rawkeys.py t:30              tap A
    rawkeys.py h:30:2.0          hold A for 2.0 s, then release
    rawkeys.py d:42 t:35 u:42    Shift down, tap H, Shift up  -> capital H
    rawkeys.py s:1.5             sleep

Tokens: t:CODE[:HOLD]  d:CODE  u:CODE  h:CODE:SEC  s:SEC

The mrext virtual keyboard has no EV_REP, so a held key produces exactly one
key-down. Any repeat you see on screen is the CORE's auto-repeat, not a PC
typematic -- which means this tool cannot test whether the core filters a real
keyboard's typematic repeats. That needs a physical keyboard.

Useful codes: A=30 B=48 F1=59 Enter=28 Space=57 LShift=42 LCtrl=29 LAlt=56
(GRAPH) RAlt=100 (KANA) RCtrl=97 (BREAK) PgDn=109 (CLS). Keypad: 7=71 8=72 9=73
-=74 4=75 5=76 6=77 +=78 1=79 2=80 3=81 0=82 .=83 *=55 /=98 Enter=96.
"""
import os, sys, time
import websocket

WS = "ws://%s:8182/api/ws" % os.environ.get("MISTER", "192.168.1.75")
TAP_HOLD, GAP = 0.10, 0.30

def main(tokens):
    ws = websocket.create_connection(WS, timeout=10)
    try:
        for tok in tokens:
            kind, _, rest = tok.partition(":")
            args = rest.split(":") if rest else []
            if kind == "s":
                time.sleep(float(args[0]))
            elif kind == "d":
                ws.send(f"kbdRawDown:{int(args[0])}"); time.sleep(0.05)
            elif kind == "u":
                ws.send(f"kbdRawUp:{int(args[0])}"); time.sleep(0.05)
            elif kind == "t":
                hold = float(args[1]) if len(args) > 1 else TAP_HOLD
                ws.send(f"kbdRawDown:{int(args[0])}"); time.sleep(hold)
                ws.send(f"kbdRawUp:{int(args[0])}");   time.sleep(GAP)
            elif kind == "h":
                ws.send(f"kbdRawDown:{int(args[0])}"); time.sleep(float(args[1]))
                ws.send(f"kbdRawUp:{int(args[0])}");   time.sleep(GAP)
            else:
                sys.exit(f"bad token {tok!r}")
    finally:
        ws.close()

if __name__ == "__main__":
    main(sys.argv[1:])
