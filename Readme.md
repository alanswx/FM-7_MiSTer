# FM-7 for MiSTer

A core for the **Fujitsu FM-7** (1982), a Japanese home computer with two
MC6809 CPUs — a main CPU running F-BASIC or a disk OS, and a sub CPU that owns
the display and keyboard. The two talk through a shared RAM aperture and a
halt/BUSY handshake.

Based on pcornier's original core, with FDC (`.d77` floppy) support and
extensive main/sub and interrupt-path work.

## State

Boots F-BASIC from ROM, cassette and disk; runs games from `.d77`; boots OS-9
Level 1 to its shell.

**197 of the 350 FM-7 floppy images in the Neo Kobe collection render a real
screen.** That raw figure includes secondary data disks, save disks, `[b]` bad
dumps and images whose boot sector deliberately halts — see
[docs/TESTING.md](docs/TESTING.md) for how to count honestly.

Verified working against the reference emulators: the FDC, the main/sub
handshake and its BUSY completion flag, the shared-RAM aperture, the full
keyboard (both routings, shift/ctrl/graph/kana/break), the kanji ROM, the
boot-ROM bank select, the PSG and joysticks, and the main-CPU interrupt path.

## Quick start

### Simulation (fast, this is where most work happens)

```sh
cd vsim
make                     # verilator build
./run_tests.sh           # 8-row regression suite, compares against shots-ref/
./obj_dir/Vemu --headless --bootrom 0 --disk game.d77 \
    --screenshot 680 --stop-at-frame 700
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

## Repository layout

| path | what |
|---|---|
| `rtl/` | the core |
| `vsim/` | Verilator simulation harness, regression suite, sweep tooling |
| `vsim/sweep/` | breadth-sweep scripts and recorded results (`.tsv`) |
| `docs/` | reference documentation — see below |
| `refs/` | reference emulator sources, vendored for citation |
| `software/` | disk and tape images (not distributed) |

## Documentation

| file | what |
|---|---|
| [TODO.md](TODO.md) | open work, current |
| [docs/REFERENCE.md](docs/REFERENCE.md) | how to work on this core without repeating known mistakes |
| [docs/IO_MAP.md](docs/IO_MAP.md) | `$fdxx` register facts, with citations |
| [docs/TESTING.md](docs/TESTING.md) | the regression suite and the breadth sweep |
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
