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
Penguin-kun Wars fell out of it. Rebuild the list from
`vsim/sweep/results-P4-19-f1500.tsv` using the exclusion rules in
`docs/TESTING.md` before chasing anything.

CHAN.POP now has two concrete simulator fixes: `t77_decode.v` was starting two
bytes early and decoding each T77 pair as a bit-7 level plus a 15-bit duration;
it also waited for SDRAM after every segment, stretching each level. 77AVEMU
uses the first byte as a `< $40` level and the second byte as the 8-bit duration,
with `7f ff` as low silence. The decoder now prefetches the next segment and
matches the first 24 entries byte-for-byte. A reduced-image run reaches
`Found` and `Loading GAME IPL`; the full-image title run remains to be captured.

Remaining validation:

- **CHAN.POP** — rerun the full load/title path with an emulated-time-aligned
  77AVEMU comparison after the T77 decoder fix.

### Ys

Playable, but only characterised as far as the town map. Nobody has played
further to see what breaks next.

---

## Media support

- **Second drive.** Only drive 0 is served. Many `(Disk 2)` images in the
  collection cannot be reached at all, which caps the sweep.
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

## Not started

**FM77AV** as an OSD option. Hardware research is in `docs/FM77AV.md`; no
implementation work has begun. Worth doing on a confirmed FM-7 interrupt path
rather than an unconfirmed one, so it sits behind the hardware results above.
