# FM-7 for MiSTer

A core for the **Fujitsu FM-7** (1982), a Japanese home computer with two
MC6809 CPUs — a main CPU running F-BASIC or a disk OS, and a sub CPU that owns
the display and keyboard. The two talk through a shared RAM aperture and a
halt/BUSY handshake.

Based on pcornier's original core, with FDC (`.d77` floppy) support and
extensive main/sub and interrupt-path work.

## State

Boots F-BASIC from ROM and disk; runs games from `.d77`; boots OS-9 Level 1 to
its shell. FM77AV mode boots and renders, including 320x200 4096-colour titles.

**The whole FM-7 disk collection has been swept against a reference: 395 of 395
distinct images (100%).** Each was screened for which machine it is really for,
run on that machine, and scored against a 77AVEMU render taken at the same
machine-time instant. That found **seven core bugs in 395 disks, six of them
fixed**; the last three cohorts found none. Most images that render nothing here
render nothing on the reference either — they are data disks, save disks, `[b]`
bad dumps, or their boot sector deliberately halts. See
[docs/TESTING.md](docs/TESTING.md) for the method and
[docs/HANDOFF.md](docs/HANDOFF.md) for the per-cohort results.

On the FM77AV side, **no title in the 68-image set renders blank where the
reference draws**: 30 MATCH, 0 CORE-BLANK, 0 CORE-WORSE.

Verified working against the reference emulators: the FDC, the main/sub
handshake and its BUSY completion flag, the shared-RAM aperture, the full
keyboard (both routings, shift/ctrl/graph/kana/break), the kanji ROM, the
boot-ROM bank select, the PSG and joysticks, the main-CPU interrupt path, and
the AV memory-management unit, analog palette and drawing ALU.

**Not yet proven on hardware.** The design fits the DE10-Nano and closes timing,
but the last 151+ commits have only ever been run in simulation. Cassette
loading is unresolved — see `TODO.md` item 0 — and 2DD media and multi-disk
`.d88` are not supported.

## Quick start

### Simulation (fast, this is where most work happens)

```sh
cd vsim
make                     # verilator build
./run_tests.sh           # 8-row regression suite, compares against shots-ref/
./obj_dir/Vemu --headless --bootrom 0 --disk game.d77 \
    --screenshot 680 --stop-at-frame 700
./obj_dir/Vemu --headless --disk game-a.d77 --disk1 game-b.d77 \
    --stop-at-frame 700
./obj_dir/Vemu --help    # full flag list
```

**`vsim` must be run from `vsim/`** — the ROM loaders use relative paths and
Verilator treats a failed `$readmem` as a warning, so running it from elsewhere
silently gives you a machine with no ROMs. See [docs/REFERENCE.md](docs/REFERENCE.md).

`vsim/README.md` documents the harness in detail.

### Hardware

Quartus project in the repo root. **`files.qip` is the canonical file list**,
not the `.qsf` — the IDE re-injects a duplicate list whenever the project is
opened in the GUI.

Some bugs only appear on hardware: several flip-flops are clocked by 74138
address-decode outputs, which are clean in Verilator and glitchy ripple clocks
in Quartus. Simulation cannot see that class at all.

Builds run on `alans@cottageubuntu`, which has a working Quartus Prime 17.0.2
Lite at `~/intelFPGA_lite/quartus/bin` and a clone at `~/mister/FM-7_MiSTer`.
`quartus_sh --flow compile FM-7_MiSTer` works there directly:

```sh
ssh alans@cottageubuntu 'cd ~/mister/FM-7_MiSTer && git pull && \
  PATH=$HOME/intelFPGA_lite/quartus/bin:$PATH \
  quartus_sh --flow compile FM-7_MiSTer'
```

A full compile takes roughly an hour. Two Critical Warnings (127005) are
expected and benign: the AV boot loader really is 480 bytes in a 512-deep
memory, and `AVMEM.v:435` already guards `boot_offset < 480`, so the zeroed
tail is never read.

## Repository layout

| path | what |
|---|---|
| `rtl/` | the core |
| `vsim/` | Verilator simulation harness, regression suite, sweep tooling |
| `vsim/sweep/` | breadth-sweep scripts and recorded results (`.tsv`) |
| `tools/hw/` | hardware test harness — drive a real MiSTer headlessly (see its README) |
| `docs/` | reference documentation — see below |
| `refs/` | reference emulator sources, vendored for citation |
| `software/` | disk and tape images (not distributed) |

## Documentation

| file | what |
|---|---|
| [docs/HANDOFF.md](docs/HANDOFF.md) | **start here** — current state, the tools, and how not to waste the first hour |
| [TODO.md](TODO.md) | open work, current |
| [docs/CONTINUATION.md](docs/CONTINUATION.md) | per-title detail behind the handoff |
| [docs/REFERENCE.md](docs/REFERENCE.md) | how to work on this core without repeating known mistakes |
| [docs/IO_MAP.md](docs/IO_MAP.md) | `$fdxx` register facts, with citations |
| [docs/TESTING.md](docs/TESTING.md) | the regression suite and the breadth sweep |
| [tools/hw/README.md](tools/hw/README.md) | hardware harness: keys/screenshots/joystick against the real MiSTer |
| `vsim/README.md` | simulation harness detail |

**Read `docs/REFERENCE.md` before starting.** Its measurement-traps section is a
list of mistakes that each produced a confident wrong answer at least once in
this project. More bugs here were mis-diagnosed than were hard to fix.

## Reference emulators

Three, and they do not agree. In order of authority for the FM-7:

1. **CSP** — `refs/common-src-project/src/vm/fm7/`. Takeda Toshiya's common
   source project. The most complete FM-7. **Primary authority.**
2. **77AVEMU** — `refs/77AVEMU/`. Tiebreaker.
3. **MAME** — `refs/mame/src/mame/fujitsu/fm7.cpp`. The most readable I/O map,
   but an **unreliable** FM-7 driver. Never trust it alone.

Where they disagree, `docs/IO_MAP.md` records which one this core follows and
why.

**`releases/boot.rom` ships with the core.** It is the 128 KB kanji ROM,
which lives in SDRAM rather than block RAM and is uploaded by the MiSTer
framework on ioctl index 0 at core start. Without it the `$fd20-$fd23`
kanji window reads garbage; everything else still boots.

## Licence

GPL. The core's own files carry the MiSTer framework's "version 2 ... or (at
your option) any later version" grant, and `rtl/jt12/` is jotego's jt12/jt49
under GPL**v3**-or-later. The combination is permitted by that grant, and the
**combined work therefore ships as GPLv3** — see `rtl/jt12/LICENSE-jt12`.
`jt03` is the FM77AV's YM2203 and also supplies the FM-7's PSG, so removing it
is not an option that leaves a working core.
