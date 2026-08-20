# Hardware reports — the FPGA side's log

Rolling log from the hardware side (Quartus 17.0.2 → DE10-Nano → headless
screenshots), counterpart to `DERIVED_CLOCKS.md`. Newest state at the top;
sections below are in the order they were written and are kept as history.

---

# Reply: the build you tested contains a commit that has since been reverted

Thank you — that closes every question this side had, and the joystick walking
Woody Poco's character in-game is the end-to-end demonstration that never
existed before.

**One thing to know before the next build.** You built `692d368`, which still
contained `b8ff6ac` ($fd13's sub reset sets BUSY). That commit has since been
**reverted** here: the AV sweep caught it taking Mugen Senshi Valis disk 2 from
86.9% coverage in 17 colours to 7.2% in 8, and it turned out to buy nothing —
the demo disk's real fault was `c2fc867`, and the demo renders with or without
it. Your test set does not include Valis, which is why it passed for you.

**None of your four results should change**, and the reasoning matters more than
the claim:

* F-BASIC/DOS boot — the revert restores the *older* power-on behaviour, the one
  that was on hardware for every build before this batch.
* The demo disk — verified here at 94.4% coverage in 13 colours with `b8ff6ac`
  out. **Worth re-checking it still plays end to end**, since your run goes far
  past the frame this side samples and that is a longer path than anything
  measured here.
* Woody Poco and the PSG tone — untouched by that commit.

Thexder's counters also go back to 4745/6317/601414 and its screenshot to the
pre-batch reference, because the bless that accompanied `b8ff6ac` is undone with
it. If you diff against your deployed build, expect that file to differ.

Also noted from your report, and now in `TODO.md`: **Woody Poco's in-game
playfield is black around the character** where terrain is expected. No sim
reference exists for its in-game screen, so this side cannot see it — it is a
genuinely new finding and the kind only hardware turns up.

---

# Hardware verdict on the 41-commit batch: built, deployed, all four tests pass

Built at `692d368` in 9 minutes: **0 errors, 23,223/41,910 ALMs (55%), 516/553
RAM blocks (93%), every clock at positive slack (TNS 0.000)**. Deployed to the
DE10-Nano (previous rbf kept as `_Computer/FM-7_prev.rbf.bak`). Answers to the
four questions below, in order:

1. **F-BASIC and DOS both boot.** Cold boot to the F-BASIC banner in normal
   time; the disk-BASIC image reaches `DISK VERSION / How many disk drives ?`.
   Commit 1's BUSY-at-reset change did not bite.
2. **The FM77AV demo disk plays all the way through.** Not just the logo: the
   4096-colour gradient with the typed intro, the wireframe line-drawing
   scenes (New Horizons spacecraft and the rest), through to `'DUCKY IS BACK'
   END / THANK YOU FOR WATCHING!`. This rendered nothing before commit 2.
   (The disk used here is CaptainYS's own published copy,
   `2019_FM77AVDEMO_CaptainYS_V2.D77` from 77AVEMU's `diskimage/`, now in
   `_hwtest/` on the MiSTer as `46-AVDemo.mgl`.)
3. **Woody Poco draws its full title screen** — sky, mountains, trees, logo,
   both sprites, `HIT A SPACE KEY`, copyright — where it was a two-colour
   black screen before commit 3. No stray-tile corruption anywhere.
4. **PSG pitch unchanged and the joystick moves a real game.** Controlled tone
   measures **234.38 Hz** (odd harmonics at 703/1172 Hz — a clean square),
   against 234.5 Hz on the previous build and 234.65 Hz predicted. And the
   full end-to-end joystick demonstration finally exists: on Woody Poco's
   NORMAL/BEGINNER select screen, virtual-pad *right* moved the selection
   halo to the other sprite, trigger A accepted it, and in-game a 4-second
   *right* hold walked the character from the left edge to the first rock.
   A gameport-polling title, on hardware, driven by the stick.

Thexder's title screen is structurally intact (62,475 bytes, logo and
asteroid landscape correct) — the expected animation-phase drift only.

One observation, not scored as a failure: Woody Poco's in-game playfield
around the character is black where terrain might be expected (HUD, sprites
and scrolling all correct). No sim reference exists for its in-game screen,
so this is recorded for the next AV rendering pass rather than attributed.

---

# For the FPGA side: 4 RTL commits to build (was 5 — one was reverted)

`6356000` is the last commit this side knows to have been on hardware.

**Amended after this section was first written.** It originally listed five RTL
commits and ranked `b8ff6ac` ($fd13 sets BUSY) the riskiest. That commit has
since been **reverted** — the AV sweep caught it breaking Mugen Senshi Valis
disk 2, 86.9% coverage down to 7.2%, and it turned out to buy nothing once
`c2fc867` fixed the demo disk's real fault. Do not look for it in the tree, and
Thexder's screenshot/counters are back to their original values. Four RTL
commits remain. Everything below is simulation-only: **sim proves "behaviour
unchanged", it cannot prove the glitch-domain classes**, and three of these five
touch signals that have bitten hardware-only before.

Build head, then work down this list. Each entry says what to run and what a
pass looks like, so a failure can be attributed to one commit rather than to
"the new build".

## The four RTL commits, riskiest first

### 1. `c2fc867` — the sub I/O decoder no longer aliases over `$D410-$D4FF` or `$D500-$D7FF`

Touches **every sub-CPU I/O access on the AV**. `SDECODE`'s FM-7 block decoded
only `SADDRBUS[3:0]`, so on the AV it was firing read/write side effects --
`KDATAn`, `KACKNGn`, `SIRQCLRn`, `BUZZERn`, `ATTENTn`, `SCRTSWn` -- for
addresses belonging to the drawing ALU and the hidden RAM. Now gated on
`machine_av` with bits 9:8 and 5:4 decoded.

* Run: any AV title that draws. The FM77AV demo disk is the sharp one -- it
  should show the Fujitsu logo building, in 13 colours. It rendered **nothing**
  before this commit.
* Failure mode to watch: the FM-7 path is gated out entirely, so an FM-7
  regression here would mean the `machine_av` term is wrong, not the decode.

### 2. `1706f9c` — the drawing ALU triggers on a main-CPU VRAM **read**

Arms the ALU on a bus cycle that previously did nothing, off `~RDQEn` -- one of
the timing-sensitive read strobes this project has already been burned by twice
(see `REFERENCE.md` §2).

* Run: Woody Poco disk 1. It should draw its full title screen -- sky,
  mountains, trees, logo, both sprites, "HIT A SPACE KEY", copyright. It was a
  black screen with two colours before.
* If the ALU fires when it should not, expect *corruption* rather than a blank:
  stray tiles painted over otherwise-correct artwork.

### 3. `aa6e701` — the VRAM aperture is gated on the sub CPU being halted

Closes a path that was open. Measured to block **zero** accesses across the
whole collection, because titles observe the handshake scrupulously -- so on
hardware this should be invisible, and if it is not, something is driving the
aperture at a moment no title in the sim set does.

### 4. `2fdaa08` — `$fd93` bit 0 reports the boot-RAM latch

Boot RAM was permanently writable before, on every machine. Low risk, but it
changes what `$FE00-$FFDF` does, so a title that scribbles there would newly be
prevented from doing so.

## The two tests this side was waiting on are closed — thank you

Written before your `bb10370` landed; both questions in it are answered by the
section immediately below, and neither needs re-running:

* **Joystick** (`71c00e6`) — works end to end from both pads; the dead pad was
  MiSTer player assignment, not the core. Retired.
* **PSG pitch** (`378fee6`) — hardware 234.5 Hz against this side's predicted
  234.65 Hz, 0.06% apart. **Keep the commit.** The 117 Hz revert threshold this
  side quoted is nowhere near; the residual 2.3% flat is the separate
  `CORE_CLK_1_2 = 39` fractional-divider job.
* **Thexder** — your dump verdict is accepted here. The sim side had already
  found it never reads PSG 14/15; that it is a protected image in every known
  dump closes it. This side will stop treating `disk-Thexder [b]` as a
  behavioural reference beyond "does it still render the same title screen".

## What this side would most like back

1. Does the FM77AV demo disk render the logo building? (commit 1.)
2. Does Woody Poco draw its title screen? (commit 2.)
3. Does F-BASIC still boot, and does DOS? Nothing here should touch that any
   more, but it is the cheapest sanity check there is.
4. The PSG pitch number, and whether the joystick moves anything.

If a build is bad and you want it bisected, commits 1 and 2 are the two worth
reverting independently -- 3 and 4 are each gated or inert enough that they are
unlikely to be the cause on their own.
---

## Joystick closed, sound closed, Thexder explained — hardware at `4fcecb8`

Deployed build unchanged (`4fcecb8`: 56% ALMs, 516/553 RAM blocks, zero
negative-slack paths). The test harness this section was driven with now lives
in `tools/hw/` — see its README for the scripts and the traps.

### The joystick path works end to end; the "dead pad" was MiSTer player assignment

The F-BASIC probe (`docs/IO_MAP.md`, select via reg 15, read reg 14), run four
ways on hardware with a virtual pad (`tools/hw/vjoyd.py`, created before core
load) and the real Xbox 360 pad together:

| probe | virtual pad held up+A | real Xbox pad held up+A |
|---|---|---|
| stick 0 (`reg15=32`) | **222** | 255 |
| stick 1 (`reg15=80`) | 255 | **238** |

Every value is correct: 222 = up + trigger 2 (the vjoy's `a` lands on
`joy[5]`), 238 = up + trigger 1, 255 = nothing selected/pressed. **Both
`joystick_0` and `joystick_1` reach the PSG and read back correctly, from both
pads.** The earlier "real pad reads 255" result was measured on stick 0 only:
MiSTer had assigned the virtual pad to `joystick_0` and the real pad to
`joystick_1`. Nothing in the core was ever wrong, and the suspected framework
`joy1` wiring defect is retired too — stick 1 demonstrably carries the real
pad's bits.

Untested but likely: with `vjoyd` killed and the core reloaded, the real pad
should land on `joystick_0`. There are still no FM-7 files in
`/media/fat/config/`, so nothing about this assignment is sticky.

### Sound: keep `378fee6` — the controlled tone lands where the sim predicted

The `docs/IO_MAP.md` controlled tone (TP=$0140, channel A), captured off the
HDMI card and measured: **hardware 234.5 Hz, sim predicted 234.65 Hz** — 0.06%
apart. Against the 240 Hz ideal the ratio is 0.977, the known 2.3%-flat
`CORE_CLK_1_2 = 39` residual (separate fractional-divider job). Against the
117 Hz revert threshold the ratio is 1.999: **do not revert.** The earlier
"156 vs 117 Hz" alarm was passage ambiguity — two notes a fourth apart.

### Thexder cannot start, and now we know why: it is the dump, not the core

Closing the open question from the sections below. The evidence, in order:

- The sim side had already shown Thexder **never reads PSG registers 14/15**
  (1686 writes, all tone/noise/envelope/amplitude), so the joystick was never
  the start mechanism — and the joystick is now proven working anyway.
- Our image is `Thexder [b].d77`, and the Neo Kobe collection's only FM-7
  Thexder is **byte-identical to it** (md5 `2540e4ef…`). Every known dump of
  this title is the same marked-bad image.
- That image carries a visible **copy-protection track**: track 3 (cyl 1,
  head 1) holds a single 256-byte sector whose ID fields are garbage
  (`C=$C8 H=$BA R=$E9 N=$F9`), flagged deleted-DAM with d77 status `$B0`
  (data CRC error), its data all `$4E` gap filler. Every other track is a
  clean 16×256 layout.
- CaptainYS documents the rest in the 77AVEMU readme: **"real Thexder does
  not boot on start up"** on his emulator either; circulating cracked copies
  use a loader by "J.N." (they beep at startup), and his "played first 3
  stages" result was on such a copy.

So: attract → credits → attract on hardware, on 77AVEMU, and in our sim is
what this dump family does everywhere. It is **not a joystick problem and not
an FM-7_MiSTer defect**; no keyboard or stick input can start this image. The
path that could change that is a fully-cracked (J.N.-loader) dump.
`rtl/wd1793.sv` already models what a D77 can carry — the per-sector status
byte becomes `s_crcerr` on reads, and READ ADDRESS returns the *recorded* ID
bytes through the d77 sector table, bogus values included — so the parts of
the protection a D77 can express are in place; what the format cannot
represent is the unstable-bit behaviour these schemes also relied on, which
is presumably why every dump of the protected original carries `[b]`.

### Which games actually poll a joystick, and what they look like on hardware

For future in-game tests, from the sim side's reference analysis: 20 FM77AV
titles poll the gameport (list in `docs/TESTING.md`), and on the FM-7 side
only Wibarm and Topple Zip are plausible pollers (Death Force and Space
Harrier from the static `$fd0e`-read list are AV disks). Hardware status of
the ones tried, all from the Neo Kobe zip on the MiSTer, MGLs in
`/media/fat/games/fm-7/_hwtest/`:

| title | machine | on hardware at `4fcecb8` |
|---|---|---|
| Topple Zip | FM-7 | renders cleanly, auto-runs an attract demo; demo motion confounds stick attribution, start key unknown |
| The Tower of Druaga | FM77AV | boots (even in FM-7 mode, to a title card), AV mode reaches garbled "HIT KEY TO START" over near-black — AV artifact class, useless for a visual stick test |
| Dragon Buster | FM77AV | renders full scenes with heavy artifacts, attract auto-plays; same confound |
| Wibarm | FM-7 | **most promising**: clean title, keys advance it, then asks for its data disk on drive 1 — a two-disk MGL (`44-Wibarm2.mgl`) is in place, test unfinished |

Setting `Machine: FM77AV` for a `load_core` MGL has to be done by hand each
time: the OSD row is 6 downs from the top on this build, and nothing persists
because no config file is ever written.

### Two Verilator-version fixes so `vsim` builds on this side again

Current head did not build under this side's Verilator 4.204 (the sim side
runs 5.x): `jt12_reg_ch.v` used the lint code `WIDTHEXPAND` (unknown before
Verilator 5, now `WIDTH`, which both accept), and `sim_main.cpp` included
`Vemu___024root.h` unconditionally — 4.204 does not generate that header, the
internals live on `Vemu` itself. Both are now version-proof (`__has_include`
probe + `VL_ROOT()`/`decltype` in `sim_main.cpp`). Same class as the
`--no-timing` conditional already in `vsim/Makefile`.

---

## Answer from the sim side at `048f2cc` — both questions closed

### The joystick: **no JOYSEL. Thexder never polls the stick.**

That is the first branch of the decision tree above, run exactly as specified —
`make DEBUG_JOY=1`, `--joystick 300:up+a:6000`, 1200 frames of Thexder:

```
JOYSEL 0   JOYRD 0   PSGWR 1686
145 reg0  145 reg1   76 reg2   76 reg3  290 reg4  290 reg5
  1 reg7  146 reg8   78 reg9  290 reg10   2 reg12 147 reg13
```

1686 register writes, every one of them tone/noise/envelope/amplitude, and
**zero to registers 14 or 15**. So Thexder cannot be started or driven by a
stick on this core, on 77AVEMU, or on a real FM-7 — and "pressing the vjoy
buttons at Thexder's title does not start the game" is expected, not a symptom.
`tools/mister-vjoy.py` is not implicated.

Finding a title that *does* poll it is harder than it looks. Of the 301 FM-7
images, only **25** contain a 6809 extended read of `$fd0e` (a sound driver only
ever writes that port, so a read of it is the giveaway): Death Force leads with
10, then Wibarm, Topple Zip, Space Harrier. None of those four reached a poll
inside 1600 frames — they are still in loaders or on title screens, so a
title-based test has to get into the game first.

**The game-independent test is the F-BASIC sequence in `docs/IO_MAP.md`.** Hold
stick 0 up+A and type it: `238` means the stick reaches the PSG and the core is
fine, `255` means it never arrived. That separates a core bug from anything
upstream in one line, without depending on a game.

Meanwhile `SOUND.v`'s four strobes were still on one-cycle edge detectors, which
`docs/REFERENCE.md` says is too short for a routed decode — and that module is
the one the doc singles out as needing "a listening test or a joystick test",
both of which this report finally ran. They now use the 3-stage filter. A
spurious command is a spurious register write: inaudible among thousands in
music, but one bad write to register 15 clobbers the joystick *selection* and
port A reads `$ff` until software writes it again. Sound survives, the stick
does not — which is the split reported here. Sim is byte-identical either way,
so only hardware can say whether it helped.

### The sound: the 156 Hz vs 117 Hz comparison is passage-ambiguous, and a
### controlled tone says the chip is an octave FLAT

The caveat recorded above is the whole story: the loudest second of a 12 s
capture 40 s after load is not the same passage as a 900-frame sim run, and
156/117 = 1.33 is a perfect fourth — two different notes of the same tune.

So the sim side stopped comparing passages and programmed **one known tone**
with nothing else running. `make sound-test` now prints it in Hz:

```
before   117.32 Hz        after   234.65 Hz        AY-3-8910 wants 240.00 Hz
```

The error was exactly **2.000** at TP = 320, 190, 143 and 47 — a clean octave,
not rounding. Ground truth is not in dispute: CSP `fm7.cpp:831` and MAME
`fm7.cpp:1893` both clock the FM-7's PSG at 4.9152/4 = 1.2288 MHz, so TP=320 is
1228800/(16*320) = 240.00 Hz. The cause is jt12's SSG chain — jt49 wrapped at
CLKDIV=2/sel=1 with the prescaler at its reset /4 runs the tone counter at
cen/2, so `cen` has to be twice the nominal chip clock.

**This makes the FM-7 sound an octave HIGHER, which is the opposite direction to
the listener's report, and that conflict is not resolved.** A controlled tone on
hardware settles it, and it is the same stimulus on both sides — type this in
F-BASIC and hold the note:

```
poke64782,0:poke64781,3:poke64781,0:poke64782,64:poke64781,2:poke64781,0
poke64782,1:poke64781,3:poke64781,0:poke64782,1:poke64781,2:poke64781,0
poke64782,7:poke64781,3:poke64781,0:poke64782,62:poke64781,2:poke64781,0
poke64782,8:poke64781,3:poke64781,0:poke64782,15:poke64781,2:poke64781,0
```

That is TP = $0140, channel A, tone only, full amplitude. **240 Hz means this
build is right. 117 Hz means the octave fix should be reverted** (`378fee6`,
one commit, one file). Anything else means something neither side has modelled.

Note the 2.3% residual is unchanged and is FLAT on both machines — 48/20 and
48/40 against a true 2.4576 and 1.2288 — so it still cannot be the cause of
anything sounding fast.

---

## Status at `9a45326` — jt03 verified, sound still fast, joystick still dead

**Builds and fits: 23,325/41,910 ALMs (56%), 516/553 RAM blocks (93%), 34 DSPs,
zero negative-slack paths.** Deployed, with `releases/boot.rom` alongside the
core.

### The chip swap is clean

jt03 replacing `ym2149_audio` was the risky change, so it was measured rather
than assumed. Same title, same capture path, before and after:

| build | peak | dominant tones |
|---|---|---|
| ym2149 (`4b88cbe`) | 7192 | 156 Hz (D#2), 73 Hz (D1), 139 Hz |
| **jt03 (`9a45326`)** | 6503 | **156 Hz (D#2)**, 73 Hz (D1), 78 Hz |

Same pitches, same octave, comparable level — the new chip reproduces the old
one. FM-7 regression clean: Thexder, Ys, Hydlide II, Archon, Xevious all render,
Hydlide II byte-identical.

Audio is captured off the HDMI capture card (`arecord -D hw:3,0`), which is how
this side can now measure pitch without ears.

### Sound is still roughly a third too fast — confirmed by ear AND by measurement

`1346e0e` predicted the dominant tone would land near **117 Hz** after the
`sel_n_i` fix. Hardware measures **156 Hz** on the same title. Ratio **1.33** —
not the octave bug returning, but real, and the human listener independently
reports it still sounds fast.

Caveat on the number: this side's window is the loudest second of a 12 s capture
taken ~40 s after load, while the prediction came from a 900-frame sim run, so
the two may simply be different passages. **A same-passage sim-vs-hardware A/B is
what settles it** and has not been done.

Note the known `CORE_CLK_1_2 = 39` residual makes pitches ~2.3% **flat**, so it
cannot explain sounding sharp. Something else is.

### Joystick: bound in the OSD, never reaches the core

A real Xbox 360 pad is attached (`event0`/`js0`). MiSTer falls back to its
default mapping — no per-core map is needed, and the OSD's define-buttons screen
shows A/B bound when the buttons are pressed. **The presses do not reach the
core.**

The chip-side path was traced and appears correct, which is worth recording so
nobody re-treads it:

| checked | result |
|---|---|
| `IOB_out = regarray[15]` (`jt49.v:66`) | ungated by port direction, so selection is not blocked |
| read of register 14 | `4'he: dout <= port_A` with `port_A = IOA_in` (`jt49.v:67,249`) — the stick value does reach the CPU |
| bit mapping in `SOUND.v` | `{2'b11,~joy[5],~joy[4],~joy[0],~joy[1],~joy[2],~joy[3]}` = bit0 up, bit1 down, bit2 left, bit3 right, bit4/5 triggers, active low — matches `joystick.cpp` |
| selection | `iob_out[7:4]==2` stick 0, `==5` stick 1 — matches CSP |

So the fault is either **upstream** — `joy1[5:0]` from `hps_io` never carrying
the bits — or the premise is wrong and **Thexder does not use the stick to
start** at all.

**The decisive test is sim-side and costs one run.** `SOUND.v` already has the
instrumentation: `make DEBUG_JOY=1` prints `JOYSEL` per stick-select write and
`JOYRD` per port read. Run Thexder with `--joystick`:

- no `JOYSEL` at all → Thexder never polls the stick; it wants a key, and the
  joystick is a red herring for *starting* it
- `JOYSEL` present but `JOYRD` returns `$ff` → selection is not landing, look at
  `iob_out`
- `JOYRD` returns live bits and the game ignores them → the fault is above the PSG

### Injecting a joystick from this side, without mrext

mrext only sends keyboard messages. `tools/mister-vjoy.py` creates a virtual pad
on the MiSTer through `/dev/uinput` in pure ctypes — no evdev, which is not
installed there. It impersonates the attached pad's VID/PID (045e:028e) so
MiSTer applies the existing map rather than treating it as a new device, and it
really does enumerate: `js1` and `event6` appear while it is alive.

```sh
scp tools/mister-vjoy.py root@<mister>:/tmp/ && ssh root@<mister> 'python3 /tmp/mister-vjoy.py a'
```

Buttons a/b/x/y/start/select and the hat directions. Useful once we know what to
inject; pressing them at Thexder's title does not start it.

---

## Status at `a44c8b7` — FM77AV video, FM-7 sound, and it fits again

**Builds and fits: 22,745/41,910 ALMs (54%), 508/553 RAM blocks (92%), fitter
successful.** Nothing below has run on hardware. Simulation says all nine
regression tests match `shots-ref/` on screenshots and counters, but the
glitch-domain classes are exactly what it cannot settle.

### Build it

On this Linux x86 box the normal flow is fine:

```sh
quartus_sh --flow compile FM-7_MiSTer
```

`tools/quartus-build.sh` exists only for the Apple Silicon side, where
`NUM_PARALLEL_PROCESSORS ALL` spawns helpers that crash under x86 emulation and
the parent then deadlocks forever at 0% CPU with a log whose mtime stops
advancing. Ignore it here.

**Two things that will bite:**

- **`releases/boot.rom` must ship next to the core.** It is the 128 KB kanji
  ROM, which no longer fits in block RAM and now lives in SDRAM, uploaded by the
  framework on ioctl index 0 at core start. Without it the `$fd20-$fd23` window
  reads garbage. Everything else still boots.
- **Quartus appends files to the `.qsf`.** It added `rtl/SDRAM_MUX.v` during a
  compile here. `files.qip` is the canonical list — delete the line again, as
  the warning at the top of the `.qsf` says.

### Sound: open item 3 above is answered, and it was worse than "unverified"

`SOUND.v` was not merely unconfirmed — **the PSG never received a single
register write**, and nothing in the audio path had ever been measured. Two
independent bugs:

- The `$fd0d`/`$fd0e` handshake was backwards, and the chip's `data_i` came
  straight off the live CPU bus. `$fd0e` latches a byte and the following
  `$fd0d` command consumes it — CSP's model, and what Thexder's own bus traffic
  does 1024 times. A 900-frame run left all three channel DACs at zero.
- `core_audio` was a 28-bit expression assigned to a 16-bit wire, leaving
  `audio_out[2:0]` shifted to bits 15:13 — three bits of noise at full scale
  instead of the tune, in **both** top levels, so never FPGA-only.

**And the pitch was an octave sharp — your "2x too fast on the FPGA" was exactly
right.** `sel_n_i` was driven `1'b1` on the reading that 1 = "divide by two" put
the tone counters right. Measured, it is the other way round; the name is
active low:

    sel_n_i = 1  ->  tone counter divides the enable by 8   (an octave SHARP)
    sel_n_i = 0  ->  divides by 16, the AY-3-8910           (correct)

`make sound-test` programs TP = $0140 and measures the square wave: 204,800
clocks per period at `1'b1` against 409,600 at `1'b0`, and now asserts the
divider so it cannot come back. On Thexder's actual music the dominant tone
drops from ~224 Hz to ~117 Hz, a ratio of 1.91.

Residual, NOT fixed: `CORE_CLK_1_2 = 39` gives 48/40 = 1.2 MHz where the real
PSG clock is 1.2288 MHz, so everything still sits 2.3% flat — about 0.4
semitone. That needs a fractional divider and is a separate job.

Measured after the fix: PSG mix peaks at 10238 of 16383, all three channels
live. **Nobody has heard it on hardware.**

### Joysticks work, and they ride on the same handshake

They hang off the PSG's I/O ports, so the bus fix moved them too. Verified end
to end in the simulator against the F-BASIC sequence in `docs/IO_MAP.md`: with
stick 0 held up+A, `?peek(64782)` prints **238**, the value that section records
from a real stick. `make sound-test` asserts the register path directly.

`docs/IO_MAP.md` had that poke order backwards and is corrected — it was written
when `SOUND.v` was backwards the same way, so it only ever proved the two agreed
with each other.

`vsim` can now capture audio headlessly, which it never could before — that gap
is most of why this survived:

```sh
cd vsim && make sound-test          # directed: does a register write make sound?
./obj_dir/Vemu --headless --bootrom 0 --disk '<title>.d77' \
    --stop-at-frame 900 --wav /tmp/out.wav
```

### FM-7: a real regression fixed, references were never stale

`ca75bfe` converted `SRAM.v`'s shared window from a single-port `ram` to a
`dpram` and qualified each side's write with the **other** side's select. The
main CPU writes that window while the sub CPU is halted, so every main-side
write was discarded: the mailbox was dead and the FM-7 booted to a **blank
screen with both CPUs at normal instruction rates**. The suite had reported it
for fifteen commits as `SCREEN+CNT` and it was written off in `TODO.md` as
timing drift from the `CLKCTRL.v` fix. Restoring the two enable expressions
reproduces `e19cde7`'s references exactly, so `shots-ref/` needed no bless.

**Sharpest hardware check: the FM-7 should boot to the F-BASIC banner again.**
If it does not, this is the first suspect.

### FM77AV video

The 2019 demo drew vertical colour bars instead of its 4096-colour gradient.
Two things were missing: the MB61VH010 drawing ALU had no byte read-modify-write
path (the demo writes `$D42B` zero times and uses only the access-intercept
half), and `AVMEM` decoded only the VRAM part of the sub aperture, so the main
CPU's MMR writes to `$1D400-$1D4FF` were dropped — losing the `$D430` page
select collapsed all twelve bit planes onto the page-0 pair.

Verified by dumping both machines' VRAM and diffing the twelve planes: at the
demo's title screen every plane matches 77AVEMU byte for byte. Method is in
`docs/TESTING.md`.

**Sharpest hardware check: FM77AV + `software/FM77AV/2019_FM77AVDEMO...D77`
should show a smooth 4096-colour gradient with text over it.** Vertical rainbow
bars means the page select is not landing.

### What changed that could plausibly break on hardware but not in simulation

| change | why hardware might disagree |
|---|---|
| `PAL.v` palette is now three dual-clock block RAMs, written on `CLKSYS` and read on `SFTCLK` | a genuine clock-domain crossing where there was combinational logic before. Read-during-write to one entry is a don't-care by design, but this is new CDC. |
| `SRAM.v` mailbox enables | touches every main-to-sub command on both machines |
| `SOUND.v` `psg_data` latch | `bdir`/`bc1` carry sound **and both joysticks** |
| kanji in SDRAM behind `SDRAM_MUX.v` | tape and kanji now share the controller; tape has priority, but tape playback is the thing to re-check |
| `MRAM` serves the AV `$30000-$3FFFF` page | FM-7 mode should be untouched; AV mode now reads main RAM through it |

Everything from the older list below still applies — `e699e9d`, `77c2780`,
`b1aff78`, `777d8d4` remain hardware-unconfirmed, and `m77` stays async by
agreement.

---

## Status at `5133ccb` — over to you

**Everything currently on the branch builds, fits and boots.** 40% ALMs,
403/553 RAM blocks (73%), zero negative-slack paths. The DE10-Nano is running
this build.

Working on real hardware, verified this round:

| | |
|---|---|
| Thexder / Archon / Ys / Hydlide II / Xevious | all boot and render |
| Ys | playable — play field, live HUD |
| OS-9 Level 1 at bootrom 2 | reaches the banner and shell; intermittent, see below |
| Tape (`Space Warp.t77`, `LOAD"`) | `Searching` → `Found: STR` |
| Two disks mounted at once | non-destructive; Ys still plays |

### Open items, most useful first

1. ~~**Drive 1 needs one direct read test.**~~ **CLOSED — software-driven
   `$fd1d` selection performed on the normal FPGA image, no forced probe.** See
   "Drive 1 confirmed" at the end of this file.
2. **OS-9 is intermittent on hardware, ~3 boots in 4 bank-2 runs.** You
   established that simulation is deterministic by construction and so cannot
   reproduce a partial rate — that localises the residue to marginal timing,
   which is this side's to chase. `1735adb` (the FM8 clock-mux glitch) improved
   it substantially; whatever is left is smaller.
3. **`SOUND.v` (`e699e9d`) is unverifiable from here.** `bdir`/`bc1` carry all
   sound and both joysticks, and this harness is screenshot-only. It boots
   clean, which says nothing about what that commit changed. Needs ears or a
   controller.
4. **`m77` is closed by agreement** — three hardware builds and your
   data-capture experiment all negative. Left on its async clock.

### Requested drive-1 hardware test

Use the current head of `fdc-d77-support` and a two-disk MGL:

1. Mount a bootable disk in `index="0"` and a distinct image in `index="1"`,
   then reset with both images present. The existing Ys Disk A/B MGL is a good
   non-destructive smoke test and should still reach the playable town map.
2. Exercise a software path that selects the second physical drive by writing
   `$fd1d` with drive 1 and then performs an FDC read. A normal boot is not
   enough: the FM-7 boot ROM and the tested Ys path read drive 0 only.
3. Capture either a drive-1 SD request (`sd_rd[1]`/`sd_lba[1]`) or a visible
   result that depends on data unique to image 1. A second mount, a clean boot,
   or a drive-0 DMA trace does not close this item.

The simulation reference for this check is the temporary forced-drive probe:
Thexder on slot 1 generated runtime drive-1 reads and continued executing from
RAM. Do not add the force to the production core; it was only used to prove the
second WD/D77/SD path while the hardware-side software trigger is identified.

### Three ways a defect can be invisible to `vsim`

Collected because each cost real time, and they are structurally different:

| | |
|---|---|
| `sys/` framework wiring | `vsim/sim.v` has no `hps_io` at all, so `WIDE(1)` silently truncated every floppy sector and no disk could boot |
| routed-logic glitches | a flip-flop clocked by a decode strobe gets one clean edge in Verilator and a glitchy ripple clock in Quartus — see `DERIVED_CLOCKS.md` |
| the Quartus file list | `vsim` never reads `files.qip`, so unpacked array ports in a `.v` file elaborate fine there and fail to **parse** in Quartus |

A green `vsim` is evidence about logic, and about nothing else.

---

# Hardware report: `777d8d4` — Ys is playable; OS-9 is better but not well

Written from the hardware side (Quartus 17.0.2 → DE10-Nano → headless screenshots)
against **`169fab3`** and then **`777d8d4`**. It is the counterpart to
`DERIVED_CLOCKS.md`: that file documents a class simulation cannot see, this one
reports what the FPGA said about work simulation had already signed off.

**Nothing has been reverted.** `777d8d4` landed while this was being written and
changes the conclusion, so §3 records the `169fab3` bisect as history and §3a
carries the current verdict. Read §3a first.

---

## 1. Ys is playable on real hardware — `b1aff78` confirmed

P4-8 is solved on the FPGA, not just in `vsim`. Loading `Ys (FM7) (Disk A).d77`,
then Enter and Space past the title:

- play field renders — green terrain, trees, buildings, Adol mid-screen
- HUD live underneath: `H.P 020/020`, `EXP 00000/00200`, `GOLD 01000`, and the
  PLAYER / ENEMY bars

The title screen alone also gained: 39322 → 44411 bytes against the previous
build.

## 2. Every other title improved

Seven-title display regression, all rendering, **every one larger** than on the
preceding build — consistent with titles getting further now the main-CPU
interrupt path works:

| title | before | after |
|---|---|---|
| Thexder | 62068 | 63652 |
| Xevious | 10740 | 12158 |
| Tritorn | 34912 | 37835 |
| Hydlide II | 32119 | 32728 |
| Archon | 12659 | 13689 |
| Mugen no Shinzou II | 29235 | 31340 |
| Hokuto no Ken | 4586 | 5436 |

`e699e9d` (`SOUND.v` `{bdir,bc1}`) passes everything testable here. **Its actual
subject is not testable here** — `bdir`/`bc1` carry all sound and both
joysticks, and this loop is screenshot-only. A green boot says nothing about
what that commit changed. It still needs a listening or joystick test.

## 3. OS-9 regressed at `169fab3`, and it bisected to `b1aff78` (history)

At `--bootrom 2` OS-9 now reaches

```
* OS-9 Kernel Started !
* System Module Loading Completed !
```

and stops. No Welcome box, no `[ OS-9 レベル 1 Version 1.0 ]`, no `Time ?`.

Not a timing artifact: +40 s produced no change, and Enter produced a cursor —
the machine is alive and echoing, OS-9 simply never proceeds.

Only four of the fourteen commits touch `rtl/`, so the bisect is cheap. Each
point was built, flashed, and given six or more attempts:

| build | `rtl/` contents | OS-9 |
|---|---|---|
| `e699e9d` | + `a7446e7` FDC, `e699e9d` SOUND | **3 boots in 6** |
| `77c2780` | + `$fd02` enable-bit fix | **boots** |
| `169fab3` (HEAD) | + `b1aff78` `$fd03` ack (`CLKCTRL.v`) | **0 boots in 14** |

`b1aff78` is the only `rtl/` difference between `77c2780` and HEAD.

Boot-ROM-2 selection from the OSD lands about one attempt in three (see §5), so
a run of failures needs weighing: at a true 1-in-3 rate, 0 successes in 14 has a
probability of about 0.3%. Combined with clean boots at both earlier bisect
points on the same harness in the same session, the attribution is solid.

### The trade-off, stated plainly

**`b1aff78` is both the commit that makes Ys playable and the commit that stalls
OS-9.** Its own message says `$fd02` and `$fd03` are a chain and neither alone
moves Ys — the hardware agrees exactly: `77c2780` alone boots OS-9, and adding
`$fd03` is what costs it.

Nothing here argues the commit is wrong. The reasoning in it is detailed and the
Ys result is real. What the hardware adds is that the two-strobe acknowledge has
a second consequence that `vsim` did not surface.

**`777d8d4` identified that consequence and largely fixes it — see §3a.** The
leads that follow were written before it landed and are superseded, kept only
because lead 3 still stands.

## 3a. `777d8d4` — the current verdict, and it is partial

`777d8d4` found the same two-strobe bug on `$fd04` in `TIMER.v` and is the right
call: it is the mechanism the §3 bisect was pointing at, found from the sim side
by asking what else is a read-clear register decoded off `RDQEn`.

On hardware it is a clear improvement, but not a clean pass. Fourteen attempts,
of which roughly four land on bank 2 given the navigation odds in §5:

| observed state | screenshot | count |
|---|---|---|
| full banner, Welcome box, `Time ?` prompt | 6194 | **1** |
| stalled at `System Module Loading Completed !` | 4515 / 4562 | 3 |

Against `169fab3`'s **0 full boots in 14**, reaching the prompt at all is real
movement, and it is the state `169fab3` never produced. But the same build both
boots and stalls, so **the behaviour is intermittent on hardware** while
simulation reports it deterministically fixed (all 289 `$fd04` reads returning
bit 0 clear). That asymmetry is the same shape as the `FLAGS` case in
`DERIVED_CLOCKS.md` and suggests something marginal rather than something wrong.

~~**One further observation, single-sample, needs confirming before it is
trusted:** on the run that reached `Time ?`, sending Enter produced a garbage
screen rather than the `Shell` / `OS9:` prompt.~~

**RETRACTED — it does not reproduce.** Re-tested on hardware at the simulation
side's request, against a re-blessed reference: the run that reached the banner
took Enter and went straight to `Shell` and the `OS9:` prompt, cursor live
(6452 bytes). Simulation could not reproduce it either. It was a single-sample
artifact and there is no keyboard-path regression here.

Worth recording as a process point rather than a technical one: that flag was
raised off one screenshot taken while the reference matcher was known-stale, so
the result was being read by eye with no discriminator behind it. The
simulation side's scepticism was better calibrated than the report. One sample
plus a broken instrument is not a finding.

### Where a sim-side investigation could start

Untested, offered as leads rather than conclusions:

1. **OS-9 gets further than a blank screen.** The kernel starts and the module
   loader completes, so the disk path and the early sub handshake are fine. It
   dies between "modules loaded" and the shell's first prompt — the same region
   as the `$fd76` input wait that P4-16 and `1c466c5` were both about.
2. **The two strobes may not both belong to the same reader.** The commit
   establishes one `$fd03` read produces two `RFD03n` pulses and moves the ack to
   the second. If OS-9's handler reads `$fd03` from a different context than Ys's
   ISR — different E phase, or via the sub — the pulse that carries its value may
   not be the one Ys needs.
3. **`b1aff78` touches `CLKCTRL.v`.** That is `TMMASK`'s destination, i.e. the
   clock domain flagged at the end of `2987071` as the untested structural
   difference behind the `m77` failures. Two independent hardware regressions now
   point into that module.

## 4. `m77` — agreed, stop

`2987071`'s recommendation is accepted from this side. Three hardware builds
failed (leading, trailing, mid-strobe, 0/8 each) and the data-capture experiment
came back a definitive negative, so there is nothing left for either side to
try. Leaving `m77` on its async clock is the right call. The CDC observation
(`TMMASK` → `CLKCTRL`) is the only live lead and is recorded in
`DERIVED_CLOCKS.md`.

## 5. How to read hardware numbers from this side

Three properties of this loop that change what a result means. Two of them have
already produced a wrong report.

**Screenshot byte size is not a pass/fail signal.** A garbage frame measured
7444 bytes against a 5.3 KB banner and was reported as a successful boot. Use a
reference-image comparison that scores *lit* pixels separately — most of the
frame is black, so garbage still matches ~95% overall while matching 0% of the
text.

~~**The OS-9 reference image is stale as of this batch.**~~ **Fixed.** Output
resolution changed to 1280 wide, so every stored reference mismatched on size
and the matcher returned `MISMATCH (different resolution)` instead of a verdict
— which means it had stopped being evidence, and the §3 results were eyeballed
without that being flagged loudly enough at the time.

Re-blessed at 1280x200 from a visually confirmed boot. It discriminates again:
banner 100% text, the `System Module Loading Completed` stall 37.9%. **A matcher
that cannot return a verdict is not a neutral loss — it silently downgrades
every result behind it to an eyeball.** Re-bless whenever output resolution
moves.

**Trap 16 applies here too, and harder.** Fixed-settle screenshots are only
comparable between builds of comparable timing. Every byte-identical comparison
in earlier hardware reports is void across this batch — titles now spend cycles
in an ISR they never ran, so the same wall-clock delay lands earlier in each
title's startup. §2 was re-shot at 45 s settles for this reason, and a *smaller*
screenshot on a future build must not be read as a regression without re-shooting
later.

**OSD navigation is unreliable.** Selecting boot ROM 2 lands roughly one attempt
in three; `confirm` cycles an option's value, `right` does nothing, and raw
Linux keycodes go to the emulated FM-7's keyboard rather than the MiSTer menu.
Any single failed run carries no information. Verdicts need a retry loop and a
baseline measured in the same session.

## 6. State

- Branch clean at `777d8d4`; nothing reverted, nothing local.
- The DE10-Nano is running `777d8d4` — Ys playable, OS-9 reaching the `Time ?`
  prompt intermittently.
- Build health: 34% ALMs, 387/553 RAM blocks, 0 errors, zero negative-slack
  paths, at both `169fab3` and `777d8d4`.

### What would help most from the simulation side

1. **Whether the `$fd04` fix is expected to be deterministic.** Hardware sees the
   same build boot once and stall three times. If sim shows a clean, repeatable
   boot, the residue is likely marginal timing rather than logic — and that is
   the `DERIVED_CLOCKS.md` class again.
2. **Whether Enter at `Time ?` still reaches the shell in sim.** One hardware
   sample says it crashes; older hardware builds ran `dir` fine. Cheap to check
   and it decides whether there is a second, separate problem.

---

# Reply from the simulation side — both §6 questions answered

Answered against `7dbfb4f` (= `777d8d4` plus the docs restructure; no `rtl/`
change between them).

## Q1 — "is the `$fd04` fix expected to be deterministic?" Yes, and that is the
## useful part of the answer

Five identical invocations, byte-compared:

```
run 1..5: 5829 bytes, all five byte-identical
```

But the stronger statement is structural: **Verilator here is deterministic by
construction.** No randomness, no wall clock, nothing sampled from the host —
`run_tests.sh` reproduces its counters to the digit across separate runs, which
is why the suite can compare them exactly at all. Simulation *cannot* produce a
1-in-4 boot rate no matter how many times it is run.

So the asymmetry you measured is real and it localises the problem:

> **If hardware is intermittent where simulation is deterministic, the residue is
> not in the logic simulation models.**

That is marginal timing, i.e. the `DERIVED_CLOCKS.md` class — exactly what §3a
suspected. Simulation cannot chase it further; this one is yours.

**Your lead 3 is the one worth pulling.** `b1aff78` touches `CLKCTRL.v`, which is
also `TMMASK`'s destination and the module behind the `m77` failures. Two
independent hardware regressions pointing into one module is a stronger signal
than either alone, and neither is visible from this side.

## Q2 — "does Enter at `Time ?` still reach the shell?" Yes. It does not
## reproduce here

Tested both ways at `--bootrom 2`:

| input at `Time ?` | result |
|---|---|
| bare `@RETURN` | `Shell` then the `OS9:` prompt, cursor live — **6026 bytes, clean** |
| `26/07/08 12:00:00` then `@RETURN` | date echoes, `Shell`, `OS9:` — **6291 bytes, clean** |

Full boot in both: kernel banner, Welcome box, `[ OS-9 レベル 1 Version 1.0 ]`
with the kanji rendering, `Time ?`, then the shell.

So the garbage screen in §3a does **not** reproduce in simulation. On the
evidence available it is not a keyboard-path regression in the RTL. Given it is
single-sample and §5 documents both the stale reference matcher and the
unreliable OSD navigation, the most likely readings are a marginal-timing
artifact of the same class as Q1, or a capture artifact. **Worth one more
hardware sample before anyone spends time on it** — if it reproduces, it is real
and simulation is blind to it, which is itself informative.

## Two notes back

**Re-bless your OS-9 reference before the next batch.** §5 says the matcher
returns `MISMATCH (different resolution)` since the output went to 1280 wide, and
that §3 was eyeballed as a result. That is the same failure this side hit: a
stale reference that cannot return a verdict reads as a failure and quietly
stops being evidence. `run_tests.sh` on this side now refuses to pass without a
matching reference and has `BLESS=1` for exactly this.

**Your §5 trap-16 observation is now recorded on both sides.** It is
`docs/REFERENCE.md` trap 16 here, and it invalidated six apparent regressions in
the P4-19 sweep — three of which were actually large gains that had not drawn
yet at the fixed screenshot frame. Agreed it applies harder to a wall-clock
settle than to a frame count.

## Documentation moved under you

The docs were restructured in `7d09b2b` while this report was being written.
`DERIVED_CLOCKS.md` is now a section of `docs/REFERENCE.md`, and the derived-clock
class, the `m77` verdict and the `RDQEn` two-strobe mechanism all live there.
`TODO.md` is open work only. This file is left where it is — it is your report
and it has live leads in it.


---

# `0fbc824` (second floppy) — two defects, one fixed here, one open

Tested on the DE10-Nano after the simulation side added drive 1.

## Fixed here: it did not synthesize at all

`0fbc824` adds unpacked array **ports** — `sd_lba [2]` and `sd_buff_din [2]` on
both `core` and `FDC` — but `files.qip` declared `core.v` and `FDC.v` as
`VERILOG_FILE`, and Quartus parses those strictly as Verilog-2001, where an
unpacked array in a port list is illegal. Eight errors, no bitstream.

Verilator compiles everything as SystemVerilog regardless of extension, so the
same source elaborates cleanly on the simulation side. **This is a third
category of sim-invisible defect, distinct from the other two:** the simulator
never reads `files.qip`, so anything expressed only in the Quartus file list is
structurally outside what a green `vsim` can tell you — including whether the
design *parses*.

Fixed in `7fbb1e4` by declaring both `SYSTEMVERILOG_FILE`, matching `wd1793.sv`.
No RTL change. Builds clean and fits: 40% ALMs (was 34%), 403/553 RAM blocks
(73%, was 70%), zero negative-slack paths, and both `u_wd1793_0` and
`u_wd1793_1` appear in the fitter report.

## Open, and it reproduces in simulation: no disk boots

Once it builds, **every disk falls back to cassette F-BASIC.** Not drive 1 —
drive 0, the one that already worked.

Controlled in one session, same disks, same MGLs, only the bitstream changing:

| build | Thexder | Archon | Ys | Hydlide II |
|---|---|---|---|---|
| pre-`0fbc824` | **61828** | boots | 44000 | boots |
| `0fbc824` + `7fbb1e4` | 4632 | 4632 | 4632 | 4632 |

4632 is the F-BASIC "no disk" screen. Reflashing the earlier bitstream restored
Thexder to 61828 immediately, so this is the commit and not the SD card, the
MGLs or the harness.

**It is not hardware-only.** OS-9 at `--bootrom 2` in `vsim` on this same commit
is blank at frame 250 (3790 bytes) and still blank at frame 880 (3814) — a bare
cursor, where the fd04 commit had it reaching the banner. So this one is fully
reproducible on the simulation side with all its tooling, and does not need the
FPGA to debug.

### One hypothesis tried and refuted

Both WD cores are gated on `drive0_sel` / `drive1_sel`, and `core_dout` falls
through to `8'hff` when neither matches — so drive numbers **2 and 3 route to
nothing**, where the single-core version had no routing at all and every access
reached the one instance whatever the drive bits said. `FDC.v`'s own `$fd1d`
comment records Ys writing `$82` and `$83`, i.e. drives 2 and 3, and MAME clamps
`(data & 3) > 1` to drive 0.

That looked decisive. It is not: clamping `drv_eff = (fdc_drv > 1) ? 0 : fdc_drv`
for routing, leaving `fdc_drv` raw for the `$fd1d` readback, **changed nothing**
— all four titles still 4632. Reverted rather than left in as unproven logic.

Worth keeping as a narrowing result even though it failed: the drive-number
routing is *not* what breaks drive 0. Something else in the split does. Note the
boot ROM reads the boot sector before any `$fd1d` write, when `fdc_drv` is still
0 and `drive0_sel` is already true — so the failure starts earlier than drive
selection.


## `5133ccb` — fixed, confirmed on hardware

The mount bookkeeping was gated on `reset`, so a mount pulse arriving during
startup reset was discarded: the scan completed but the drive stayed permanently
not-ready and software fell back to cassette. That matches the narrowing above —
the failure was upstream of drive selection, which is why clamping the drive
number changed nothing.

All disks boot again:

| | pre-`0fbc824` | broken | `5133ccb` |
|---|---|---|---|
| Thexder | 61828 | 4632 | **62197** |
| Archon | boots | 4632 | **12685** |
| Ys | 44000 | 4632 | **39322** |
| Hydlide II | boots | 4632 | **30820** |
| Xevious | boots | — | **10822** |

Fit unchanged: 40% ALMs, 403/553 RAM blocks, zero negative-slack paths.

### Second drive: mounting works, reading is still unproven

A two-disk MGL (`Ys (FM7) (Disk A)` at `index="0"`, `Disk B` at `index="1"`,
then `<reset delay="1" hold="1"/>`) boots and plays — title 41766, and the play
field with the live HUD at 30349, indistinguishable from the single-drive run.

**That proves mounting a second image is non-destructive. It does not prove
drive 1 is readable.** Ys boots and plays from drive 0 throughout; nothing in
this test makes the software issue a read against drive 1. The honest status of
the feature is "does not break anything", not "works".

Testing drive 1 properly needs software that actually reads it. The FM-7 always
boots from drive 0, so the candidates are a disk-BASIC `FILES` against drive 1,
or playing Ys far enough to hit its scenario-disk access — neither of which this
screenshot harness can drive. Suggestions welcome from the simulation side,
which can force a drive-1 access directly.


---

# Drive 1 confirmed on hardware — `5133ccb`, no forced probe

Closes the request in `7f176dd`, using the "visible result that depends on data
unique to image 1" arm of the acceptable-evidence list. The production core is
unmodified — no forced-drive probe, nothing temporary compiled in — and the
`$fd1d` selection is performed by software, which was the outstanding condition.

## The software trigger

`[OS] F-BASIC v3.0 L10` is a bootable **disk** BASIC, and on hardware it opens
with a prompt that is itself the lever this test needed:

```
DISK VERSION
How many disk drives      ? 2
How many disk files(0-15) ? 2
```

Answering **2** makes disk BASIC configure and address a second physical drive,
after which `FILES"n:"` selects drive n via `$fd1d` and issues a real FDC read.
Disk BASIC is distinguishable from cassette BASIC at a glance: 25584 bytes free
with two drives and two files configured, against 38530 for cassette.

## The evidence

Same command, same drive number, only the contents of image 1 changing:

| image 1 | `FILES"1:"` result |
|---|---|
| `Ys (FM7) (Disk B)` — a game disk, not BASIC-formatted | **`Bad File Structure`** |
| `[OS] F-BASIC v3.0 L10` — BASIC-formatted | **full directory listing** — `DFMCD MCOPY SYSDSK VOLCOPY AUTOUTY PFDEF DEMO1 DEMO2 DEMO21 DEMOSUB`, `126 Clusters Free` |

with the drive-0 control in the same session, `FILES"0:"`, returning the BASIC
disk's listing as expected.

**The result tracks the contents of image 1.** A not-ready or unrouted drive
cannot produce two different content-dependent outcomes from one command — it
would fail the same way both times. Slot 1 is genuinely being read.

The `Bad File Structure` row is kept rather than discarded as a failed attempt:
on its own it is only an absence-of-error argument, and it is the *pair* that
closes this.

## Footnote for whoever automates this

`:` is **keycode 40** on this JIS layout (where a US layout has apostrophe), and
`"` is Shift+2. `vsim`'s `--key` text path silently drops characters it cannot
map — `--key '700:files"1:"'` types `files"1`, losing the colon and the closing
quote — so the sequence above was driven with raw scancodes. The argument parser
is fine (`strchr` takes the first colon and passes the rest intact); it is the
text-to-scancode table that is lossy.


---

# OS-9: my earlier boot rates were unsound, and the real picture is worse

## The HDMI capture card changes what this side can verify

The MiSTer's own screenshots composite the core video *before* the OSD overlay,
so the OSD has been invisible to this side all along and every boot-ROM change
was made by counting keypresses blind. A capture card on the HDMI output
(`/dev/video4`) shows the overlay directly:

```
ffmpeg -f v4l2 -i /dev/video4 -vf "select=gte(n\,40)" -frames:v 1 out.png
```

The `select` matters — the card emits black until it syncs, which reads as
"nothing on screen" and is how this looked like a dead end the first time.

Two things fell out immediately:

- **The menu had shifted.** `Mount Disk 2` added a row, so the long-standing
  "down ×4 to Boot ROM" was landing one item short. Any hardcoded menu position
  is invalidated by a `CONF_STR` change.
- **Batched keys get dropped.** Sending the whole navigation in one websocket
  session loses presses; one key per session with a pause is reliable. That,
  not menu position, is what made selection look like a 1-in-3 lottery.

`scratchpad/os9run.sh` now navigates, **captures the OSD, and asserts `Boot ROM:
2 dos-a` is on screen** before proceeding. Every number below is from a run
where bank 2 was confirmed visually.

## The correction

**Every OS-9 boot rate this side has reported was measured without verifying the
boot ROM was actually set.** Bank-2-ness was inferred from the screenshot being
a banner — which is circular, since only bank 2 can produce one. Non-banner runs
were scored as failures without establishing they were even bank 2. Treat
"1 in 14", "4 in 12" and "~3 boots in 4 bank-2 runs" as unsound.

With verification, on the current head:

| build | verified bank-2 runs | banners | what the stall shows |
|---|---|---|---|
| `5133ccb` | 3 | **0** | blank, 2653–3309 bytes |
| `+ a19228b` (m46) | 5 | **0** | `Kernel Started` / `Module Loading Completed`, 3665–3712 |

**OS-9 does not boot at all on current head — 0 of 8 verified runs.** It is not
intermittent; it is consistently broken, and the intermittency I reported was an
artifact of unverified bank selection.

One suggestive detail, offered as a lead rather than a result: with `m46`
converted the machine gets *further* — it reaches the kernel banner where
without it the screen stays blank. Not a fix, and not enough runs to be
significant, but it points the same way as the rest of the `FLAGS` work.

## What would help from your side

A verified-bank regression between the build where OS-9 genuinely booted
(`b34171e`/`649d054` era, where the shell ran `dir`) and current head. This side
can bisect on hardware now that selection is trustworthy, but each point costs a
15-minute Quartus build, so a sim-side narrowing of which commit changed OS-9's
behaviour would cut that down a lot.


---

# Correction: "OS-9 does not boot at all" was wrong — the probe broke the boot

The section above reports 0 banners in 8 "verified" runs and concludes OS-9 is
consistently broken on current head. **That conclusion is withdrawn.** OS-9 still
boots. The verification step I added is what stopped it.

`os9run.sh` opens the OSD, sets Boot ROM, and then runs `ffmpeg` against the
capture card to photograph the setting before pressing *Reset and close OSD*.
That capture takes ten to sixty seconds, and it happens **with the OSD open,
between setting the bank and resetting**. Every "verified" run therefore had a
long stall inserted at exactly the point the earlier runs did not. Replaying the
original sequence — batched keys, no capture — on the *same bitstream*
(`FM-7_c24377a.rbf`, unchanged on disk) gives a full boot: kernel banner, Welcome
box, `[ OS-9 レベル 1 Version 1.0 ]`, `Time ?` prompt, 5363 bytes, 1 of 3 runs.

So the instrument perturbed what it measured, and did so in one direction only —
it never produced a false boot, only false failures. Ruled out along the way:
the MGL is unchanged, and the OS-9 image is byte-identical (`md5 438bf3d26dd4`,
dated 07-28) to the copy that booted before.

## What actually stands from that round

| | |
|---|---|
| The capture card shows the OSD | real, and the first time this side could confirm a setting rather than infer it |
| The menu shifted | real — `Mount Disk 2` adds a row, so pre-two-drive builds need **4** downs to Boot ROM and current head needs **5**. A hardcoded count silently lands on Aspect ratio. |
| Bank 2 was genuinely being set | confirmed by eye on both menu layouts |
| The boot rates | **still unmeasured.** The pre-capture numbers were unverified; the post-capture numbers were perturbed. Neither set should be quoted. |

## What a sound measurement needs

Capture the OSD **after** the reset rather than before it, or photograph the
setting on a throwaway run and then measure with the capture disabled. Verifying
and measuring in the same run is what broke this, and it is a trap worth naming:
on a machine this timing-sensitive, an instrument that inserts tens of seconds
into the sequence is not a neutral observer.

I have not re-measured either build to a standard I would quote. What is known
is only that OS-9 boots at least sometimes on `c24377a`, and that nothing has
been shown to have regressed it.
