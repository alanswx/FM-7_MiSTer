# TODO

Open work only. Fixed items leave this file — the conclusion goes in a code
comment, the journey stays in the commit message. See `CLAUDE.md`.

Reference material: `docs/REFERENCE.md` (read first), `docs/IO_MAP.md`,
`docs/TESTING.md`, `docs/FM77AV.md`.

---

## Start here

**Where it stands.** The **twelve-row** gate is green — `./run_tests.sh` in
`vsim/` compares screenshots *and* counters against `shots-ref/`. FM-7 boots,
Thexder runs, OS-9 reaches its shell. On the FM77AV side **Deep Forest now
matches 77AVEMU on 100.0% of pixels and the 2019 demo on 99.9%**, measured
rather than eyeballed, after correcting a display phase that had the whole
picture sitting three pixels right of where it belonged and finding that the
analog palette had never accepted a write in its life. Ys boots and draws, and
four titles that rendered nothing now render game art (Deep Forest, both Luxsor
disks, Psy-O-Blade).

**Woody Poco's in-game playfield now matches 77AVEMU on 97.3% of pixels**
(93.8% coverage in 39 colours against the reference's 93.7%/39, up from
55.7%/37 and 58.73%). Two faults in the same mechanism: `$D40E`/`$D40F` latched
off the sub CPU's bus, so a title that halts the sub and scrolls through the
MMR aperture had every scroll write dropped; and `$D430` b2, the unmasked
offset, was not implemented, so the offsets that did land were rounded to
32-byte steps. Fixing only the first moves the number to 60.27%. Luxsor disk 2
came with it, 65.8% -> 81.8%, its reference's coverage exactly -- it had been
getting the scroll registers by accident from the ALU aliasing that `c2fc867`
removed.

**It fits and closes timing.** 23,293 / 41,910 ALMs (56%), 516 / 553 M10K
(93%), positive slack in all five corners, `output_files/FM-7_MiSTer.rbf` built
with `tools/quartus-build.sh all`. **37 M10K blocks is the whole remaining
budget** — price any new feature against that, from the map report's RAM
summary and never in bits (see the FPGA fit section).

**The sound is one chip now.** `jt03` (jotego/jt12) serves both the FM-7's PSG
and the FM77AV's YM2203, so `$FD15`/`$FD16` are decoded and the joysticks sit on
the chip's real I/O ports. **The combined work ships as GPLv3** — see
`Readme.md`. That is a one-way door and it is already through.

**The FM-7 disk collection is fully swept.** 395 of 395 distinct disks, ten
cohorts, each screened for machine and scored against a frame-matched 77AVEMU
render. Seven core bugs in the whole collection, six fixed. **The FM77AV set has
no blank-screen bugs left** — 30 of 68 MATCH, 0 CORE-BLANK, 0 CORE-WORSE, the
rest blank on the reference too.

**The gating risk is now hardware, not software.** Synthesis is current and the
design fits with timing closed, but **none of the last 151+ commits has been RUN
on a DE10-Nano**. Sim proves "behaviour unchanged"; only hardware proves the
glitch-domain classes, and this project has one live example already — the
joystick works in simulation and is dead on the board.

**Open, in priority order:**

0. **Cassettes: finish the long run and record the answer.** *(This item used to
   read "Cassette loading does not work, for any tape, and there is no reference
   to diff against." Both halves were wrong — see `docs/CONTINUATION.md`.)*

   The reference **can** drive tapes; `tools/77avemu_headless.cpp` never bound
   the data recorder's `Outside_World`, so every reference tape run died of
   SIGSEGV the moment the motor turned. One line. With it fixed the reference
   reaches `Found: Fighter` at 60,000,000 steps.

   And the loads were never failing here so much as never finishing: **a tape
   load is minutes of machine time, not the ~20 s a disk title needs**, and
   every tape default in this harness is sized for disks. At 8M steps the
   reference shows exactly the `Searching` state that every previous
   investigation recorded as failure. On this core a 3700-frame run is nowhere
   near: motor on 87.8% of it, 162,019 cassette-bit edges, 37% of the image
   consumed — all healthy, just unfinished.

   **What is actually open is one measurement**: run this core long enough on
   Fighter to reach `Found:` or to prove it cannot. Budget many thousands of
   frames. Until that lands, "do tapes work" is unanswered rather than answered
   no.

   Separately and still open: **Crash Ball reports `Device I/O Error` after
   `Found: CRB`** on hardware and in simulation, while the reference loads and
   plays the same image (74.0% coverage). The header block is found, so it is a
   data-block checksum or framing case, not sync. See `HARDWARE-HANDOFF.md`.

0. ~~The FM-7 half has never been compared to a reference.~~ **DONE — the
   cohort campaign is complete, 395/395 distinct disks (100%), 2026-09-03.**

   Every disk in the collection has been screened for machine, swept on the one
   it belongs to, and scored against a 77AVEMU render at the matched instant.
   Ten cohorts. `docs/HANDOFF.md` carries the per-cohort table and
   `sweep/cohort-results/` the data.

   **Seven core bugs in 395 disks, six fixed.** Cohorts 08, 09 and 10 found none
   at all. The one still open is Xanadu Scenario II disk D, two of whose three
   faults are fixed (`338e936`, `40728f1`).

   The old "153 blank" figure it used to quote was an upper bound with no
   reference behind it, and the campaign is what replaced it: most blanks are
   blank on the reference too — data disks, save disks, `[b]` dumps and images
   whose boot sector halts.

   What is left of the campaign is `cohort.py all <outdir>`, the validation pass
   that confirms nothing regressed across the ten cohorts. It is not where bugs
   are expected; every disk has already been through one.

### Marchen Veil [b]: an over-declared sector count breaks the D77 scan

**Diagnosed, not fixed.** The title uses a standard FM-7 copy protection: two
tracks -- 5/side 0 and 32/side 1 -- declare **`nsec=256`** in the .d77 track
header while physically holding 10 sectors, and the sector order is shuffled so
sector 1 is *last* (`5/0/2 5/0/3 ... 5/0/10 5/0/1`). Every other track is a
plain `nsec=10` in order.

The scanner walks the declared count, so on those two tracks it consumes 256
sector headers of which ~246 are garbage and the table loses sync. Measured:
the image's declared sectors sum to **1320** and `D77SCAN` builds **810**, so
`5/0/1` is never indexed. The read then fails with **RECORD NOT FOUND** --
status `$10`, 12156 times in a 700-frame run, a value the reference never
returns once. `WDNOMATCH want trk=5 side=0 sec=1 (wdreg_track=5 ...)` confirms
the search exhausts the table with the track register *correct*.

Second, independent problem on the same data: `sectors_per_track` is
`reg [7:0]` (wd1793.sv:98), so a declared 256 truncates to **0**, and the guard
at wd1793.sv:478 (`wdreg_sector > sectors_per_track`) then rejects every sector
number on that track.

Note what this is NOT, because both were checked and ruled out: not the
ID-cylinder-vs-track-register disagreement (`wdreg_track` equals `disk_track`
equals 5 at the failure), and not head movement -- this core and the reference
issue *identical* type I commands, 5 x RESTORE, 7 x SEEK, 1 x SEEK+verify.

A fix has to bound the per-track scan by the track's actual extent rather than
trusting the header count, and widen or saturate `sectors_per_track`. Check it
against Daisenryaku, whose page-zero path is sensitive to the same search
(FDC.v's ID-cylinder note), and against the two titles above.

### The Xanadu family draws nothing, and never has

Cohort 02's four real findings, each confirmed by looking at the picture:
**Xanadu (Disk A)**, **XANADU.D77**, **Xanadu Scenario II (Disk D)** and
**Marchen Veil [b]**. All four render a full title screen on 77AVEMU and a
black screen here. (The cohort's fifth CORE-BLANK row, Return of Ishtar, is
the same noise screen as cohort 01's Ishtar -- not a bug.)

**Not a regression.** All four were blank in the Aug-8 sweep too
(`results-P4-19-f1500.tsv`, `png=3790`). The main-CPU rate has changed since
(6698 -> 11017 per frame on Disk A) but the screen was always black.

**Not a wedge, and not the display path.** On Xanadu Disk A both CPUs run at
healthy rates (11102 main / 8810 sub per frame) with 15.2M `$fdxx` cycles
across 4200 frames, and every sampled frame from 400 to 4000 is the blank
3790-byte PNG while the reference has the title up by frame 400. At the
matched frame the reference holds **33108 non-zero VRAM bytes and this core
holds ZERO** -- so nothing is ever drawn, and the palette, display enable and
raster are all eliminated. The fault is upstream of VRAM.

The lead worth following: on all three Xanadu disks the reference's **sub CPU
executes at `$d39d-$d3a5`**, inside the shared RAM window `$d380-$d3ff`. The
main CPU downloads a routine into shared RAM and the sub runs it from there,
so this is a main/sub handoff, not a drawing bug. Marchen Veil's sub instead
runs at `$c023-$c02d`, so it may be a different fault that happens to end in
the same black screen.

Measuring this needs `FM7_VRAM_DUMP`, which until `847df20` was gated
AV-only and silently wrote no file for FM-7 titles; note also that
`--av-dump-frame` defaults to 870, so a shorter run writes nothing either.

   When everything is retired, `cohort.py all` writes one list of every
   distinct disk for a final validation pass. That pass confirms nothing
   regressed across the cohorts; it is not where bugs are expected, since each
   disk will already have been through one.

   Run it with `ref-shots-at-frame.sh` so both sides sample the same
   instant -- `reference_frame = round(vsim_frame * 1.00608)`, and note the
   sweep's safe-name rule is `tr -c 'A-Za-z0-9._-' '_'` (it KEEPS `-`); a
   different rule silently produces NO-SHOT rows rather than an error.

0. **Frame-matched references exist; the blessed set is still step-matched.**
   Every blessed reference in `sweep/renders/ref-shots/` is captured at a fixed
   20,000,000 reference steps (~22 s) while the core samples at a fixed frame
   (2000 = 33 s). Those are different moments, which did not matter while
   nothing scrolled and matters a great deal after `c50a852`. Dragon Buster
   read as the sweep's worst regression, 74.90% -> 65.98%, and is in fact a
   **32-point improvement**: against a reference rendered at 22M steps it goes
   65.45% -> 97.70%. Sampling our own render across frames 1800-2300 moves the
   score 57.94% -> 73.76% with no RTL change at all.

   `sweep/ref-shots-at-frame.sh` now renders the reference at the *same instant*
   the core samples — `reference_frame = round(vsim_frame * 1.00608)`, the
   60 x 1024 x 262 / 16e6 ratio — and the AV sweep has been re-scored through it
   (`results-av-f2000-shared-window.tsv`). What remains is the FM-7 half, which
   has never been compared to a reference at all, and re-blessing
   `sweep/renders/ref-shots/` off the fixed 20,000,000-step capture.

   Do not re-bless Dragon Buster to 22M to make the number look right — that is
   how `shots-ref/` rotted. Options worth thinking about: capture references at
   several step counts and score against the best match; or drive scrolling
   titles to a deterministic state the way the Woody Poco comparison does with
   `--joystick`, which is what made that title scoreable at all. Until then,
   treat any agreement delta on a moving-camera title as uninterpretable, and
   check coverage and colour count instead — if those are unchanged and only
   agreement moved, the picture shifted rather than broke.

0. **World Golf II disk 1 now renders here and NOT on 77AVEMU.** Its title screen
   — kana logo, golfer, mountains — appears at 42.4% coverage in 8 colours since
   `c2fc867`, where the reference draws a black screen. Nobody has checked which
   machine is right. Worth an hour: if this core is correct it is the first AV
   title where the reference is the one that fails, and `refs/local`'s renders
   stop being a safe target for the whole blank half of the set.

1. **Synthesis is current again as of `ec2a1ab`; hardware TESTING is not.**
   Built on `alans@cottageubuntu` (Quartus 17.0.2 Lite): full compilation
   successful, **0 errors**, 676 warnings, `output_files/FM-7_MiSTer.rbf`
   4,045,756 B. 23,651 / 41,910 ALMs (56%), **516 / 553 M10K (93%) -- the
   37-block headroom has not moved**, 4,097,480 / 5,662,720 memory bits (72%),
   145 / 314 pins. No negative slack anywhere in the STA report. The two
   Critical Warnings are benign and expected (127005: the AV boot loader is
   480 bytes in a 512-deep memory; `AVMEM.v:435` guards `boot_offset < 480`).

   So "it does not build" is no longer a risk. What is still outstanding is
   that **none of these 151 commits has been RUN on hardware** --
   `HARDWARE-HANDOFF.md` has the list ordered by risk. `b8ff6ac` is the one to
   watch: it changes power-on behaviour for every machine, FM-7 included.

   (Superseded: this item used to read "A hardware build is 41 commits overdue,
   five of them RTL. Nothing since
   `6356000` has ever been synthesized." Both halves were stale: the count was
   151 commits / 20 RTL files, and it has now been synthesized.)

   (The pitch and joystick tests that used to head this list were both settled
   on hardware in `bb10370` — PSG tone 234.5 Hz vs 234.65 predicted, keep
   `378fee6`; joystick works from both pads, the dead pad was MiSTer player
   assignment. Neither is a core defect.)
2. **The gate lost an AV row's worth of coverage, and a second row is now
   sampled mid-animation.** Both are the same defect: `SHOT_AT` is one global
   frame (`FRAMES - 20` = 600) and two of the three AV titles have nothing
   worth photographing there.

   * `av-kohakuiro`'s reference was a picture of the dead palette; the corrected
     render is a black screen. It is **not** blank because the core fails to
     draw it — this core paints the RIVERHILL SOFT logo at frame **199** and
     fades it out by 400, which is exactly what 77AVEMU does at its own frames
     200 and 400, and the reference is then black from 600 through 2400. The
     gate simply photographs it 400 frames after the only thing it draws.
     Shooting that row near frame 200 would restore the coverage without
     changing the title.
   * `av-wizardry4` is an attract *animation* — four portraits, then a
     three-portrait "DISPELL" stage, then more — and after `6a7030e` made
     everything 1.65x faster, frame 600 lands on a transition with no sprites
     at all. Today's core at frame **400** reproduces the previous blessed shot
     **byte for byte**, and at 800 it is on the same three-portrait stage
     77AVEMU is on at its 800, so the two are in step; the picture moved, it did
     not break (trap 16). The blessed shot is nonetheless mid-draw, which
     `run_tests.sh`'s own comment says a gate row must not be.

   The fix for both is a per-row shot frame rather than one `SHOT_AT`.

   Separately, and older than either: on this title the core's **title text is
   overprinted** ("THE RETURN OF WERDNA" doubled on itself) and the
   `S) ゲームをはじめる` line of the bottom box is missing, where 77AVEMU draws
   both cleanly. That is visible in the *previous* blessed shot too, so it is
   long-standing, not new — see `vsim/shots-ref-77avemu/av-wizardry4.png`.
3. ~~AV titles that render nothing.~~ **None left.** All six of the original
   set are fixed: the TWR, encoder-RTC, CRT-latch and shared-window faults
   earlier; Luxsor disk 1 by `2ea9fc0` (NMI recognition); Little Box disk A and
   In the Dream disk A by `6f2817e` (the MMR deciding ROM against RAM). A full
   68-title sweep before and after that last commit moved exactly those two
   rows and regressed nothing — **30 MATCH, 0 CORE-BLANK, 0 CORE-WORSE**.
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

(`378fee6` and `71c00e6` were settled on hardware in `bb10370`: the controlled
tone measured 234.5 Hz against this side's predicted 234.65, so the PSG commit
stays; and the joystick works from both pads -- the dead pad was MiSTer player
assignment, not the core.)

| commit | what | why only hardware |
|---|---|---|
| `648efbd` | YM2203 interrupt delivered, `EXTIRQ` driven | changes interrupt delivery on every AV title |
| `6356000` | every AV write no longer clobbers the FM-7 page | changes AV memory behaviour wholesale; an FPGA build older than this will not match anything reported here |
| `bad101e` | sub I/O aperture halt gate un-inverted | as above |
| `1706f9c` | the drawing ALU now triggers on a main-CPU VRAM **read** | fires the ALU on a bus cycle that previously did nothing; the read strobe is `~RDQEn`, one of the timing-sensitive decodes |
| `2fdaa08` | `$fd93` bit 0 reports the boot-RAM latch | changes what boot RAM does on every machine |
| `aa6e701` | VRAM aperture gated on the sub CPU being halted | closes a path that was open; blocks nothing measurable in sim, so only hardware can show a title that relied on it |
| `c2fc867` | sub I/O decoder no longer aliases over `$D410-$D4FF`/`$D500-$D7FF` | touches **every** sub-CPU I/O access on the AV, and the outputs it gates are side effects (CRT on/off, attention FIRQ), not just a read mux |

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

### Why all eleven references were re-blessed (the CPU clock fix)

**Blessed at `d09fe5d`, before the sub-CPU VRAM arbitration rework.** That
change (`MB60H010.v` `SCASSEL` cycle-steal, with `SUBCRTADDR.v`, `AVHDRAW.v`,
`CRTRAM.v`, `FDC.v`) speeds the sub CPU up on every machine and will move these
counters again; this bless is the baseline it is measured against, and the two
must not be confused for one another.

`shots-ref/` was last blessed at `b6292e8` and the tree moved 45 commits after
it. The one that matters is **`6a7030e`**, which put the CPU clock mux legs the
right way round: the main CPU had been on the FM-8 leg at 4.8 MHz while the sub
ran at 8 MHz, a state no real machine can be in. Everything now runs about
**1.65x faster**, so every liveness counter moved and every fixed-frame
screenshot lands somewhere else in each title's startup. `c88c1db`
(`$FD00` b0), `f03d333` (CE_PIXEL is one pulse per pixel), `d8e5329` (the FDC
INDEX pulse free-runs) and `3546ea4`/`32e04b6` (an absent drive takes as long to
answer as a real one) contribute the rest.

| row | main/frame | sub/frame | I/O cycles | screenshot |
|---|---|---|---|---|
| `boot-basic` | 5555 → **9165** | 9682 → 9517 | 1511195 → 2163395 | cursor blink phase only |
| `boot-dos1` | 6566 → **11038** | 8709 = | 65535 = | unchanged |
| `boot-dos2` | 6157 → **10094** | 8709 = | 204899 → 209839 | unchanged |
| `boot-dos3` | 6707 → **11179** | 8709 = | 0 = | unchanged |
| `basic-print` | 5552 → **9162** | 9609 → 9444 | 1506685 → 2158884 | unchanged |
| `basic-keys` | 5552 → **9163** | 9592 → 9429 | 1507663 → 2159863 | unchanged |
| `basic-shift` | 5550 → **9160** | 9520 → 9360 | 1503131 → 2155331 | unchanged |
| `disk-Thexder [b]` | 4745 → **8523** | 6317 → 6744 | 601414 → 986091 | same title screen, animation moved |
| `av-demo` | 5044 → **8463** | 5918 → 6376 | 507617 → 798307 | same colour grid, banner further along |
| `av-kohakuiro` | 5309 → **9055** | 7195 → 7462 | 924729 → 1678717 | unchanged — blank, see item 2 above |
| `av-wizardry4` | 4288 → **6975** | 8038 → 7946 | 532204 → 994045 | mid-animation, see item 2 above |

9165/5555 = 1.650, which is the speed-up `6a7030e` measured end to end. Only
**four** screenshots changed at all; the seven FM-7 text rows are the same
pictures, which is the evidence that a 1.65x clock change moved timing and not
rendering. The one screenshot that changed *in kind* is `av-wizardry4`, and it
is not a regression: today's core at frame 400 reproduces the old blessed shot
byte for byte.

Two bugs in the harness itself were in the way and are fixed in the same commit:

* **`run_tests.sh` found zero disk images in a git worktree.** `find "$DISKDIR"`
  without a trailing slash does not descend into a symlink, and `software/` is a
  real directory in the main checkout and a symlink in a worktree. Every disk row
  silently vanished from the run and `BLESS=1` left its reference untouched —
  a gate quietly not gating, which is trap 17 and trap 15 at once.
* **A `pkill -f Vemu` from another shell in the same checkout SIGTERMs the
  runs**, and a killed row reports `MAIN-STALLED SUB-STALLED NO-SCREENSHOT` with
  `?` counters — indistinguishable from a core that cannot boot an AV disk, and
  `BLESS=1` would have written `0 0 0` into `counters.tsv` for it. `EXE=` is now
  overridable so a run can be given a name nothing else matches.

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

### Three titles blocked together, and `$FD00` b0 is NOT the blocker

Shounen Mike (ref 99.9% coverage in 200 colours, 0.1% here), FM Sound Editor
(69.8%, 0.0%) and Pro Yakyuu Fan disk A (40.2%, 0.0%) are all blank or nearly
blank, and **all three diverge from 77AVEMU at the same instruction**: `R $FD00`
at pc=$51CB on frame 6-10, in the boot ROM's four-drive probe, after ~20600
accesses that match port, value AND PC exactly.

That made `$FD00` b0 look like one blocker gating three titles. **It is not.**
Built with b0 = 1 (the documented value -- see the clock section in
docs/FM77AV.md) and re-rendered all three: every one is unchanged, to the
decimal, at every sampled frame.

    Shounen Mike     0.10% -> 0.10%
    FM Sound Editor 30.17% -> 30.17%
    Pro Yakyuu Fan  59.80% -> 59.80%

So b0 is the first difference they NOTICE, not the one that stops them. Worth
knowing before more effort goes into the b0/Luxsor standoff: it is one title
(Luxsor, which blanks when b0 is set) against three, and fixing it buys none of
the three.

**What b0 = 1 does buy is reach.** It moves each title's first divergence a long
way down, which is how the two leads below were found at all. Both were invisible
underneath the $FD00 difference.

**Lead 1 -- Shounen Mike, `$FD05` bit 7 (SUBUNAVAIL).** With b0 = 1 the first
divergence moves from access #20614 on frame 10 to **#29912 on frame 86**:

    ours       R $FD05 7E pc=$1273
    reference  R $FD05 FE pc=$1273 x45292

Bit 7 is the sub-CPU-unavailable flag (`TIMER.v`, `{ SUBUNAVAIL, 6'b111111,
EXTDETn }`). This core reports the sub AVAILABLE; the reference reports it BUSY
and spins there 45292 times before continuing. Ours then writes `$FD05 80` at
pc=$1279 -- halting the sub -- while the reference is still waiting. That is a
handshake this core is winning when it should be losing.

**Lead 2 -- FM Sound Editor and Pro Yakyuu Fan, `$FD1D` at pc=$FEF0.** Both land
on `R $FD1D` reading `$BC` here against `$80` there, in the boot ROM. Tested
behaviourally: building with 77AVEMU's form (bits 5:2 cleared) changes NEITHER
title, so matching the reference there is not the fix. See the FDC register
section in docs/FM77AV.md -- the Fujitsu manuals define b0/b1, b6 and b7 only,
both references agree on all of those, and they differ only on undefined bits
where CSP's "reads 1" matches the FM-7 bus convention this project has confirmed
four times over. **Not a lead; do not chase it.**

**Eliminated for Shounen Mike, do not re-check:** the ALU's main-CPU read
trigger (its sub CPU is not halted), `$FD37`'s access mask (never written), fine
scroll and the scroll-register aperture routing (it never writes `$D40E`/`$D40F`),
and the drawing ALU itself (it fires with correct data).

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

### The CPU clocks are wrong, and the two must move together

**Settled from the primary sources** -- see the new clock section in
docs/FM77AV.md for the quotations. FM-7 System Specifications page 38: both CPUs
run at **8 MHz** normally, the FM-8 compatibility setting moves **both** (main to
4.9 MHz, sub to 4 MHz), and they **cannot be switched independently**. Page 22
labels `$FD00` b0 as `0:1.2M / 1:2M`. FM-Techknow page 334: on the AV, enabling
MMR drops the main CPU from **2 MHz to 1.6 MHz**, "processing speed reliably 20%
UP" with MMR off -- and 1.6/2.0 = 0.8 exactly.

**This core is in a state no real machine can be in.** `MCPUCLK = switch ?
CLK4_9 : SCLK1` with SW2 tied high puts the main CPU on the FM-8 leg (4.8 MHz)
while `SCPUCLK = SCLK1` keeps the sub on the FM-7 leg (8 MHz).

That explains the two failed attempts (trap 45): raising the main clock alone to
2.016 or 1.714 MHz breaks the FM77AV demo, because it changes the main:sub
*ratio*, and CLKCTRL's own comment already records that ratio being load-bearing
-- Thexder dropped roughly every other byte across the shared window when the sub
was slowed to 4 MHz. That fix was right in direction and wrong in kind.

**What to try, in this order:**

1. Move main AND sub to 8 MHz together (E = 2.016 both). This is the documented
   normal FM-7 configuration and the only one the manual allows alongside a sub
   at 8 MHz.
2. Add the AV's MMR-conditional drop to ~1.6 MHz. The demo disk toggles MMR --
   traced, `$FD93` written with b7 both set and clear -- so it exercises this.
3. Only then revisit `$FD00` b0, which is a CPU-speed bit and currently reports
   this core's real (wrong) 1.2 MHz honestly. Fixing it alone blanks Luxsor disk
   2 (trap 53).

**Why the demo is the test to watch.** FM-Techknow page 318 describes that exact
disk: its closing 4096-colour palette section watches `$FD12` b1 for the
display-timing edge and writes palette entries inside the 23.84 us horizontal
blanking window, disabling MMR and halting the sub CPU to go fast enough. It
exercises the MMR clock, the main:sub ratio and the blanking window at once. The
window itself is already correct here (384 of 1024 pixels = 23.8 us).
### Undriven read bits return 0 where hardware returns 1

Found by diffing the read streams against 77AVEMU over the same frames. Bits
that no device drives should read as 1 -- which `core.v:622` already says for
the sub I/O page ("Everything else returns $FF") but several registers do not
honour:

| port | reference | here | what it is |
|---|---|---|---|
| `$FD16` | `$7C`/`$7D` | `$00`/`$01`/`$80`/`$81` | YM2203 status; read 254175 times pre-divergence |
| `$FD00` | `$7F` | `$00` | keyboard/switch; bit 7 agrees, the rest do not |
| `$FD1D` | `$80` | `$BC` | |
| `$D432` | `$FE`/`$FF` | `$81` | AV keyboard encoder status (`AVKEYBOARD.v:37` builds `{~data_valid, 6'd0, ack}`) |

`$D432` also differs in bit 0: this core reports ACK immediately (8 reads
against the reference's 74), so the handshake completes but not the way the
hardware does it.

**These are tolerated by Woody Poco** -- they read identically in the window
where the drawing streams match exactly, so they are not that title's fault.
Fix them as accuracy work, and re-gate: changing a status bit a title polls
254175 times is not a safe no-op.

Two members of this family are now fixed and are worth reading before doing the
rest, because both had a trap in them (`794d016`). `$FD01` was a declaration
initialiser, not the idle branch that looked like the culprit -- an `always @*`
block does not re-run until its sensitivity list moves, so patching the branch
changed nothing. `$FD04` b2 was the one case where the references did NOT
disagree once the Fujitsu system manual was read properly: all four say bits
7..2 are unused, and only this core put sub-BUSY there.

### Open FM77AV implementation gaps

- The main-CPU MMR path into the sub aperture is implemented for **writes**
  only. No software in hand reads `$1D4xx`, and the reference gates the whole
  aperture on the sub CPU being halted. This core now gates **both** halves --
  `vram_sel = vram_addr_sel && sub_open` -- and a measured run blocks zero
  writes, i.e. no title in hand writes the aperture while the sub runs.
  (Superseded claim: "the VRAM half stays ungated" -- it was gated in `08062cd`
  / `971c8df`, the fix that made Mahjong render.)
- The drawing ALU's line trigger (`$D42B`) **is** exercised: Mahjong writes it
  485 times in a 2000-frame run, and that title now matches the reference's VRAM
  byte-for-byte (98,304/98,304). (Superseded claim: "no title in hand writes
  it, so it is unexercised.")
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
