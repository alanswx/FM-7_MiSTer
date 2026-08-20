# TODO

Open work only. Fixed items leave this file — the conclusion goes in a code
comment, the journey stays in the commit message. See `CLAUDE.md`.

Reference material: `docs/REFERENCE.md` (read first), `docs/IO_MAP.md`,
`docs/TESTING.md`, `docs/FM77AV.md`.

---

## Start here

**Where it stands.** The **eleven-row** gate is green — `./run_tests.sh` in
`vsim/` compares screenshots *and* counters against `shots-ref/`. FM-7 boots,
Thexder runs, OS-9 reaches its shell. On the FM77AV side **Deep Forest now
matches 77AVEMU on 100.0% of pixels and the 2019 demo on 99.9%**, measured
rather than eyeballed, after correcting a display phase that had the whole
picture sitting three pixels right of where it belonged and finding that the
analog palette had never accepted a write in its life. Ys boots and draws, and
four titles that rendered nothing now render game art (Deep Forest, both Luxsor
disks, Psy-O-Blade).

**It fits and closes timing.** 23,293 / 41,910 ALMs (56%), 516 / 553 M10K
(93%), positive slack in all five corners, `output_files/FM-7_MiSTer.rbf` built
with `tools/quartus-build.sh all`. **37 M10K blocks is the whole remaining
budget** — price any new feature against that, from the map report's RAM
summary and never in bits (see the FPGA fit section).

**The sound is one chip now.** `jt03` (jotego/jt12) serves both the FM-7's PSG
and the FM77AV's YM2203, so `$FD15`/`$FD16` are decoded and the joysticks sit on
the chip's real I/O ports. **The combined work ships as GPLv3** — see
`Readme.md`. That is a one-way door and it is already through.

**Open, in priority order:**

1. **Two hardware tests are waiting, and only hardware can settle them.**
   `HARDWARE-HANDOFF.md` has both procedures verbatim.
   * *Pitch.* The PSG was an octave flat; measured, not inferred, and fixed. Four
     typable F-BASIC lines program one known tone: **240 Hz means this build is
     right, 117 Hz means revert `378fee6`.**
   * *Joystick.* Dead on hardware, working in simulation — the signature of the
     glitch-domain class, so `SOUND.v`'s strobes were filtered on that reading.
     **Test an FM77AV title**, not an FM-7 one: only the AV routes the gameport
     through `$FD15`/`$FD16`. Twenty AV titles provably poll it; Dragon Buster is
     the pick because it already rendered before any of this work.
2. **The gate lost an AV row's worth of coverage.** `av-kohakuiro`'s reference
   was a picture of the dead palette; the corrected render is a black screen
   that matches 77AVEMU exactly and tests almost nothing. Replace it with a
   title that genuinely renders — see below.
3. **Six AV titles still render nothing**, in four distinct shapes, all recorded
   below rather than left to be re-derived.
4. **The FM half of the YM2203 has never been compared to anything**, and its
   timers/`$FD17` IRQ path is only as good as one title's use of it.

**Ask the reference before theorising.** `refs/local/` holds a built 77AVEMU and
its ROMs, gitignored but persistent, so no rebuild is needed:

```sh
refs/local/fm77av_headless refs/local/fm77av-roms game.d77 60000000 out.png --fm7 \
    --key 700:MID_SPACE:40  --joystick 1200:right+a:600  --shot-every 1500
```

It takes the **same input options as `vsim`**, and a frame means the same thing
on both (1/60 s of machine time), so a sequence is portable between them. It is
also about fifty times faster. `FM77AV_MEM_DUMP` dumps its 256 KB physical
memory and `FM77AV_VRAM_DUMP` its VRAM, which is how most of this session's bugs
were pinned down — identical code with different data is a lost store, not bad
logic.

`vsim/sweep/ref-sweep.sh` renders a whole sweep on the reference and
`compare-ref.py` joins the two into one verdict per title. That is what showed
**27 of the old "blanks" are blank on the reference too**, i.e. were never our
bug. Do not quote a blank count that has not been through it.

## Awaiting hardware

These are on `alanswx/fdc-d77-support` and **cannot be settled in simulation** —
they are the glitch-domain and listening classes. `HARDWARE-HANDOFF.md` carries
the FPGA side's own log and the exact procedures.

| commit | what | why only hardware |
|---|---|---|
| `378fee6` | PSG was an octave flat; chip clock now machine-dependent | **the pitch test is the whole point.** 240 Hz = right, 117 Hz = revert this one commit |
| `71c00e6` | `SOUND.v`'s four strobes filtered to 3 stages | Verilator gives one clean edge per access either way, so sim is byte-identical before and after. The joystick test is the only evidence there is |
| `648efbd` | YM2203 interrupt delivered, `EXTIRQ` driven | changes interrupt delivery on every AV title |
| `6356000` | every AV write no longer clobbers the FM-7 page | changes AV memory behaviour wholesale; an FPGA build older than this will not match anything reported here |
| `bad101e` | sub I/O aperture halt gate un-inverted | as above |
| `1706f9c` | the drawing ALU now triggers on a main-CPU VRAM **read** | fires the ALU on a bus cycle that previously did nothing; the read strobe is `~RDQEn`, one of the timing-sensitive decodes |
| `2fdaa08` | `$fd93` bit 0 reports the boot-RAM latch | changes what boot RAM does on every machine |
| `aa6e701` | VRAM aperture gated on the sub CPU being halted | closes a path that was open; blocks nothing measurable in sim, so only hardware can show a title that relied on it |
| `b8ff6ac` | `$fd13`'s sub reset sets BUSY, and so does power-on | **changes power-on behaviour for every machine, FM-7 included.** Thexder's counters moved in sim; anything subtler will only show here |

Earlier commits (`e699e9d`, `77c2780`, `b1aff78`, `777d8d4`) covering the
`$fd02`/`$fd03`/`$fd04` interrupt paths were confirmed working on hardware —
Ys reaches its town map, 1942 reaches its title menu, both dead before.

`m77` in `KEYBOARD.v` remains on an async decode strobe. Three hardware
conversion attempts all regressed OS-9 (0/8 each) and a sim experiment showed
all four candidate designs capture identical values at identical times — see
`docs/REFERENCE.md`. **Leave it async unless there is new evidence.**

Hardware-side update (2026-08-08): `1735adb` fixes an intermittent power-on
clock-mux glitch in `CLKCTRL.v` by giving `switch` a defined startup value and
sampling `SW2` on `CLKSYS`. Integrated locally.

(Superseded claim: *"the reference counters moved by the expected startup timing
shift, so the references were re-blessed"* — none of that held. The counter move
was `ca75bfe` breaking the main-to-sub shared-RAM mailbox; with that fixed the
suite reproduces `e19cde7`'s references exactly. `docs/REFERENCE.md` trap 18.)

---

## Next: CHAN.POP and the remaining blank-screen triage

The read-acknowledge audit is complete for the currently identified paths:
`$fd01`, `$fd03`, `$fd04`, `$d401`, and `$d402` now acknowledge at the E-phase
close; `$d40a` is a single overlap-qualified pulse. `$d404` is split Q/E, but
its effect only sets the attention latch, so both pulse closes are harmless.

Daisenryaku's first divergence is now captured and fixed. The FDC was matching
only the physical head track and requested sector; it ignored the D77 ID
cylinder versus the WD1793 track register. Daisenryaku deliberately leaves the
track register at 0 while the head is at track 4, so 77AVEMU rejects that read
and falls back to track 0 / sector 11. The RTL incorrectly accepted track 4 /
sector 11 and entered the page-zero `$009f FCB $05` path. `wd1793.sv` now checks
the ID cylinder unconditionally.

(Superseded: that check used to be described here as "matching 77AVEMU". It does
not. 77AVEMU looks a sector up by `compensateTrackNumber(drv.trackPos)` -- the
physical head position -- and never compares the ID cylinder against the track
register (`fm77avfdc.cpp:195,206`). The references genuinely disagree; a real
WD1793 does compare C to the track register, so this core follows the datasheet
and 77AVEMU is the lenient one. The check is load-bearing regardless: removing
it takes Daisenryaku from 67.3% coverage to 0.1%, measured.) The core's FDC command stream
then follows the reference through the later track loads and reaches the
Daisenryaku title screen at frame 621. The supplied sibling `refs/TOWNSEMU` now
satisfies 77AVEMU's build contract. Return and Space reach the keyboard latch,
and the DOS boot-ROM selections do not mount this FM-7 disk.

(Superseded: this section used to end "the first BIOS divergence is still
`$fd05`: 77AVEMU reads `$fe` (BUSY asserted after reset), while this core reads
`$7e`; forcing BUSY high changes timing but is not needed for the title fix."
It was needed -- see the FM77AV demo disk. `FLAGS.v` now sets BUSY on reset and
the divergence is gone.)

Resolved in simulation: the shared boot loader seeks with `$fd18=$1a`, writes
the next sector number while the seek is busy, then starts a `$fd18=$80` read.
The controller was dropping that sector-register write, so it read sector 1
instead of sector 13 and eventually executed into the `$fdxx` window. Sector
register writes are now retained during RESTORE/SEEK/STEP busy states. All
three Wizardry images reach RAM-resident code without runaway; the normal
eight-case regression remains reference-clean.

---

## Per-title work

### Re-triage the remaining blanks

The old "17 genuine blanks" list is stale — P4-19 moved 25 titles and
Penguin-kun Wars fell out of it. The current 350-image sweep has 221 FM-7
rows: 82 rich renders, 53 partial renders, 64 blank screens, 6 low-rate
crash/idle candidates, and 16 F-BASIC fallbacks. `bootsector.py` identifies
63 halt-stub disks; 39 of those are blank by design. Rebuild the actionable
list from `vsim/sweep/results.tsv` using the exclusion rules in
`docs/TESTING.md` before chasing anything. The first primary-disk checks are
Soukoban 2 and Hokuto no Ken (Disk 1); most of the low-rate and fallback rows
are secondary disks, known-bad dumps, or programs requiring a `RUN` command.
Soukoban 2 has now been promoted out of this queue: the checked-in D77 reaches
its title/menu screen at frame 1500 and waits for keyboard input.
Hokuto no Ken (Disk 1) likewise reaches its title/menu screen at frame 1500
(`HIT 1-3 KEY`); its earlier partial-render classification was also loader-time.
Wizard and the Princess (Disk 0) reaches a rendered Japanese prompt at frame
1500. Disk 1 alone settles in a data-disk loop after its track-52 load, so it is
not a standalone boot failure.

CHAN.POP now has two concrete simulator fixes: `t77_decode.v` was starting two
bytes early and decoding each T77 pair as a bit-7 level plus a 15-bit duration;
it also waited for SDRAM after every segment, stretching each level. 77AVEMU
uses the first byte as a `< $40` level and the second byte as the 8-bit duration,
with `7f ff` as low silence. The decoder now prefetches the next segment and
matches the first 24 entries byte-for-byte. The full 2.77 MB image, run with
the same `RUN""` autostart that 77AVEMU uses, reaches `Loading GAME IPL` at
frame 3000. Its tape address is `$03f50a` (9.4%); 77AVEMU reports `GAME IPL`
at raw pointer 202540, so the core has crossed the same block and is actively
transferring it. Motor cycling and the extra `$fd02` control write also match
the reference sequence. At frame 4500 the loader has completed that transfer
and is searching for the game payload. At frame 6000 it reports `Device I/O
Error` and the main CPU is in the `$0124` zero loop, with the tape address at
`$082802` (19.3%). 77AVEMU's full-image file scan also reports a malformed
block (`Device I/O Error` at raw `$214b42`), so the error text alone is not
evidence of an RTL defect. Runtime alignment of that payload/error remains
open; do not change the decoder without that reference trace.

Remaining validation:

- **CHAN.POP** — align the post-`GAME IPL` `Device I/O Error` against a
  77AVEMU runtime trace before changing RTL; the decoder and full tape-load
  comparison match through the payload transfer.

### Ys

**FM-7 version:** playable, but only characterised as far as the town map.
Nobody has played further to see what breaks next.

**FM77AV version:** reaches its title screen at frame 900 and keeps drawing.
Not characterised past that, and nobody has compared the finished title against
`refs/local/av-divergence/Ys__FM77AV___Disk_A__.png` pixel for pixel.

---

## Media support

- **Second drive.** Implemented in the core and simulator: OSD slots S0/S1
  feed independent D77 scanners, and `$fd1d` selects the active drive. The
  hardware build still needs a Quartus compile and physical two-disk check.
- **2DD media** and **multi-disk `.d88`**.

These three together gate a large fraction of the collection — probably the
highest title-count-per-effort item after the register audit.

---

## Smaller open items

- **PSG pitch is now measured, and 2.3% flat.** `make sound-test` prints the
  tone in Hz: 234.65 against the AY-3-8910's 240.00 at the FM-7's documented
  1.2288 MHz. The octave error is fixed; what is left is the integer divider,
  48/20 and 48/40 against a true 2.4576 and 1.2288, i.e. about 0.4 semitone on
  both machines. Fixing it needs a fractional divider.
- **The FM77AV's FM clock is still unverified.** jt03's `cen` is 1.2288 MHz on
  the AV, which puts the FM half at cen/3 after the initiator's prescaler --
  a ~34 kHz sample rate, plausible but unchecked. Nothing has diffed a rendered
  tune against 77AVEMU or CSP, and the YM2203's timers and its `$FD17` bit-3
  IRQ are wired to nothing (`jt03`'s `irq_n` is unconnected in `core.v`).
- **The joystick is dead on hardware and works in simulation**, which is the
  signature of the glitch-domain class, not of a logic bug. `SOUND.v`'s strobes
  are now filtered on that reading; only hardware can say whether it worked.
  Two things are worth knowing before chasing it further. **Thexder cannot test
  it** — it never reads PSG registers 14/15 at all, so no joystick can drive it
  on any machine. And of the 301 FM-7 images, only 25 contain a 6809 extended
  *read* of `$fd0e` (a sound driver only ever writes that port), with Death
  Force, Wibarm, Space Harrier and Topple Zip the strongest; none of the four
  reached a poll inside 1600 frames, so a title-based test needs to get into
  the game first. The game-independent test is the F-BASIC poke sequence in
  `docs/IO_MAP.md`: it prints 238 with stick 0 held up+A, 255 if the stick is
  not arriving at all, which separates a core bug from an OSD mapping problem.
- **Keyboard layout is JIS-positional, not US** — a decision, not a bug. Shifted
  punctuation lands where a JIS keyboard puts it, which surprises US-layout
  users. Decide whether to offer a translation.
- **`$fd06`/`$fd07`** claim to be an 8251 UART and are a stub. Nothing observed
  needs them yet.

---

## FM77AV bring-up

The hardware facts and their citations live in `docs/FM77AV.md`; what is
implemented is in the RTL and its comments. What is *not* done is under
"Open FM77AV implementation gaps" below.


## FPGA fit

The core did not fit the DE10-Nano's 5CSEBA6U23I7 and was over on **both**
axes: 58,848 / 41,910 ALMs (140%) and 6,240,854 / 5,662,720 block-memory bits
(110%, Quartus error 170048 -- more than 553 M10K). Three fixes, all of them
recovering resource the design was spending on nothing:

- `PAL.v` held the 4096-entry analog palette as `reg [11:0] analog[0:4095]`
  read **combinationally**. An asynchronous read blocks RAM inference, so
  Quartus built 49,152 flip-flops plus a 4096:1 multiplexer: 21,025 ALUTs and
  49,334 registers, 40% of the design's logic and 65% of its registers, for a
  table. It is now three 4096x4 dual-clock RAMs, one per gun, addressed by the
  combinational *next* code so the registered read costs no latency.
- `ENABLE_SIGNALTAP` was left ON by an IDE session, naming a `.stp` that is not
  in the tree: 188,416 memory bits and ~1,000 ALUTs/registers of JTAG fabric.
- `AVMEM`'s 256 KB physical array was mostly holes -- VRAM lives in `CRTRAM`,
  the shared window in `SRAM.v`, font and monitor ROM in `SMEM.v`. Split into
  three blocks totalling 200 KB along the map `ram_write` already encoded.

Build it with `tools/quartus-build.sh` -- **not** `quartus_sh --flow compile`,
which deadlocks forever at 0% CPU under x86 emulation on Apple Silicon because
`NUM_PARALLEL_PROCESSORS ALL` spawns helpers that crash there. The give-away is
a log whose mtime stops advancing. The script passes `--parallel=1` per stage.

**It fits.** ALMs 22,745 of 41,910 (54%), 508 M10K of 553 (92%), fitter
successful. What it took, in order of size:

| blocks | change |
|---|---|
| 128 | `kanji.rom` to SDRAM. The only ROM that could move: every other one is fetched by a CPU every bus cycle or by the raster every character cell, where SDRAM latency is a wrong instruction or a wrong pixel. This one is read through a slow I/O window and the protocol prefetches for free -- the CPU writes the glyph address a whole bus cycle before it reads the byte. Arrives as `releases/boot.rom` on ioctl index 0, uploaded by the framework at core start, so it needs no user action. |
| 64 | `MRAM` serves the AV's `$30000-$3FFFF` page instead of `AVMEM` backing it twice |
| 64 | `AVMEM`'s 256 KB array split to the regions that are actually RAM |
| ~21 | the analog palette became block RAM instead of 49,152 flip-flops (this one was the ALM fix; it *cost* 6 blocks and saved 21k ALUTs) |
| 19 | SignalTap removed |

`make kanji-test` is the only thing covering the SDRAM path -- no title in the
suite reads the kanji window -- and it caught two bugs that would otherwise have
shipped: `ioctl_index[15:6] == 0` matches indices 0-63 and would have routed
*tape* bytes to the kanji base, and the sim's `sdram` instantiation writes
`.we ( tape_download & ioctl_wr )` with the operands reversed from the FPGA
top's, so a substitution silently missed it and kanji was never written at all.

Historical note on measurement, kept because it cost two wrong estimates:

block-memory BITS are not the budget. 5,642,883 of 5,662,720 read as 100% while
the design needed 690 M10K of 553, because a byte-wide memory uses 8 of each
block's 10 bits. Error 170048 counts blocks. Price a change from the map
report's RAM summary, never in bits.


**That fit predates `jt03`.** 508 of 553 M10K left 45 blocks of headroom, and
the YM2203 has been added since — `jt12_exprom`/`jt12_logsin` are tables and the
`jt12_sh*` shift registers are what Quartus most likes to infer as RAM. Re-run
`tools/quartus-build.sh` and price the change from the map report's RAM summary
before assuming anything below is reachable. The retired `ym2149_audio.v` gives
a little back, but not much.

### Why the three AV references were re-blessed

`shots-ref/` was rewritten for the AV rows only; the eight FM-7 rows came out
**byte-identical**, screenshots and counters, which is the evidence that
swapping `ym2149_audio` for `jt03` changed nothing on the FM-7. The AV rows
moved because all three AV fixes are CPU-visible:

| row | before | after |
|---|---|---|
| `av-demo` | 507616 I/O cycles | 507617 — one extra cycle, screenshot byte-identical |
| `av-kohakuiro` | — | unchanged, both halves |
| `av-wizardry4` | overlapping, unreadable title text | renders correctly: "THE RETURN OF WERDNA / THE FOURTH WIZARDRY SCENARIO" and its credits |

Only `av-wizardry4.png` and `counters.tsv` changed on disk. Wizardry IV is the
one to look at if this bless ever needs re-justifying — the old reference is a
picture of the bug.

### And re-blessed again for the $FD12 status bits

Two counter rows only, and **no screenshot anywhere changed** — all three AV
shots are byte-identical, as are the eight FM-7 rows:

| row | change |
|---|---|
| `av-kohakuiro` | main 5077 → 5309, io 889656 → 924729 |
| `av-wizardry4` | io 532261 → 532204 |

`$FD12` used to read back as a constant and now returns live VSYNC/DISPLAY, so
any AV title that polls it spends a different number of cycles doing so. That is
the whole of it: the two rows that moved are the two that read the register, and
the interrupt commit that followed left both numbers unchanged, i.e. neither
title arms the YM2203 timer.

The `--joystick`/F-BASIC integration check in `docs/TESTING.md` was run against
the `jt03` swap and still prints **238**, which is what covers the joystick move
from the old bus snoop onto the chip's real port A. The gate does not exercise
joysticks, so that check is the only thing that does.

### FM77AV titles: six core faults fixed, four titles rescued

The 68-image sweep joined against a 77AVEMU render of every title
(`vsim/sweep/compare-av-jt03.txt`) found 14 genuine CORE-BLANKs — and **27 of the
old "blanks" are blank on the reference too**, so were never our bug. Tracing the
worst one (Woody Poco) turned up six faults, every one a generic AV path rather
than anything title-specific:

1. **`$FD12` read back as a constant.** Bits 0/1 are VSYNC/DISPLAY, so every
   "wait for vblank" spun forever. DISPLAY needs *vertical* blanking —
   77AVEMU's `InBlank()` is `InVBLANK() || InHSYNC()`, not the horizontal
   `SBLANKn` behind `$D430` bit 7.
2. **The sub I/O MMR aperture was write-only.** Titles drive the AV keyboard
   encoder from the main side with the sub halted.
3. **The YM2203 interrupt reached nothing** — `jt03`'s `irq_n` was unconnected.
4. **`EXTIRQ` was declared and never driven**, so `$fd03` bit 3 always read
   "nothing pending" and handlers dismissed every card interrupt.
5. **Every AV write also landed on the FM-7 page.** `MRAM_rwbn` fell back to the
   raw CPU strobe whenever the physical address was outside `$30000-$3FFFF`,
   corrupting memory continuously for every AV title. This is the big one.
6. **The aperture's halt gate was inverted**, returning `$FF` exactly when the
   sub was halted. Woody Poco survived it by luck — `$FF` has the ACK bit set.

**The AV set has been re-swept since**, against a fresh 77AVEMU render of every
title, and that supersedes the old per-title tables. See below.

### The AV set, re-swept after the display and palette fixes

`results-av-f2000-postfix.tsv`, joined against 77AVEMU by
`sweep/gallery.py renders` -> `renders/gallery.html`. Of 67 titles paired:
**11 match, 6 close, 20 differ, 30 blank on both machines.**

**Read "differs" as "look at it", not "broken".** The two machines stop at
independently chosen points, so most of that 22 is scene mismatch. Tetris is the
proof: it scores 21% agreement and is a **gain** -- we render the full
4096-colour BPS title screen with St Basil's Cathedral while the reference, at
20 M instructions, is still on its copyright text. Dragon Buster scores 72% and
is also fine (trap 28). Judge these by eye on the page, not by the number.

**Genuine gains**: Tetris (blank -> full 4096-colour title screen), Deep Forest,
both Luxsor disks, Psy-O-Blade, Daiva Story 2, Digital Devil Story -- and then
Argo 34.5% -> **96.3%** and Luxsor 1 5.7% -> **98.0%** from making the drawing
ALU reachable from the main CPU.

That last change is worth remembering for its shape: it moved **exactly one row**
of the 68-title sweep and left the other 67 byte-identical, and the row it moved
got *smaller* -- Luxsor 42128 -> 12297 bytes. A correct render with the ALU
masking properly has far fewer spurious colours than a wrong one, so it
compresses better. Size-based triage scores that fix as a regression.

**We render nothing where the reference renders something** -- the real blank
list, and it is longer than the old "six" because that list predates this
comparison: Shounen Mike, the FM77AV demo disk (both copies), FM Sound Editor,
Mahjong Kyou Jidai Special 1, Woody Poco 1, Pro Yakyuu Fan, In the Dream, Little
Box, Ys II program disk, Yami no Iyo Densetsu 1. The last few are marginal --
the reference itself draws only 1-10% coverage on them.

**Do not use the old sweep as a baseline.** `results-av-f2000-jt03.tsv` was
taken with a displaced raster and a dead palette, and several of its "renders"
were artifacts of exactly that: FM Sound Editor scored 100% coverage there while
executing 604 instructions a frame -- a screen flooded with one colour by a
palette that was never written. PNG byte size is worse than useless now, since a
more correct render often compresses smaller.

### The rendering artifacts were the display phase and a dead palette

Two faults, both found by comparing against 77AVEMU in **palette-nibble space**
rather than by eye. (Byte-exact pixel comparison is useless between the two:
`PAL.v` expands a 4-bit gun level with CSP's `{n,$F}` and 77AVEMU replicates the
nibble, so every non-black pixel differs. Both keep the level in the high
nibble, so `>>4` on each side makes the comparison meaningful.)

1. **The whole picture sat to the right of where it belonged** — three pixels in
   640 mode, two in 320. `HBLANK` came straight off MB60H010's `xx`, but a pixel
   arrives several stages later: raster address, CRTRAM's synchronous read,
   `SFTLODn`'s deliberate settle delay, then PAL. The two modes differ by one
   because their paths do: 640 goes `SFT -> qh -> grb`, 320 goes
   `shift-register -> palette RAM output`. Fixed by delaying the display
   blanking to match, which leaves `HBLANKn` (and so `SCASSEL`, the VRAM
   arbitration) untouched: **every counter in the eleven-row gate is byte-
   identical across the change and only screenshots moved.**
2. **The FM77AV analog palette never took a single write.** `PLTREGn` is the
   schematic decode for `$fd38-$fd3f`, and `PAL.v` asked for
   `~PLTREGn && ~MADDRBUS[3]` — `MADDRBUS[3]` high and low at once. The table
   stayed at its power-on identity ramp for the life of the AV support.

Measured, not inferred. Pixels matching 77AVEMU, before → after, comparing at
points where both machines are showing the same thing:

| title | mode | before | after |
|---|---|---|---|
| Deep Forest | 320 | 20.8% | **100.0%** (63991 / 64000) |
| 2019 demo | 320 | 10.8% | **99.9%** |
| Wizardry IV | 640 | 90.7% | **99.1%** |
| F-BASIC banner (FM-7) | 640 | 97.5% | **99.8%** |
| Psy-O-Blade | 640 | — | **96.6%** |

and, for the phase alone, a third measurement that involves no reference at all:
`tools/raster_phase.py` reconciles the core's own VRAM with its own screenshot,
and went from peaking one column out to 99.1% at zero offset.

**The constant was nearly wrong by one.** The first offset sweep ran ±2 and
reported the 640-mode error as 2, because the search window ended exactly where
the answer was. Widening it to ±5 showed a sharp peak at 3. Size the window
from what you are willing to be wrong about.

Why the palette bug survived so long is worth keeping: a 4096-colour photograph
is normally displayed through very nearly the identity ramp, so Deep Forest,
Luxsor and Psy-O-Blade all looked *plausible* with the table dead. Only software
that programs a genuinely different map exposes it — the demo's colour chart
does, and it rendered as the raw plane code.

**The earlier "we set pixels that should not be set, ~15% more non-zero bytes in
every plane" was wrong**, and worth recording as the trap it was: our VRAM dump
was taken at a point where the reference had already drawn the "DEEP FOREST"
logo — a black box over the landscape — and we had not. The extra bytes were the
landscape the reference had painted over. The giveaway was that the mismatching
rows were 101-138 and nothing else: exactly the logo box, not the "every plane
and both banks" the byte counts suggested.

**Still eliminated, do not re-check:**

* **The MB61VH010 drawing ALU.** `--trace-av-video` over 200 frames: 9356
  `SUBVRAM`, **0 `ALUW`, 0 `AVVRAM`**. Deep Forest never uses it.
* **The 320-mode sub-CPU address transform.** `MB60H010.v` `SUBRA_320` preserves
  bit 13 and wraps the low 13 bits, matching 77AVEMU's `TransformVRAMAddress`
  (`fm77avcrtc.h:219`) case by case.
* **The picture width.** The reference emits 320x200 PNGs in 320 mode; this core
  renders the same mode pixel-doubled to 640x200 by design. Not a fault, and the
  doubled pair provably never disagrees.

**Deep Forest was never "stuck", either.** With the palette dead it snapped to
full brightness the instant VRAM was drawn and then sat unchanged from frame 900
to 1500, which read as a stall. It is in fact fading in through the palette,
synchronised to `$fd12` vblank polls at `pc=$622a`: black at 900, half up at
1200, complete at 1500, and that frame is the 100.0% row above. What remains
open is only the title logo, which the reference draws between its frames 1200
and 2100 and we do not.

**`av-kohakuiro`'s blessed screenshot was a picture of the bug, and its
replacement is a black screen.** It was picked for the gate on "81% coverage, 18
colours — the strongest exercise of the 320-mode plane path outside the demo".
That picture only existed because the palette was stuck at the identity ramp:
77AVEMU renders this disk black from its frame 500 to the end of a 30 M-step
run, and our new shot matches it on **100.0%** of pixels with zero non-black
pixels, where the old blessed one had 104,246 against the reference's none.

So the row is now correct and nearly worthless as a test. **The gate needs a
different second AV title** — one that renders real graphics *and* is stable at
the shot frame with a live palette. Deep Forest around frame 1500 and
Psy-O-Blade are the candidates; both were measured against 77AVEMU above. Pick
one by re-checking it at two frame counts first, which is the rule that put
Kohakuiro here in the first place.

**Luxsor is the one still visibly wrong.** It renders its pyramid scene in
garish green and red at frame 1980, and no reference frame in a 30 M-step run
matches it above 5.6%. Treat that number with care, though — the reference is on
a completely different scene (a dialogue screen) by then, so the two are not
aligned and the comparison is not yet evidence of a video fault (trap 20). Get
them onto the same screen first.

### `$FD37`'s CPU access mask, and why only a bench can cover it

Bits 2:0 close a gun to the CPU: 77AVEMU suppresses the store and returns `$FF`
on the read, for either CPU (`fm77avmemory.cpp:830-878` and `:539-575`). Both
are implemented in `CRTRAM.v`, for the sub CPU and the main aperture alike.

It had reached nothing at all, and it took two stacked faults to get there.
`SUBCRTADDR` folds the mask into `SVCASBn/SVCASRn/SVCASGn` as
`SBLANKn & SDRAMVn & SCASSEL` — and `SBLANKn` *is* `~SCASSEL`, so all three were
identically zero. `CRTRAM` then declared those three as inputs and never
mentioned them again. A signal that could not assert, feeding a port that
ignored it.

**No title in hand writes `$fd37`**, so the breadth sweep is structurally
incapable of covering this and `make crtram-test` is the only evidence there is —
six directed assertions on the write and the `$FF` read, both paths. Do not try
to "confirm" it from a title.

### The first byte of every sector is lost at the bus boundary, not in the FDC

Measured, not inferred, and the measurement overturned both of the obvious
theories. `make DEBUG_FDC_READ=1` prints the buffer base per sector and one line
per byte the controller hands over. On Thexder's first sector:

```
FDCSEC start: buff_a=002c0 base=192 sector_size=256 blk_size=0
FDCRD byte_addr=192 buff_dout=20 ...
FDCRD byte_addr=193 buff_dout=08 ...
FDCRD byte_addr=194 buff_dout=0a ...
```

The image really does begin `20 08 0a 00 10 00 00 04`, so **`wd1793` presents the
right byte, at the right pointer, from the right buffer base, on time.** The read
pointer is not off by one and the SD block fetch is not late -- both were
plausible and both are wrong.

The CPU nevertheless reads `03 08 0a ...` (`tools/iodiff.py` against 77AVEMU,
which reads `ff 1a 50 32` on Shounen Mike and `20 08 0a` here). From the SECOND
read onward the CPU sees exactly what the controller emits. So the first read
samples stale data *and still advances the controller*: one byte is consumed
without being delivered.

**That puts it in `FDC.v`'s bus boundary -- the `FD_Dout` mux and the read strobe
that sets `read_data` -- not in the controller.** The obvious suspect is the
RDQEn two-strobe mechanism (`docs/REFERENCE.md` section 2): every `$fdxx` read
decodes as a Q-phase pulse and an E-phase pulse, and a data register that
advances on the wrong one hands the CPU the byte before or after the one it
latches. That section's fix idiom -- acknowledge only at the close of the
E-phase pulse -- is the first thing to try.

**It is general, not a title's blocker.** Thexder loses its first byte and boots
correctly, so every loader in the suite already tolerates it. Do not expect
fixing it to rescue a blank title; expect it to remove a whole class of
one-byte-shifted reads that nothing has yet been shown to depend on.

### $FD1E is a drive-mapping register and we do not implement it

77AVEMU `fm77avfdc.cpp:817-831`: `$FD1D` bits 1:0 select a drive *through*
`mapDrive()`, and `$FD1E` bit 4 enables a logical-to-physical drive map whose
entry is `(data>>2)&3 -> data&3`. Bit 6 is the 2D/2DD drive mode. Our core
decodes neither — `$fd1e` shows up in the sim's undecoded-port list.

Pro Yakyuu Fan is not explained by it (it writes `$fd1e <- $40`, i.e. drive mode
only), but the register is real and cited, and a title that remaps drives will
misbehave until it exists.

### Pro Yakyuu Fan: selects an unmounted drive and waits for it

It polls `LDA $fd18 / BITA #$81` — bit 7 is drive-not-ready — and reads `$b4`
586,859 times. The last `$fd1d` write is `$81`, i.e. **drive 1**, which the
sweep never mounts, so `ready1` is low forever. The reference renders its title
screen from the same single-disk setup, so it gets past this somehow. Find out
what 77AVEMU reports for an absent drive before changing `FDC.v` — its
`DriveReady()` lives in the shared TOWNS FDC
(`refs/TOWNSEMU/src/diskdrive/diskdrive.cpp:1346`) and returns false for an
unloaded drive, which does *not* obviously explain it.

**The reference does not get past it by mounting a second disk.** Its headless
driver sets `fdImgFName[0]` only (`tools/77avemu_headless.cpp:240`), exactly like
the sweep, and `DiskDrive::DriveReady()` returns false for an unloaded drive
(`refs/TOWNSEMU/src/diskdrive/diskdrive.cpp:1346`), with `$FD18` bit 7 built
straight from it (`fm77avfdc.cpp:906`). So the reference sees drive 1 not-ready
too and still renders. **That makes this a first-divergence hunt, not a
drive-mapping fix**: our `$fd1d <- $81` is a symptom of going wrong earlier.

Also settled: the drawing-ALU aperture fix does not help it. 77AVEMU names Pro
Baseball Fan as the title that triggers hardware drawing by dummy-writing, which
made it a fair guess, but it retires 5435 instructions a frame sitting on
`$fd18` and never reaches its drawing at all.

### Nothing in the collection uses 640x400 (superseded claim, corrected)

**A previous version of this file said In the Dream and Little Box select
640x400 via `$FD04` bit 3, and that is wrong.** The evidence was that 77AVEMU
renders them into a 640x400 PNG. It sizes the buffer 640x400 for **both**
`SCRNMODE_640X200` and `SCRNMODE_640X400` (`fm77avrender.cpp:106-109`) and
line-doubles the former, so **the image dimensions do not identify the mode.**

What does identify it: in 640x200 the renderer writes `rgba0` and `rgba1` with
the same pixel, so every even row equals the odd row below it; in a true 640x400
they differ. Across all 22 640-wide renders in the AV set — Ys, Wizardry IV,
Psy-O-Blade, Argo, Druaga, Return of Ishtar, In the Dream, Little Box and the
rest — **0 of 200 row pairs differ in every single one.** No title in hand uses
640x400, and implementing it would buy nothing.

So the earlier `BITB $d430` lead on In the Dream stands undisturbed, and those
two titles remain unexplained.

Keep the register fact, which is real and cited: `$FD04` bit 3 clear selects
`SCRNMODE_640X400` and bit 4 selects `SCRNMODE_320X200_260KCOL`
(`fm77avcrtc.cpp:205-219` `WriteFD04`). This core models neither — `AV_MODE_320`
is one bit off `$FD12` bit 6 — and decodes `$fd04` only as the FM-7's attention
register. That is a real gap; it is just not the gap these two titles fell into.

### `$fd04` bit 2 reads BUSY here and `1` everywhere else

`TIMER.v` returns `{5'b11111, BUSY, BREAKn, m45_q8n}`, derived from the
schematic. **Four references now disagree**, and none of them agrees with any
other reading either: MAME leaves the bit set, CSP ORs in `$7c` and puts
sub-busy at bit 7, 77AVEMU returns `~firqSource` so b7:2 all read 1, and sedoc
tabulates it straight from the Fujitsu system manual as `bits 7…2 unused`
(`refs/sedoc/8bit/fm7/ml.md:106-112`, citing SS:1-8).

Measured divergence, first one found: Woody Poco reads `$fd04` twice, at
`pc=$6120` and `pc=$5013`, and gets `$fb` where 77AVEMU returns `$ff` — bit 2
only. Its screen is now explained by the ALU trigger instead (fixed), so this
did **not** turn out to be its bug and remains uncorroborated by any title's
behaviour. Left alone deliberately: changing it is a one-line edit, but doing so
on a reference disagreement rather than on a measured symptom is how the wrong
answer gets locked in. Revisit when a title's *behaviour*, not its register
read, depends on it.

### Shounen Mike: the video path is fine, the title does not progress

The largest gap in the set -- 99.9% coverage and 200 colours on the reference,
nothing here -- and it is **not** a video bug. Triaged with `--trace-av-video`
over 600 frames:

* 27614 sub-CPU VRAM writes, all in frames 0-199, then they stop.
* From frame 150 the title works purely through the drawing ALU in **TILE**
  mode (`$D410 <- $86`), 672 operations across 450 frames, loading
  `$D41C/D/E` before each.
* Those operations write real data -- 352 of `ff/ff/ff` and 320 of `00/00/00`.
  It is drawing and erasing something small, over and over.

So the machine is executing (6574 main, 8707 sub per frame), the ALU is firing,
and the bytes it writes are the bytes it was told to write. VRAM ends up empty
because the title never reaches the artwork the reference paints -- 672 tile
blits in 600 frames is not a screen. This is the Woody Poco class: find why it
does not progress, and do not look at the video path.

**Four suspects eliminated, do not re-check:**

* **The ALU's main-CPU read trigger** (the fix that rescued Woody Poco). Does
  not apply: Mike's sub CPU is *not* halted -- 8650 instructions/frame, halted
  0.1% of cycles -- so its ALU work goes through the sub path, and that path was
  never direction-qualified (`alu_access = enabled & SUB_VRAM_SEL & SCASSEL &
  SEB`). Measured after the fix: still 0.0% coverage, 1 colour, against the
  reference's 99.9% and 200 colours. Unchanged.
* **`$FD37`'s access mask.** It never writes `$fd37` in 620 frames.
* **Fine scroll (`$D430` bit 2).** It sets that bit in every `$D430` write, so
  it *asks* for the unmasked VRAM offset that `MB60H010` does not implement --
  but it never writes `$D40E`/`$D40F` at all, so the offset stays 0 and the
  missing feature cannot be its problem. (The gap is real and still open; see
  below.)
* **The drawing ALU.** It fires, and the `q`/`d` bytes in the trace are correct.

### The original Fujitsu FM77AV demo disk stalls in an FDC retry loop

`software/D77/FM77AV demo.d77` (and its duplicate `FM77AV-DEMO.D77`). Reference
renders 92.8% coverage in 13 colours; this core renders nothing, at **every**
frame sampled -- 400, 680, 800, 1000, 1200, 1400, 1600, 1980. Not `av-demo` in
`run_tests.sh`, which is CaptainYS's 2019 demo and passes.

Fixed on the way here: `$fd13` did not set BUSY (`b8ff6ac`).

**Where it stops.** At frame 1000 the sub CPU is idle in its command-wait loop
and the main CPU is in the boot ROM's floppy wait:

    $ff98  LDB <$1f     ; DP=$fd, so this is $FD1F -- b=$3f, DRQ clear
    $ff9a  BPL $ffa2
    $ffa2  LSLB         ; b=$7e, INTRQ clear
    $ffa3  BPL $ff98    ; spin

`dp=fd` is the whole point: the byte is the FDC's DRQ/INTRQ register, not RAM.

**Why.** `$fd18 <- $80` (read sector) is issued **2048** times here against the
reference's **444**, and the extra attempts return status `$10` -- Record Not
Found. Every other FDC command matches exactly: `$1c` seek x19, `$0a` x4, `$08`
x1, on both. `DEBUG_FDC=1` shows **444 WDMATCH successes**, i.e. we read every
sector the reference reads and then keep asking for one more.

The first failure is at frame 348, and the request is malformed rather than
missing: the BIOS writes the TRACK register `$fd19 <- $00` at `pc=$fe95`, then
side `$fd1c <- $00`, sector `$fd1a <- $02`, then `$fd18 <- $80` -- asking for
cylinder 0 with the head parked at track 14, which a WD1793 correctly answers
with Record Not Found. The reference never makes that request.

The RNF itself is **correct and is not the bug**. The scan visits the right
entry -- `addr=449 entry trk=14 side=0 sec=2`, wanting exactly that -- and
rejects it on the fourth term of the match, `edsk_trackf == wdreg_track`: the
ID cylinder must equal the WD track register, which the BIOS has left at 0.
That is what a real WD1793 does.

**Eliminated, do not retry: removing that term.** Measured both ways --
Daisenryaku 67.3% -> 0.1% coverage (it is load-bearing, which is why it was
added), and the demo unchanged at 0.0%. A clean double negative.

**The boot ROM is not the difference.** `$FE00-$FFDF` -- all 480 bytes of BIOS
code -- is byte-identical across `vsim/roms/boot_bas.rom`,
`vsim/roms/fm77av_boot_basic.rom.mem` and `refs/local/fm77av-roms/BOOT_BAS.ROM`.
Only `$FFE0-$FFFF` differs, and only in fill: `$ff` in ours, `$00` in the
reference's image. That range is the BIOS work area (the `$ffe1` track cache,
`$ffe5`, `$ffe8`) plus the vectors, and the loader writes the cache entries at
boot anyway, so both machines reach the same values. Worth knowing before
diffing PCs in this region.

**Both machines park the head on track 14.** 19 `$1c` seeks on each, issued by
the demo's own code at `$023f`/`$024e`/`$0253`, and the reference's destination
list ends `... 03 0F 0A 0E` -- `$0e` = 14. So the head position agrees and the
reference reads track 14 sector 2 where the BIOS asked for cylinder 0, because
it looks sectors up by head position and never checks C.

**The demo retries forever, by design.** The BIOS error path is
`$ffa5 LDB <$18 / BNE / BITB #$80 / BITB #$40 / BITB #$14 / ORCC #$01 / RTS`
-- it classifies the error into A ($0c for RNF) and returns carry set. The
demo's own code then does `$011c BCS $0119 / $0119 JSR $fe08`, an
**unconditional retry with no counter**, and throws the error code away. So this
read is not allowed to fail on real hardware: whatever the machine does, it must
answer it.

That is the crux. On this disk every sector's ID C equals its physical track
(checked: 0 of 1296 differ, and 0 of 1292 on Daisenryaku), so
`edsk_trackf == wdreg_track` reduces exactly to "track register must equal head
position" -- 0 vs 14 here. A real WD1793 compares C to the track register, so by
the datasheet this read fails; yet the disk shipped and worked.

So one of these is true and none is yet established:

1. Something should have left the track register at 14 -- e.g. a real WD179x
   ignoring the `$fd19` write. This core models the ignore-while-BUSY rule
   (`WDDROP TRACK`), and the BIOS polls status `$00` (idle) before writing, so
   that path does not fire.
2. `disk_track` should not be 14 by then, i.e. this core moves the head where
   the machine would not.
3. The C comparison has a qualifier this core does not model.

So the question is upstream: why is the head at track 14 when the BIOS asks for
track 0? Either `disk_track` is wrong here, or the BIOS has a path that should
have updated `$ffe1`/re-seeked and does not run. Note `$ffe1` is written exactly
once, at boot, and read 77 times -- if the real BIOS updates it after a seek,
find what writes it. The BIOS also reads `$fd1d` at `$fef4` and `$fd1b` at
`$fed7` in the window before `$fe95`, and `$fd1d` is still the unexcluded
three-way disagreement below.

**`$fd1d` is a known three-way disagreement and is NOT yet eliminated.** We
return `$bc`, 77AVEMU returns `$80`, every time (2477 vs 873 reads). Both agree
on bit 7 (motor) and bits 1:0 (drive); they differ on bits 5:2, which CSP builds
as a constant `$3c` (`floppy.cpp:178` `get_fdc_motor`) and 77AVEMU leaves zero
(`fm77avfdc.cpp:946-949`). This core follows CSP deliberately -- see the long
comment in `FDC.v`, where following MAME here was what stopped Ys entering its
loaded program. Bits 5:2 should not matter to a bit-7 motor test, so this is
recorded as unexcluded rather than as the suspect.

**Do NOT re-investigate:**

* *The video path.* At frame 500 VRAM holds 7972/8192 non-zero bytes in blue and
  zero in red/green, which is exactly what `$fd37 = $de` asks for (CPU/ALU mask
  `$de & 7 = 6` blocks red and green; display mask `($de>>4) & 7 = 5` blocks blue
  and green). A black screen mid-sequence is correct. `AVHDRAW.v`'s
  `plane_mask = bank_mask | VPAGE_MASK` also matches 77AVEMU's
  `bankMask | VRAMAccessMaskFromCPU`, which carries its own citation to a 2022
  experiment on a real FM77AV (`fm77avcrtc.cpp:410-412`).
* *The sub-command protocol.* `iodiff.py --ports=05` matches **1439 of 1440**
  accesses on direction, port, value AND PC. Our whole run is a prefix of the
  reference's; nothing diverges, we just stop early.
* *Superseded claim: "the gap is sub command `$18` = PAINT, dispatched 6 times
  here against 135 there."* That compared a 10-frame window of this core against
  the reference's entire run. The whole-trace comparison above contradicts it.
  PAINT is missing because the machine stalls before reaching it, not because a
  branch is taken differently.
* *The boot sector read.* Correct here; 77AVEMU's is the one that is off by one
  (REFERENCE.md section 1).

### Sub RAM and the sub monitor ROM are reachable through MMR with the sub running

77AVEMU discards a main-CPU access to the whole of physical `$10000-$1FFFF`
while the sub CPU is running -- read `$FF` (`fm77avmemory.cpp:737-742`), store
dropped (`:805-810`). This core now gates the sub I/O page (`core.v:596`) and
the VRAM aperture (`AVMEM.v`, `sub_open`), but not sub RAM `$1C000-$1D37F` or
the font/monitor ROM `$1D800-$1FFFF`, which `ram_sel`/the block selects still
serve unconditionally.

No title in hand is known to read either with the sub running -- the gate on
the two ranges that *are* covered rejects zero accesses across the collection,
which is what a correctly-observed handshake looks like. Finish the range when
something turns up that needs it, and instrument the rejected accesses (as
`DEBUG_AVDRAW=1` does) so "the gate blocks nothing" can be told apart from
"the gate is not in the build".

### The MMR aperture cannot READ the drawing ALU registers

The same family as the trigger bug that rescued Woody Poco, found while
auditing for others. `AVHDRAW.v` has a readback mux for `$D410`/`$D411`/
`$D412`/`$D413`/`$D41B`, but `core.v:409` routes it into the **sub** CPU's read
mux only (`SADDRBUS`). The main CPU's aperture read path
(`AV_SUBIO_dout`, `core.v:617-621`) decodes `$D430`/`$D431`/`$D432` and returns
`$FF` for everything else, so a main-CPU read of the ALU registers gets `$FF`.

77AVEMU routes them: `MEMTYPE_SUBSYS_IO` in the fetch path calls
`IORead(accessFrom, addr)` with no check of which CPU is asking
(`fm77avmemory.cpp:759-760`), and the `$D413` case returns the live compare
result.

Measured, but **not yet known to break anything**: Woody Poco reads `$D412`
through the aperture 41 times in the reference and gets `$00`; we return `$FF`.
Its subsequent writes to `$D412` are `$00` on both sides, so the value is not
carried into behaviour there. The register to worry about is `$D413`, the
per-pixel COMPARE result -- a title doing hit-testing from the main side would
read "every pixel matched" from us. No title in hand is known to do that; find
one before changing this, and re-read trap 33 first.

### `$D430` bit 2 -- the unmasked VRAM offset -- is not implemented

77AVEMU: `if(0!=(data&4)) VRAMOffsetMask=0xffff; else 0xffe0`
(`fm77avcrtc.cpp:271-282`). With the bit set the scroll offset's low 5 bits are
live, i.e. fine scroll rather than 32-byte steps.

`MB60H010.v` hardcodes the masked form -- `VOFFSET0 = {SRH[5:0], SRL[7:5], 5'd0}`
-- so a title that sets the bit and then writes a fine offset scrolls to the
wrong address. Shounen Mike sets the bit but never writes the offset, so nothing
in hand is known to need this yet. Recorded because it is a real divergence with
a citation, not because a title is waiting on it.

### The next lead: another undelivered interrupt

Two of the remaining blanks wait on a **main-RAM flag that only an interrupt
handler can set**, which is the same shape as the YM2203 fault above:

* **Woody Poco** now runs 2438+ serviced interrupt cycles and reaches `$c989`,
  inside the `$c9xx` region 77AVEMU executes in, but still draws only one glyph.
* **In the Dream** spins on `BITB $d430 / BEQ` — and note `$d430` there is *not*
  the sub I/O register: main `$Dxxx` maps to the FM-7 page, so it is ordinary
  RAM. It writes `$fd02 <- $40`, which per CSP `fm7_mainio.cpp:459` enables
  **RXRDY** and nothing else, then takes one interrupt in 900 frames.

The other two shapes, for whoever picks this up:

* **Pro Yakyuu Fan** polls `LDA $fd18 / BITA #$81` — the FDC status register,
  so an FDC problem rather than an interrupt one.
* **Little Box** executes garbage at `$61b8` with a dead main CPU
  (243 instructions/frame) — a runaway, and a different fault again.

### Open FM77AV implementation gaps

- The main-CPU MMR path into the sub aperture is implemented for **writes**
  only. No software in hand reads `$1D4xx`, and the reference gates the whole
  aperture on the sub CPU being halted while this core gates only the new
  sub-I/O half (the VRAM half stays ungated, as before).
- The drawing ALU's line trigger (`$D42B`) is implemented but no title in hand
  writes it, so it is unexercised.
- Host key events are not connected to AV scan codes; `$D431`/`$D432` answer the
  encoder protocol but no key ever arrives.
- 77AVEMU also suppresses the sub NMI while the sub CPU is halted
  (`fm77av.h:340`); this core does not, and nothing in hand needs it.
- **Eight `$FDxx` ports are still genuinely undecoded on an AV run.** With
  `port_is_decoded()` in `sim_main.cpp` taught the AV map, the summary line is
  worth reading again, and 60 frames of Ys leaves: `$0b` (boot-mode flag,
  read once), `$1e`, `$25`/`$27`/`$29`/`$2b` (7 accesses each) and
  `$96`/`$97` (10 each, written by the initiator through `LDU #$fd96`). None is
  in `docs/IO_MAP.md` or `docs/FM77AV.md`; find out what they are before
  assuming they do not matter.

Research and reference addresses are in `docs/FM77AV.md`.

### Build-file housekeeping

`FM-7_MiSTer.qsf` carries an IDE-injected per-file list that duplicates
`files.qip` (which the qsf sources). It is a strict duplicate apart from
`sys/sys.qip`, and `docs/REFERENCE.md` says to delete it whenever Quartus writes
it back. It has not been deleted this time — only the retired `ym2149_audio.v`
line was removed from it, so the two lists agree again.
