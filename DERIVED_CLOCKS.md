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

**Edge-detecting the raw strobe is not enough.** The snippet above is the
minimum shape, not the recommended one. A decode glitch is one or two `CLKSYS`
cycles wide, and a one-cycle edge detector sees a glitch as an edge — which is
the very thing being fixed. Filter the strobe through a short shift register
and take the edge from the *filtered* copy, so a transient has to persist to be
believed:

```verilog
reg [2:0] strobe_sr;
always @(posedge CLKSYS) begin
  strobe_sr <= { strobe_sr[1:0], WFD05n };
  if (~RESETBn)                            m9 <= 3'd0;
  else if (strobe_sr[2] & ~strobe_sr[1])   m9 <= { ... };   // filtered leading edge
end
```

All four conversions landed so far (`b34171e`, `649d054`, `5cae28c`, `b632ea1`)
use this shape. The sample then lands two `CLKSYS` cycles into the strobe rather
than exactly on its edge; `E`-high is about 19 `CLKSYS` cycles, so that is still
comfortably inside the access and no longer at the instant the decode settles.

Four things to get right:

1. **Sample on the LEADING edge of the strobe**, i.e. the falling edge of an
   active-low one. Several of these registers historically latched on the
   *trailing* edge, which is separately the P1-4 hazard: by then the CPU may
   already have released the bus. `$fd37` read back `$00` forever for exactly
   that reason (TODO.md P1-4). Converting to `CLKSYS` fixes both problems at
   once, so do not preserve a trailing-edge sample "for fidelity".

   **Known exception: `KEYBOARD.v`'s `m77`.** Both edges were tried on hardware
   and both regressed OS-9 — see the open item below. Do not assume this rule
   holds for a register whose data comes off a wide combinational mux.
2. **An edge cannot be missed.** `E` is 1.2288 MHz against a 48 MHz `CLKSYS`, so
   every strobe is tens of clocks wide.
3. **Preserve clear/set dominance.** If the original had a level-sensitive async
   clear that overrode the clock, keep the clear first in the `if` chain.
4. **The module may not have a clock port.** Add `input CLKSYS` and wire it in
   `core.v`. Both top levels instantiate `core`, so nothing else changes.

## Remaining instances, highest risk first

**Done and confirmed on hardware:**

| file | register | commit |
|---|---|---|
| `FLAGS.v` | `m56_5`, `m56_9`, `m45`, `m44_5` | `3f85852` |
| `PERIPHERAL.v` | `m10`, `m2`, `m9` | `b34171e` |
| `MFD.v` | `m6_q` (FDC IRQ mask) | `649d054` |
| `PAL.v` | palette read-back | `5cae28c` |
| `MB60H010.v` | `SRL`/`SRH` (display offset) | `b632ea1` |
| `FLAGS.v`, `PERIPHERAL.v` | three-cycle filters replacing the one-cycle edge detectors | `18e635c` |

**Still open:**

| file | register | clocked by | drives | status |
|---|---|---|---|---|
| `KEYBOARD.v:543` | `m77` | `posedge WFD02n` | keyboard routing (`KEYINn`/`KSTROBEn`), `LPMASKn`, `TMMASK` | **two hardware attempts, both regressed OS-9 — see below** |
| `SOUND.v:28` | `bdir`/`bc1` | `posedge WFD0Dn` | PSG bus protocol → all sound and both joysticks | not attempted; **not verifiable from the hardware side** (see below) |
| `FLAGS.v:228` | `m46` (`$fd37`) | `negedge WFD37n` | VRAM plane access + display masks | P1-4 already moved it; needs a check, not a conversion |

### `KEYBOARD.v` `m77` — open, and it breaks rule 1

**Three** conversions have now been built, flashed and tested. All three
regressed OS-9, **0 boots in 8 tries each**, against baselines on the
immediately preceding commit that booted within 5:

| attempt | where it sampled | result |
|---|---|---|
| recipe verbatim | leading edge, `wfd02_d & ~WFD02n` | 0/8 |
| trailing edge | strobe filtered, `MDATA_in` tracked while low, committed on release | 0/8 |
| `0ce7ad3` mid-strobe | stably low for 3 cycles, commit once, re-arm after 3 high | 0/8 |

So **the sample point is not the variable** — leading, trailing and middle all
fail. A fourth position is unlikely to be worth a build. All three failures
showed the partial-boot signature (`* System Module Loading Completed !` and no
further), which only appears once bank 2 has been selected and OS-9 has actually
started, so this is a real behavioural change and not a mis-set boot ROM.

None of the three is in the tree. The first two were never committed; `0ce7ad3`
was reverted by `e443a02` after being isolated from `18e635c`, which arrived in
the same pull and is good on hardware.

#### The measurement that says where to look instead

`m77` is **not** parked at its reset value during an OS-9 run, so the three
designs are not behaviourally identical for it and what each one *captures*
is the live variable. `--trace-mem fd02-fd02` over 900 frames at `--bootrom 2`:

```
147 mem  R $fd02 -> $fe   pc=$fbc5
147 mem  W $fd02 <- $00   pc=$fbc5
332 mem  W $fd02 <- $01   pc=$d261
```

Two writes in 900 frames — which is why this is easy to grep past; TODO.md
already records that OS-9 writes `$fd02` after all, and this is the trace behind
it. The final value is `$01`, bit 0 **set**, routing the keyboard to the main
CPU.

**The experiment that does not need hardware:** probe `m77` across the write at
**frame 332, `pc=$d261`** under all four designs — original, leading, trailing,
mid-strobe — and compare what lands against the `$01` on the bus. If a
conversion captures anything else there, that is the bug, and it is a
*data-capture* question rather than a glitch question, so `vsim` can see it.
The hardware stall is consistent with the keyboard ending up on the wrong CPU.
Worth checking the `$00` at frame 147 the same way: it is boot-ROM code
(`pc=$fbc5`), so the `$00`→`$01` ordering may matter too.

The standing lead also remains: `m77` alone takes its data from `MDATABUS_out`,
a wide combinational mux over the whole main bus, where every other converted
register reads a narrower source. If that mux only presents write data during
part of the cycle, no fixed `CLKSYS` sample point reproduces the original edge
and the fix has to come from the data side.

Untested lead for the simulation side: `m77`'s `MDATA_in` is wired to
`MDATABUS_out`, a wide combinational mux over the whole main bus rather than a
plain write-data bus. Every other converted register takes its data from a
narrower source. If the mux only presents the CPU's write data during a specific
part of the cycle, then *no* fixed `CLKSYS` sampling point reproduces what the
original edge captured, and the fix has to come from the data side rather than
the clock side. That question is behavioural, so it is reproducible in `vsim`
even though the glitch itself is not.

### `SOUND.v` — cannot be validated from the hardware side

`bdir`/`bc1` drive the PSG bus protocol, so they carry **all sound and both
joysticks**. The hardware loop in use is screenshot-based: it can confirm a
build boots, but it cannot observe audio or joystick input at all. A green boot
on a `SOUND.v` change would therefore prove nothing about the thing changed.
Whoever converts this needs a listening test or a joystick test, not a
screenshot.

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
- **A `.t77` mounted at ioctl index 1**, then `LOAD"` at the F-BASIC prompt →
  `Searching` → `Found: <name>`. This is the test for `PERIPHERAL.v`: `m10` *is*
  the tape motor register and `$fd02` bit 7 is the cassette input, so a
  conversion there is exercised end to end by nothing else on this list. Note
  the FM-7 is a **JIS layout** — `"` is Shift+2, not Shift+apostrophe, which
  types `*` and earns a `Syntax Error`.
- **Any title with sound**, and a joystick — exercises `SOUND.v`. A
  screenshot-based loop cannot do this; see the `SOUND.v` note above.
- **Thexder / Hydlide II / Xevious / Tritorn** — exercise the display path and
  the shared window. For display-adjacent changes (`PAL.v`, `MB60H010.v`) these
  are strongest as an exact comparison: Archon and Hydlide II came back
  **byte-identical** across those two conversions, which rules out a shifted
  offset or a wrong palette entry pixel for pixel.

If a conversion breaks something on hardware, **revert that one commit** and say
so; do not try to fix it blind. The sim side can then reproduce the *behavioural*
half and re-derive.

### Two traps in the hardware loop itself

Both of these produced a confidently wrong result before being caught. Anyone
reading a hardware verdict on this bug class needs to know they exist.

**Screenshot byte size is not a pass/fail signal.** The OS-9 banner is about
5.3 KB, so "bigger than 5 KB" looks like a reasonable test for it. A *garbage*
screen measured **7444 bytes** and was reported as a successful boot. Compare
against a known-good reference image instead, and score the lit pixels
separately from the whole frame — most of the screen is black, so a garbage
frame still matches ~95% overall while matching 0% of the banner text. The three
states then separate cleanly:

| state | overall | text pixels |
|---|---|---|
| banner (booted) | 100% | 100% |
| `System Module Loading Completed` and stalled | ~99% | ~39% |
| garbage / wrong boot ROM | 95–98% | 0% |

**Selecting boot ROM 2 from the OSD succeeds about one try in three.** The
`confirm` presses that cycle the option get dropped, so a single failed OS-9 run
carries no information whatever. Any verdict needs a retry loop that keeps
relaunching until the banner is actually matched, and a "did not boot" claim
needs enough tries to be meaningful — 8 failed tries against a baseline that
booted within 3 is about the minimum worth reporting.

Driving the OSD with raw Linux keycodes (`kbdRawDown:108` etc.) does **not**
work: those go to the emulated FM-7's keyboard, not to the MiSTer menu. Only the
named actions (`kbd:down`, `kbd:confirm`) drive the OSD. This matters because
the raw-keycode attempt still produced plausible-looking results — a title going
blank, which read as "the boot ROM changed" — while never having navigated the
menu at all.

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
