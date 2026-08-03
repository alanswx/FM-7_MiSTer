# Flip-flops clocked by decode strobes — a hardware-only bug class

**Read this before touching any `always @(posedge <something-that-is-not-a-clock>)`
in `rtl/`.** It documents a defect class that is **invisible in simulation** and
has already cost one hardware regression. It is written as a handoff between two
workers with different verification loops:

- **the hardware side** can build a `.rbf` with Quartus, flash a MiSTer and see
  the real behaviour — but has a slow edit/test cycle;
- **the simulation side** can run `vsim` and a 350-image sweep in minutes — but
  **structurally cannot observe this bug at all.**

Neither side can finish this alone. That is the whole reason this file exists.

---

## The defect

Large parts of `rtl/` are a transliteration of the FM-7 schematic, where a
74LS74 is genuinely clocked by a 74LS138's chip-select output. Written directly
in Verilog that becomes

```verilog
always @(posedge SCRTSWn, posedge s0)
  if (s0) m56_5 <= 1'b1;
  else    m56_5 <= SRWB;
```

`SCRTSWn` is not a clock. It is a 74138 output, i.e. **combinational logic over
the address bus**.

| | |
|---|---|
| **Verilator** | evaluates the decode once per delta cycle and produces exactly one clean edge per bus access. The RTL behaves perfectly. |
| **Quartus** | infers a flip-flop whose clock is a LUT output on general routing. A LUT-built address decode **glitches** as its inputs arrive skewed, and **every glitch is a spurious clock edge.** |

So the register latches at moments that do not exist in simulation. On real
hardware it captures garbage; in `vsim` it never misbehaves, no matter how long
you run it or how many titles you sweep.

**A green simulation is not evidence about this class of bug.** If you take one
thing from this document, take that.

## The confirmed case

`core.v` passed a literal `1'b0` for `FLAGS`' `SRESETn` pin. Every asynchronous
clear in that module derives from that pin, so **four** flip-flops sat
permanently held in reset — and their glitchy clocks had nothing to clock, so
the latent defect was harmless.

Commit `f9548d8` untied it (correctly — `SUBIRQn` could never assert, so the sub
CPU could never take the main's attention interrupt). That released all four.

**OS-9 immediately regressed on real hardware while remaining perfect in
simulation.** That asymmetry *is* the diagnosis.

Two of the four are load-bearing:

| flop | drives | a spurious edge does |
|---|---|---|
| `m56_5` | `SVDOFFn` → `PAL.v`'s `m25_3 = ~(SVDOFFn & SBLANKn)` | **blanks or corrupts the display** |
| `m45` | `SUBIRQn` | fires a spurious interrupt at the sub CPU |

Commit `3f85852` moved all four onto `CLKSYS` with the strobes edge-detected.
**Confirmed fixed on hardware.**

## The conversion recipe

Replace the derived clock with `CLKSYS` plus an explicit edge detector. Keep the
original semantics exactly — this is a *clocking* change, not a behaviour change.

```verilog
// before
always @(posedge WFD05n or posedge reset)
  if (reset) m9 <= 3'd0;
  else       m9 <= { MDATABUS_in[7:6], MDATABUS_in[0] };

// after
reg wfd05_d;
always @(posedge CLKSYS) begin
  wfd05_d <= WFD05n;
  if (~RESETBn)          m9 <= 3'd0;
  else if (wfd05_d & ~WFD05n)                  // falling edge = leading edge
                         m9 <= { MDATABUS_in[7:6], MDATABUS_in[0] };
end
```

Four things to get right:

1. **Sample on the LEADING edge of the strobe**, i.e. the falling edge of an
   active-low one. Several of these registers historically latched on the
   *trailing* edge, which is separately the P1-4 hazard: by then the CPU may
   already have released the bus. `$fd37` read back `$00` forever for exactly
   that reason (TODO.md P1-4). Converting to `CLKSYS` fixes both problems at
   once, so do not preserve a trailing-edge sample "for fidelity".
2. **An edge cannot be missed.** `E` is 1.2288 MHz against a 48 MHz `CLKSYS`, so
   every strobe is tens of clocks wide.
3. **Preserve clear/set dominance.** If the original had a level-sensitive async
   clear that overrode the clock, keep the clear first in the `if` chain.
4. **The module may not have a clock port.** Add `input CLKSYS` and wire it in
   `core.v`. Both top levels instantiate `core`, so nothing else changes.

## Remaining instances, highest risk first

`rtl/FLAGS.v` is **done and confirmed on hardware** (`3f85852`).

`rtl/PERIPHERAL.v` (`m10`/`m2`/`m9`) is **converted and committed but NOT yet
tested on hardware** — see the commit for the reasoning. `m9` was the most
exposed register left in the core: it holds `SUBHALTREQn` and `CANCELn`, so a
spurious edge either halts the sub CPU or fires an attention interrupt at it,
and `FLAGS`' `m45` now edge-detects `CANCELn`. **Flash and smoke-test this one
before converting anything else.**

| file | register | clocked by | drives | trailing edge? |
|---|---|---|---|---|
| `KEYBOARD.v:543` | `m77` | `posedge WFD02n` | keyboard routing (`KEYINn`/`KSTROBEn`), `LPMASKn`, `TMMASK` | **yes** |
| `SOUND.v:28` | `bdir`/`bc1` | `posedge WFD0Dn` | PSG bus protocol → all sound and both joysticks | **yes** |
| `MB60H010.v:52,55` | sub display regs | `negedge SREGLn` / `SREGHn` | display offset | no |
| `FLAGS.v:228` | `m46` (`$fd37`) | `negedge WFD37n` | VRAM plane access + display masks | no (P1-4 already moved it) |
| `PAL.v:44` | palette | `negedge RDQEn` | palette register file | no |
| `MFD.v:65` | FDC latch | `posedge m13_6` | floppy register access | — |

**These are not six bugs.** Every one has been live since the beginning and the
machine works on hardware today, so the routing evidently tolerates them as
built. What made the `FLAGS` four bite is that something *changed* near them.
The narrow rule that follows:

> **Never release a held flip-flop, or re-time anything near one of these,
> without converting its clock first.**

Converting the rest is worthwhile hardening, not an emergency.

## How to verify — and what each side can and cannot prove

**Do one file per commit.** If hardware ever objects, that gives a clean bisect
instead of unpicking a six-register sweep.

| step | who | proves |
|---|---|---|
| `cd vsim && make && ./run_tests.sh` | sim side | **only** that behaviour did not change. All 8 rows must stay byte-identical. This is a guard rail, not validation. |
| 350-image sweep (`vsim/sweep/sweep.sh`) | sim side | same — a regression detector, blind to glitches |
| build `.rbf`, flash, run | **hardware side** | **the only real test of this bug class** |

Good hardware smoke tests, chosen because each exercises a different converted
register:

- **OS-9 Level 1** at `--bootrom 2` → should reach the `OS9:` shell and run
  `dir`. This is the case that caught the `FLAGS` bug.
- **F-BASIC** boot, then type — exercises `KEYBOARD.v`'s `m77`.
- **Any title with sound**, and a joystick — exercises `SOUND.v`.
- **Thexder / Hydlide II / Xevious / Tritorn** — exercise the display path and
  the shared window.

If a conversion breaks something on hardware, **revert that one commit** and say
so; do not try to fix it blind. The sim side can then reproduce the *behavioural*
half and re-derive.

## House rules that apply to any change here

- **`rtl/FLAGS.v`, `rtl/MFD.v`, `rtl/SRAM.v`, `rtl/ROMS.v`, `rtl/CLKCTRL.v`,
  `files.qip` and `FM-7_MiSTer.qsf` are CRLF** and must stay that way. Check
  with `file` after any scripted edit. `rtl/PERIPHERAL.v` is CRLF too.
- **`files.qip` is the canonical Quartus file list**, not the `.qsf`. Any new
  module goes there. The IDE re-injects a duplicate per-file list into the
  `.qsf` whenever the project is opened in the GUI — delete that when it
  reappears.
- `vsim` has its own list in `vsim/Makefile`.
- **`vsim` must be run from `vsim/`** or every ROM silently fails to load — see
  measurement trap 9 in TODO.md.

## Why this is worth the trouble

The FM-7 schematic really does clock those 74LS74s from 74LS138 outputs, and on
real 1982 hardware that is fine: propagation delays are matched and the decode
does not glitch the way a modern LUT does. Transliterating it is faithful and
wrong. Every one of these registers is a small, silent hardware-only failure
waiting for the next unrelated change to expose it — and because simulation is
clean, the next person will lose a day before suspecting the clock.
