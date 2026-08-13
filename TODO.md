# TODO

Open work only. Fixed items leave this file — the conclusion goes in a code
comment, the journey stays in the commit message. See `CLAUDE.md`.

Reference material: `docs/REFERENCE.md` (read first), `docs/IO_MAP.md`,
`docs/TESTING.md`, `docs/FM77AV.md`.

---

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

Playable, but only characterised as far as the town map. Nobody has played
further to see what breaks next.

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

- **PSG pitch** needs a human ear. `SOUND.v`'s select was fixed but nobody has
  confirmed the notes are right.
- **Keyboard layout is JIS-positional, not US** — a decision, not a bug. Shifted
  punctuation lands where a JIS keyboard puts it, which surprises US-layout
  users. Decide whether to offer a translation.
- **`$fd06`/`$fd07`** claim to be an 8251 UART and are a stub. Nothing observed
  needs them yet.

---

## FM77AV bring-up

The OSD and simulator now have a machine-family selector. The initiator overlay
is mapped at `$6000-$7FFF` (and supplies `$FFFE-$FFFF`), AV F-BASIC is mapped at
`$8000-$FBFF`, and `AVMEM.v` now models writable boot RAM, `$FD80-$FD93`
MMR/TWR registers, and the 256 KB physical main-memory map. The `$FD13`
sub-monitor selector now switches the secondary CPU's `$E000-$FFFF` window
between the Type C, A, and B monitor images. `make avmem-test` covers identity
RAM, bank translation, TWR, boot seeding, boot-RAM writes, and monitor select.
The main-CPU MMR aperture into the three shared VRAM planes is wired and
`make crtram-test` checks blue/red/green storage.
The AV `$D800-$DFFF` character-generator aperture is now banked by the
sub-system `$D430` register; `make smem-test` checks the ROM banks and status.
The `$D430` display/active page bits now select the page on the shared
raster/sub-CPU VRAM port; `make crtram-test` covers both page paths.
The main-CPU VRAM aperture now uses `$D430` bit 5 as its bank select;
`make crtram-test` covers a bank-1 write/read. Mode gating and the 320×200
address transform are wired through `$FD12` and the existing scroll offset;
`make avmem-test` covers both masks. The raster now uses 40-byte lines and
doubles each logical pixel, while retaining the FM-7's 640-clock line timing.
The FM77AV `$FD30-$FD34` analog palette index/component registers are now
separated from the FM-7 digital palette and tested with the reference reset
ramp and DAC expansion.
The reference-matched 12-plane pixel-code combiner now assembles
`{G3,G2,G1,G0,R3,R2,R1,R0,B3,B2,B1,B0}` MSB-first and has a directed test.
The raster offset latches now retain separate access/display page values and
reset to zero; `make mb60h010-test` covers the split selection.
CRTRAM now stores each gun as four 8 KB slices, exposes all twelve raster
bytes in 320 mode, and feeds the analog palette's 24-bit RGB result at the
core boundary; `make crtram-test` covers the four B slices.
`$D40E/$D40F` capture is qualified by the exact sub-CPU address and write
strobe. The demo reaches the matching CPU checkpoint, but its simulated VRAM
contents still need a write-path comparison against 77AVEMU before the analog
gradient can be called complete.
Selecting FM77AV now releases both CPUs through the normal reset path so the
initiator ROM can execute. `make av-boot-test` verifies the reset vector,
initiator execution, both CPU liveness, and the first raster frame. The checked
in 77AVEMU demo disk now passes the four-drive probe, loads its bootstrap into
RAM, reaches the AV PIO sector loader, and produces visible analog-raster
output after the post-load delay (frame 1100 checkpoint). The remaining AV
work is reference-raster comparison and confirming the later demo stages. The
main `$FC80-$FCFF` alias now connects to the sub-CPU `$D380-$D3FF` mailbox,
which the demo uses for its loader stub. The AV `$D431/$D432` encoder protocol
is also wired with directed command/status coverage; host key-to-scan-code
injection remains open. The AV boot-RAM read window previously fell through to
zero-filled RAM and is fixed in `a0d4bd2`.
The `$D430` read path now matches the reference live-status semantics: blanking,
VSYNC, idle-ALU, and the monitor-switch/reset latch are reported independently
of the write-only font/page latch. Focused tests cover the status latch and
clear-on-read behavior. The top-level sub-bus mux also now gives this AV status
read priority over the legacy FM-7 keyboard decode; otherwise the keyboard
alias returned `$00`, leaving the AV monitor in its `$D430` wait loop and the
main CPU stuck polling `$FD05`. The 77AVEMU headless runner now leaves the
reset-time busy latch clear so its disk path reaches the same handshake.
The Verilator video tap now selects the AV 24-bit output, matching the FPGA
top level, so screenshots are useful for raster comparison. With the status-mux
fix, the 2019 demo reaches the same post-loader `$328D` main / `$C020` sub idle
loops as 77AVEMU and clears BUSY at the frame-1100 checkpoint. The raster is
now visible in the sim; its text/bit layout still needs pixel-level comparison
against the reference before the AV video path can be called complete.
The FM77AV shadow-RAM control at `$FD0F` now switches the F-BASIC window between
ROM and RAM, and the MMR-mapped physical `$1C000-$1D37F` sub-system RAM is
dual-ported to the secondary CPU. The core-side address calculation now
preserves the hardware page order (`$C000->$1C000`, `$D000->$1D000`); the old
13-bit subtract-and-truncate expression silently reversed those pages. The
directed `$CA00` command test passes. In the real 2019 AV demo, however, the
startup code leaves MMR segment 0 at C/D=`$0C/$0D` while copying its
`$D40A/$CA00` stub to main physical `$0C000`; the sub CPU consequently does
not see that payload in its fixed physical `$1D000` D page and later executes
garbage. The next AV task is to reproduce this loader/MMR protocol against
77AVEMU and determine which hardware transition or ROM stage should select
the sub-system RAM page; the current trace first diverges when the sub monitor
returns from `$D3C9` to a zero-filled `$D100` target after consuming the
`$D380` mailbox command. Do not add a game-specific alias.
The AV memory regression also covers the exact loader command path: main MMR
segment 0 `$CA00` writes are visible at sub `$CA00` as physical `$1CA00`.

The simulator/reference comparison was rerun from the required `vsim/`
working directory so all ROMs are actually loaded. The mailbox sequence is
hardware-consistent: the sub monitor consumes `Y=$CA05` and then `Y=$CC85`,
matching 77AVEMU's `$D3C9` trace. The frame-346 runaway was traced to a generic
reset-path bug: `$FD13` monitor-bank writes assert the derived sub-reset, but
`SCPU` was wired to global reset and continued executing the old monitor. It
then took the newly selected monitor's `$D2B7` NMI vector as RAM and ran into
zero-filled space. Wiring `SCPU` to `SRESETn` fixes the bank-switch handoff;
the demo now remains in valid sub ROM/RAM through the frame-1100 checkpoint
with the original NMI cadence. No game-specific alias or interrupt workaround
is justified.

`ca75bfe` converted `SRAM.v`'s shared-RAM window from a single-port `ram` to a
`dpram` and, in the rewrite, qualified each side's write with the **other**
side's select. The main CPU writes that window while the sub CPU is halted, so
the sub is never addressing `$d000-$d3ff` at that moment and every main-side
write was discarded: the mailbox was dead and the FM-7 booted to a blank screen
with both CPUs at normal instruction rates. Restoring the two enable
expressions reproduces `e19cde7`'s references exactly. The regression suite had
been reporting this for fifteen commits as `SCREEN+CNT` and it was written off
as timing drift — `docs/REFERENCE.md` trap 18.

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


The suite now has an FM77AV row (`av-demo`, CaptainYS's 2019 demo from
`software/FM77AV/`). It had none before, which is why a broken `$D430` page
select and a missing drawing ALU both survived. Its disk scan also no longer
runs every image in `software/` — with a few hundred there the gate became a
six-hour sweep; use `ALLDISKS=1` or `vsim/sweep/sweep.sh`.

The AV raster is now validated against 77AVEMU by dumping both machines' VRAM
and diffing the twelve 8 KB planes (`docs/TESTING.md`). At the 2019 demo's
title screen every plane matches byte-for-byte except the text lines this core
has not finished typing yet, so the 320-mode plane layout, the scroll
transform, the pixel-code combiner and the analog palette are all confirmed.
Two things were missing and are now implemented: the MB61VH010 drawing ALU's
byte read-modify-write path (`rtl/AVHDRAW.v`, `make avhdraw-test`), and the
main CPU's MMR window onto the sub-system I/O page at physical `$1D400-$1D4FF`.
Only the VRAM half of that aperture existed, so the demo's page-select write
was dropped and the whole gradient collapsed onto the page-0 planes.

Open AV work: the main-CPU MMR path into the sub aperture is implemented for
**writes** only — no software in hand reads `$1D4xx`, and the reference gates
the whole aperture on the sub CPU being halted while this core gates only the
new sub-I/O half (the VRAM half stays ungated, as before). The drawing ALU's
line trigger (`$D42B`) is implemented but no title in hand writes it, so it is
unexercised. Then connect host key events to AV scan codes and add the YM2203
paths behind the same family signal.
Research and reference addresses are in
`docs/FM77AV.md`.
