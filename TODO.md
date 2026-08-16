# TODO

Open work only. Fixed items leave this file — the conclusion goes in a code
comment, the journey stays in the commit message. See `CLAUDE.md`.

Reference material: `docs/REFERENCE.md` (read first), `docs/IO_MAP.md`,
`docs/TESTING.md`, `docs/FM77AV.md`.

---

## Start here

**Where it stands.** The nine-row gate is green — `./run_tests.sh` in `vsim/`
compares screenshots *and* counters against `shots-ref/`. FM-7 boots, Thexder
runs, the FM77AV demo matches 77AVEMU plane-for-plane, and **Ys (FM77AV) now
boots and draws its title screen**. The PSG became a `jt03` (jotego/jt12) that
also supplies the FM77AV's YM2203, so `$FD15`/`$FD16` are decoded for the first
time and **the combined work now ships as GPLv3** (see `Readme.md`). **None of
it has run on hardware**; `HARDWARE-HANDOFF.md` is the FPGA side's log and its
newest section says what to check first.

**Open, in priority order:**

1. **The FPGA fit is unknown again.** The last successful fit was 54% ALMs and
   508 of 553 M10K — 92% of the block RAM on the device — and `jt03` has been
   added since. `tools/quartus-build.sh` has not been run against it. Nothing
   below matters if it does not fit.
2. **Re-sweep the FM77AV set.** Every AV figure in this file predates the two
   fixes below, so the "59 of 68 are blank" table is stale and must not be
   quoted. `vsim/sweep/av-sweep.sh` at 2000 frames, then `classify.py`.
3. **The FM sound has never been heard.** `make sound-test` proves registers
   reach the chip and that the FM-7's SSG pitch is bit-identical to the retired
   `ym2149_audio`, but nothing proves the notes are right — and the AV's
   prescaler question in `docs/FM77AV.md` §Sound is open by construction.
4. Timing closure is unverified — `map` and `fit` pass, `asm`/`sta` have not run.

**The 77AVEMU reference is ready to use, no rebuild needed.** It lives in
`refs/local/` (gitignored, but persistent) rather than `/tmp`:

```sh
refs/local/fm77av_headless refs/local/fm77av-roms \
    'software/D77/Ys (FM77AV) (Disk A).d77' 20000000 /tmp/ys-ref.png
```

`refs/local/av-divergence/` holds its renders of Ys, Argo and Laydock. **Ask the
reference before theorising.** It settled the last five bugs. On Ys it killed a
whole line of enquiry in one run: the sub CPU sitting at `$c036` reads as a
deadlock, and the reference sits at exactly the same address with the title
screen drawn — that is the program's normal idle loop, not a hang.

## Awaiting hardware

Four commits are on `alanswx/fdc-d77-support` and have **not** been confirmed on
real hardware. Simulation cannot settle the glitch-domain classes.

| commit | what | hardware risk |
|---|---|---|
| `e699e9d` | `SOUND.v` `$fd0d` off its derived clock | **only hardware can validate this** — the sim test (joystick reads 238) passes, but the bug class is invisible in Verilator |
| `77c2780` | `$fd02` enable-bit polarity | changes interrupt delivery for every title |
| `b1aff78` | `$fd03` acknowledge | changes interrupt acknowledge for every title |
| `777d8d4` | `$fd04` attention acknowledge | as above |

Sharpest checks: **Ys** should reach its town map and be playable; **1942**
should reach its title menu. Both were completely dead before.

`m77` in `KEYBOARD.v` remains on an async decode strobe. Three hardware attempts
to convert it all failed (0/8) and a sim experiment showed all four candidate
designs capture identical values at identical times — see `docs/REFERENCE.md`.
Leave it async unless there is new evidence.

Hardware-side update (2026-08-08): `alanswx/fdc-d77-support` reported that
`1735adb` fixes an intermittent power-on clock-mux glitch in `CLKCTRL.v` by
giving `switch` a defined startup value and sampling `SW2` on `CLKSYS`. It is
integrated locally.

(Superseded claim: *"the full simulation regression still passes; the reference
counters moved by the expected startup timing shift... so the references were
re-blessed"* — none of that held. No bless was ever committed; `shots-ref/` is
still the one written at `e19cde7`. The counter move was **not** a timing shift,
it was `ca75bfe` breaking the main-to-sub shared-RAM mailbox, which booted the
FM-7 to a blank screen. See the SRAM entry below. With that fixed the suite
reproduces `e19cde7`'s references exactly, counters and screenshots, so the
references were correct the whole time and needed no bless.)

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
the ID cylinder unconditionally, matching 77AVEMU. The core's FDC command stream
then follows the reference through the later track loads and reaches the
Daisenryaku title screen at frame 621. The supplied sibling `refs/TOWNSEMU` now
satisfies 77AVEMU's build contract. With the exact FM-7 ROMs, the first BIOS
divergence is still `$fd05`: 77AVEMU reads `$fe` (BUSY asserted after reset),
while this core reads `$7e`; forcing BUSY high changes timing but is not needed
for the title fix. Hardware confirmation remains useful. Return and Space reach
the keyboard latch, and the DOS boot-ROM selections do not mount this FM-7 disk.

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

**Four titles went from rendering nothing to rendering game art**, measured at
2000 frames:

| title | before | after |
|---|---|---|
| Deep Forest | 3790 | **98940** — landscape with title logo |
| Luxsor (Disk 1) | 3790 | **40843** — pyramid scene |
| Psy-O-Blade | 3841 | **24536** — character portraits |
| Luxsor (Disk 2) | 3790 | **17023** |

with Daiva Story 2 (7510) and Silpheed (7410) newly partial. **The renders are
not clean** — colour banding on Deep Forest, vertical stripes on Psy-O-Blade,
wrong palette on Luxsor — so there is at least one video-path fault left. Diff
the VRAM against the reference (`docs/TESTING.md`) rather than guessing at it.

Six remain blank: Woody Poco, Shounen Mike, Pro Yakyuu Fan, FM77AV demo, In the
Dream, Little Box.

### The rendering artifacts are in the sub-CPU VRAM write path

The four rescued titles draw, but with banding, stripes and wrong palette. A
VRAM diff against the reference (`FM77AV_VRAM_DUMP` / `FM7_VRAM_DUMP`, method in
`docs/TESTING.md`) on Deep Forest, **with both machines on the same title screen
so the comparison is legitimate** (trap 20):

* all twelve 8 KB slices differ
* ours has consistently **more** non-zero bytes than the reference — bank0 B0
  3504 vs 2548, bank1 R1 7444 vs 6360, ~15% more throughout

So we are setting pixels that should not be set, in every plane and both banks.

`--trace-av-video` says where they come from, and it rules out most of the video
back end: over 200 frames Deep Forest issues **9356 `SUBVRAM` writes, 0 `ALUW`,
0 `AVVRAM`**. It draws entirely through the sub CPU's own VRAM writes — no
drawing ALU, no main-CPU MMR aperture. So the fault is in the sub-CPU VRAM write
path: the 320-mode address transform, the `$FD37` plane-access mask, or the
scroll offset. It is **not** the MB61VH010, which is where the eye is drawn.

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
