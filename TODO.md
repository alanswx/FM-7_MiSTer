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
integrated locally. The full simulation regression still passes; the reference
counters moved by the expected startup timing shift, and only the fixed-frame
Thexder title-reveal screenshot changed, so the references were re-blessed.

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
Selecting FM77AV still holds execution in reset until the AV sub-system and
video paths are present.

Next, in hardware order: connect the combiner and analog palette to the AV
12-plane VRAM fetch path, then implement the keyboard encoder and YM2203 paths behind
the same family signal. Research and reference addresses are in
`docs/FM77AV.md`.
