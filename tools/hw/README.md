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
| `osdrows.py [label]` | the OSD row map, parsed from `CONF_STR` — the fix for trap 4; `FM7_TOP` points it at another commit's top file |
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
4. **Menu positions shift when `CONF_STR` changes — this has now bitten THREE
   times.** `Mount Disk 2` shifted every row down one (4 downs to Boot ROM
   became 5); `4b447f3`'s `Disk 1 image` / `Disk 2 image` shifted them two more
   (5 became 7). A stale count does not error — it selects a different item, so
   the run "succeeds" having set the wrong option.

   **Fixed structurally: nothing hardcodes a count any more.** `osdrows.py`
   parses `CONF_STR` out of `FM-7_MiSTer.sv` and `osdkey.py` / `avtoggle.py`
   ask it for the row they want, printing what they resolved. Run
   `./osdrows.py` to see the current map, or `./osdrows.py "Boot ROM"` for one
   index.

   **The catch that remains: the OSD is drawn by the core ON THE BOARD, not by
   your working tree.** If the deployed rbf came from a different commit, point
   the scripts at that commit's top file, or they will confidently resolve the
   wrong row:

   ```sh
   git show <deployed-commit>:FM-7_MiSTer.sv > /tmp/top.sv
   FM7_TOP=/tmp/top.sv ./avtoggle.py
   ```
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
