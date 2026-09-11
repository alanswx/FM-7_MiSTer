# Fujitsu FM-7 for MiSTer

The **FM-7** (1982) was Fujitsu's big seller in Japan — a two-CPU machine with
an MC6809 running F-BASIC and a *second* MC6809 that does nothing but drive the
display and the keyboard. It ran one of the strongest Japanese games libraries
of the early 80s, and almost none of it ever left Japan.

This core also runs the **FM77AV**, the 1985 successor with 4096 colours, a
hardware drawing engine and a YM2203 — still marked experimental, but it boots
and plays.

![FM-7 keyboard map](docs/keyboard.svg)

## What works

* **F-BASIC** from ROM, and disk BASIC from a `.d77` / `.d88` floppy
* **Games** — the whole FM-7 disk collection has been checked against a
  reference emulator, 395 of 395 images
* **OS-9 Level 1** boots to its shell (Boot ROM bank 2)
* **Cassettes** — `.t77` tape images load and run
* **Two floppy drives**, and multi-disk container images
* **FM77AV mode** — 320×200 in 4096 colours, the drawing ALU, the analog palette
* **Sound** — PSG on the FM-7, YM2203 FM on the AV
* **Joysticks**, two ports, two buttons each
* **Kanji ROM**, the full 128 KB JIS set
* **Spanish Secoinsa FM-7**, selectable at run time

## Installing

| copy this | to here |
|---|---|
| `releases/FM-7_<date>.rbf` | `/media/fat/_Computer/FM-7.rbf` |
| `releases/boot.rom` | `/media/fat/games/FM-7/boot.rom` |
| `releases/boot1.rom` | `/media/fat/games/FM-7/boot1.rom` *(optional)* |

Put your `.d77`, `.d88` and `.t77` files under `/media/fat/games/FM-7/` too.

> **The ROM files go in `games/FM-7/`, not next to the `.rbf`.** MiSTer looks
> for them in the core's games folder. A `boot.rom` sitting beside the core is
> silently ignored — and without it, anything that draws kanji shows garbage.

## Getting started

Load the core with no disk and you get F-BASIC. Type `print 1+1`, press Enter.

To run a game, open the OSD (**F12**), pick **Mount Disk 1**, choose a `.d77`,
then **Reset**. Most disks boot on their own from there.

A few things that catch people out:

* **Mounting a disk does not reboot the machine.** That is deliberate — games
  that ask you to swap disks mid-play would restart otherwise. Hit **Reset**
  after mounting if you want to boot from it.
* **Some disks need a different Boot ROM.** If a disk sits there doing nothing,
  try **Boot ROM → 2 dos-a**. OS-9 disks need this one.
* **Tapes are slow, because tapes were slow.** A `.t77` takes around six
  minutes of machine time to load. Mount it, type `run""`, and wait. Turn on
  **Tape Audio** if you want to hear it working.

## The OSD

| option | what it does |
|---|---|
| **Load Tape** | mount a `.t77` cassette image |
| **Mount Disk 1 / 2** | mount a floppy in drive 0 / drive 1 |
| **Disk 1 / 2 image** | pick which disk inside a multi-disk container file |
| **Tape Rewind** | rewind the cassette to the start |
| **Tape Audio** | hear the tape while it loads |
| **Boot ROM** | `0 disk` boots floppies, `2 dos-a` boots OS-9 |
| **Machine** | FM-7, or FM77AV (experimental) |
| **System ROM** | Japanese or Spanish system ROMs — see below |
| **Aspect ratio** | original 4:3, or fill the screen |

## Keyboard

The FM-7's keyboard is **JIS**, and this core keeps the real machine's key
*positions*. That means some keys type a different character than your PC key
cap says — most of the shifted punctuation, and the brackets.

The [keyboard map](docs/keyboard.svg) above shows all of it. The ones people
hit first:

| you press | you get |
|---|---|
| `Shift`+`2` | `"` (not `@`) |
| `Shift`+`7` `8` `9` | `'` `(` `)` |
| `[` | `@` |
| `]` | `[` |
| `'` | `:` |
| `Shift`+`;` | `+` |

And the special keys:

| PC key | FM-7 key |
|---|---|
| **Left Alt** | **GRAPH** — the semigraphics character set |
| **Right Alt** | **KANA** — locking toggle for katakana |
| **Right Ctrl** | **BREAK** — stops a running BASIC program |
| Page Up / Page Down | EL (erase line) / CLS |
| F1–F10 | PF1–PF10 |

Caps Lock does nothing, and the numeric keypad is not mapped.

## Joysticks

Two ports, mapped to MiSTer players 1 and 2, with **Button A** and **Button B**.
Plenty of FM-7 games are keyboard-only — of 301 disk images, only 25 ever read
the joystick ports at all, so if a game ignores your pad it is probably the game.

## Spanish Secoinsa FM-7

Secoinsa built and sold the FM-7 in Spain under licence, with a Latin character
set in place of katakana and a slightly different F-BASIC. Install `boot1.rom`
and set **System ROM** to **Set 1** to run it — `Ñ`, `Ç` and `¿` appear where
katakana would be.

You can build your own ROM sets for other variants; the file format is in
[docs/ROMSETS.md](docs/ROMSETS.md).

## Known limitations

* **2DD floppies are not supported** — 2D only
* Multi-disk containers can only reach disks in the **first 1 MB** of the file;
  beyond that the selector clamps to the last reachable disk
* **FM77AV mode is experimental.** It boots and plays, but it is newer than the
  FM-7 side and less tested
* The **AV keyboard** is not wired up — AV-native titles that expect the AV's
  own key encoder will not see keypresses
* One tape, **Crash Ball**, reports `Device I/O Error` after finding its header
* **Xanadu Scenario II disk D** does not load
* PSG pitch is about **0.4 of a semitone flat**, from an integer clock divider
* The FM77AV's FM sound clock has not been verified against a reference

## Thanks

Based on [pcornier](https://github.com/pcornier)'s original FM-7 core.
Sound uses [jotego](https://github.com/jotego)'s jt12/jt49. Verified against
Takeda Toshiya's common source project, CaptainYS's 77AVEMU, and MAME.

## Licence

GPLv3 — see [LICENSE](LICENSE) and [LICENSE-NOTICE.md](LICENSE-NOTICE.md).
ROM images are not GPL and belong to their respective owners.

---

*Working on the core itself? [DEVELOPING.md](DEVELOPING.md) is the developer
reference — build, simulate, test and verify. Read
[docs/REFERENCE.md](docs/REFERENCE.md) before changing anything.*
