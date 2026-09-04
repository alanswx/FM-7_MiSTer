# Hardware test harness

Scripts for driving a real MiSTer (DE10-Nano) headlessly: keys in over the
network, screenshots and audio out. Everything here was proven in hardware
sessions; the traps at the bottom each cost real time once.

All scripts target `$MISTER` (default `192.168.1.75`). Prerequisites on the
MiSTer: **mrext Remote** listening on `:8182` (websocket keys, screenshot
API), ssh keys for `root@`. On this side: `python3-websocket`, `ffmpeg`, and
optionally an HDMI capture card (MiraBox/MS2109 class) on the MiSTer's HDMI
output for OSD capture and audio measurement.

## The scripts

| script | what it does |
|---|---|
| `mkey.py osd down confirm` | named mrext key actions (`kbd:`), plus `sleep=N` and raw `kbdRaw:<code>` forms |
| `osdkey.py <bank>` | OSD navigation with raw down/up and real holds — sets Boot ROM bank and resets. Named `kbd:` actions drop presses; this is the reliable way |
| `avtoggle.py` | flips the Machine row to FM77AV and resets — what every AV title needs |
| `runtest.sh <label> <mgl> [av] [settle]` | one test: load MGL, optionally switch to FM77AV, settle, screenshot |
| `score.py <png>...` | size, **lit-pixel %** and distinct-colour count per shot — the pass/fail signal that byte size is not |
| `type.py '<text>' [--enter]` | types ASCII into the FM-7 with raw scancodes on the **JIS** layout |
| `shoot.sh <label>` | MiSTer-side screenshot into `shots/<label>.png` — **core video only, no OSD** |
| `osdcap.sh <label>` | HDMI capture-card frame into `shots/<label>.png` — **the only way to see the OSD** |
| `vjoyd.py` | virtual gamepad daemon on the MiSTer, fifo-driven; see header for deploy and button names |
| `../mister-vjoy.py` | one-shot virtual pad press — only useful when a pad was already bound at core load; for anything else use `vjoyd.py` |

Audio capture (MS2109 card): `arecord -D hw:3,0 -f S16_LE -r 48000 -c 2 -d 12 out.wav`.

Loading a core / MGL without the OSD: `ssh root@$MISTER "echo 'load_core /media/fat/<path>' > /dev/MiSTer_cmd"`.
An MGL that mounts disks needs a `<reset delay="1" hold="1"/>` or they never boot.

## JIS layout facts (established by experiment, encoded in `type.py`)

- `:` is keycode 40 (the US apostrophe slot)
- `"` is Shift+2, `(` Shift+8, `)` Shift+9
- `vsim`'s `--key` text path silently drops what it cannot map; raw scancodes
  do not lie

## Traps

1. **MiSTer enumerates input devices at core load.** A virtual pad must exist
   *before* `load_core` or it is never bound — hence `vjoyd.py` is a daemon.
2. **`shoot.sh` cannot see the OSD** — the MiSTer composites core video before
   the overlay. Use `osdcap.sh`.
3. **The capture card emits black until it syncs.** `osdcap.sh`'s
   `select=gte(n,40)` frame-skip is required, not decoration.
4. **Menu positions shift when `CONF_STR` changes.** `Mount Disk 2` added a
   row: pre-two-drive builds need 4 downs to Boot ROM, current head needs 5.
   A hardcoded count silently lands on Aspect ratio. **This bit twice** —
   `osdkey.py` still carried the 4-down count as late as `af63b45`. The row map
   at HEAD is in `osdkey.py`'s docstring; update it there when `CONF_STR`
   changes. Current: Boot ROM = 5 downs, Machine = 6, and "Reset and close OSD"
   is 4 further from Boot ROM / 3 from Machine.
5. **Do not verify and measure in the same run.** An OSD capture between
   setting an option and resetting inserts 10–60 s and broke OS-9 booting —
   false failures only, and a wrongly reported "OS-9 does not boot at all".
6. **Screenshot byte size is not a pass/fail signal.** A garbage frame
   measured 7444 bytes against a 5.3 KB banner. Compare against a reference
   image and score *lit* pixels separately (`score.py`); re-bless when output
   resolution changes. A fully black 640x200 frame is **1771 bytes, 0.00% lit,
   1 colour** — that exact triple is the blank signature.
7. **`ssh` without `-n` eats the caller's stdin.** A `while read ... done < list`
   loop driving `runtest.sh` ran **one** of 30 titles and then exited 0 with a
   completion message. Every `ssh` in these scripts uses `-n`, and loops should
   read their list on fd 3. A green run that tested almost nothing is the worst
   failure mode in this directory.
8. **A low lit-% is not automatically a fault — look at the picture.** In one
   30-title sweep, five separate "suspiciously small" captures were all correct:
   a Japanese chapter menu, an aircraft data screen, a sparse vector demo frame,
   a title-plus-menu, and the `How many disk drives?` prompt.
9. **`{boot DOS mode}` disks need Boot ROM bank 2**, which `runtest.sh` does not
   set. OS-9 captured through a plain MGL load is a black screen and means
   nothing; drive it with `osdkey.py 2` and it reaches its `Time ?` prompt.

## The game-independent joystick probe

From F-BASIC (`docs/IO_MAP.md`), select stick 0 and read port A:

```
poke64782,15:poke64781,3:poke64781,0:poke64782,32:poke64781,2:poke64781,0:poke64782,14:poke64781,3:poke64781,1:?peek(64782)
```

`255` = no stick reaching the core; `238` = up + trigger 1; `222` = up +
trigger 2 (what `vjoyd.py`'s `upa` produces). For stick 1, write `80`
instead of `32`. F-BASIC's own `STICK()` never touches these ports and
always returns 0 — it cannot be used to test them.
