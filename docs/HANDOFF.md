# Start here

Orientation for picking this branch up cold. Detail lives in
`docs/CONTINUATION.md` (open work, per-title), `docs/REFERENCE.md` (measurement
traps — read section 5 before trusting any number) and `HARDWARE-HANDOFF.md`
(the FPGA side). `CLAUDE.md` has the documentation rules; follow them.

Branch `fdc-d77-support`, pushed to `alanswx`. Working tree clean, gate green.

## If file reads intermittently fail with EPERM

While this session ran, the repo lived under `~/Documents`, which macOS
protects: reads of files in the tree returned `Operation not permitted`
intermittently, while `ls` and `pwd` kept working. It spoiled four gate runs
before being recognised.

The symptom to know, because it does NOT look like a tooling problem
(trap 71): `run_tests.sh` reports **REGRESSION** with several rows at an
identical `5589` main / `882` I/O and `RUNAWAY-INTO-IO`, plus
`awk: can't open file shots-ref/counters.tsv`. vsim loads its ROMs with
`$readmem` on relative paths and a failed load is a *warning*, so the machine
runs away into `$fdxx` and still prints plausible counters.

**Identical counters across unrelated tests is the tell** — `basic-print` and
`basic-keys` do not touch the FDC and cannot fail the same way as `boot-dos3`
by coincidence. Re-run from a verified directory before believing any
regression. If the repo has since been moved out of `~/Documents`, this should
be gone.

Related and self-inflicted: do not run anything alongside the gate. Three runs
were invalidated that way, one of them by `scp`-ing a disk image the gate was
actively reading.

## Read this first: the sweep used to corrupt the disk collection

`sim/sim_blkdevice.cpp` opened every mounted `.d77` **read-write** and wrote
sectors back to it. Any title that legitimately saves to disk therefore
modified the user's image, permanently and silently, and `software/` is
gitignored so there was no version history to notice it against.

Two disks were damaged during cohort 02, both at 2026-08-27 17:40:08:
`FM Sound Editor V1.0 (1985)(Fujitsu)(JP).d77` and
`F-BASIC V3.3L11 System Disk (1985)(Fujitsu)(JP).d77`. **Both have been
restored** from the MiSTer at `192.168.1.75`
(`/media/fat/games/fm-7/D77/`) and hash-verified against the pre-damage
values recorded in `sweep/cohorts/02-images.retired`.

Writes are now opt-in behind `--disk-writable`. The core is still told the
disk is writable and the write still costs the same cycles, so emulated
behaviour is unchanged; only the `put()` to the file is skipped.

**How it was found, because the lesson generalises.** `cohort.py status`
reported 78 disks covered after two 40-disk cohorts. Chasing that two-disk
discrepancy found the corruption: cohorts identify a disk by content hash, so
a modified image stops being recognised. The bookkeeping built for coverage
turned out to be the audit trail — it recorded what each file hashed to
*before* the sweep ran, which is what made both the diagnosis and the verified
restore possible.

If you ever see coverage arithmetic that does not add up, chase it. It is
cheap and it was hiding real data loss.

## State in one screen

Against 77AVEMU over the 68-image FM77AV set, **both sides scored at the same
machine-time instant** — core frame 1980, reference frame 1992 — using
`sweep/ref-shots-at-frame.sh`. *(Superseded: earlier tables here, including the
one this replaces, were scored against `ref-sweep.sh` output, which renders by
INSTRUCTION COUNT. That is a different moment in a title, exactly as
`ref-sweep.sh`'s own header warns, and it inflated the actionable list — see
trap 67.)*

Both columns re-scored on the frame-matched basis, so they are comparable:

| verdict | `sweep/renders/` | prev | **re-measured 2026-08-30** |
|---|---|---|---|
| CORE-BLANK — reference draws, this core does not | 12 | 5 | **3** |
| CORE-WORSE | 2 | 0 | **0** |
| TEXT-ONLY | 8 | 8 | **8** |
| BOTH-BLANK — neither draws; mostly data/scenario disks | 27 | 27 | **29** |
| MATCH | 18 | 27 | **27** |
| REF-WORSE — this core draws and the reference does not | 1 | 1 | **1** |

**The right-hand column is measured, not inherited.** All 68 re-swept on
`fm77av` with four-frame sampling against the frame-matched references in
`sweep/renders-postfix/ref-shots`; every image hash-verified unchanged.

**The honest read: this session's three fixes moved this set not at all.**
MATCH is 27 before and after. The scan bound, the `$D400` padding and the timer
were all real and verified, but their payoff was on the FM-7 side and in the
multi-disk containers. CORE-BLANK narrowing 5 -> 3 is the two trap-49 artifacts
resolving, not a gain. The remaining three ARE the actionable list below.

**`sweep/renders/` is two sessions old**, so that delta is not this session
alone; it carries the previous session's NMI-mask and sector-register fixes as
well. The three titles verified individually as gained *this* session are FM
Sound Editor, Daiva Story 2 disk A and Mahjong Kyou Jidai disk 1 — the last
matching 77AVEMU on **all 98,304 VRAM bytes**.

Actionable list, frame-matched, worst first:

**THREE titles, not five.** Every row was checked against its own four sampled
frames before being believed:

| ours | ref | title |
|---|---|---|
| 0.0 | 27.1 | Luxsor disk 1 — blank at all four samples. Runaway into `$fdxx`, IRQ asserted never taken. |
| 0.1 | 9.6 | Little Box disk A — blank at all four. Main CPU at 816 instr/frame against a healthy ~7400. |
| 0.0 | 9.6 | In the Dream disk A — blank at all four. Sub 65% halted, BUSY stuck at 1. |

**Cleared as trap 49 — do NOT re-open without checking the other sampled frames
first.** Four of the seven rows the sweep called actionable were the attract
sequence photographed at a different moment:

| title | why it is not a bug |
|---|---|
| Ys II Program disk | our frame 1100 is the same title screen the reference shows at 1992 — stone relief, logo, "ANCIENT YS VANISHED THE FINAL CHAPTER". The reference itself swings 151 KB → 8.9 KB → 8.9 KB → 98 KB across the same span. |
| How Many Robot disk 0 | our frame 1100 *is* the reference's title screen, pixel for pixel |
| Gambler Jikochuushinha | at the matched frame the reference shows the same border and portrait as ours; the real gap is missing **text**, not the title illustration |
| Wizardry IV disk A | samples 12222/10635/10411/7143 bytes — renders throughout; the gate passes it byte-identically at frame 600 |

## The FM-7 half: cohort sweeping, and what it has found

The AV set above is 68 images. The **FM-7 half is 395 distinct disks** and had
never been compared to a reference at all until this session. It is being
covered in **retirable cohorts of 40** — see `docs/TESTING.md` for the method
and `sweep/cohort.py` for the tooling.

    python3 cohort.py status            # coverage
    python3 cohort.py next --size 40    # draw the next cohort
    python3 cohort.py retire NN <dir>   # only if OUR side rendered all 40

**Coverage: 160/395 (40.5%).** Cohorts 01-04 retired.

| cohort | result |
|---|---|
| 01 | **0 core bugs in 40 disks.** All 12 blanks were blank on the reference too |
| 02 | **4 real bugs**, 3 fixed. 15 MATCH, 14 BOTH-BLANK, 5 TEXT-ONLY, 1 REF-WORSE |
| 04 | **0 core bugs in 40 disks**, and the first cohort run with machine screening AND four-frame sampling. 23 MATCH, 9 BOTH-BLANK, 7 TEXT-ONLY. Both flagged rows were caught by the new steps, not by hindsight — see below |
| 03 | **1 real bug, fixed** — Ys Omen `[a]`, visible only on the AV, root-caused to the D77 scan bound (`9b9af08`) and now byte-identical to 77AVEMU on all 98,304 VRAM bytes. 12 MATCH, 15 BOTH-BLANK, 11 TEXT-ONLY. Both rows the scorer called actionable meant something other than their verdict — see below |

So the rate is roughly **5 real bugs per 120 disks**, and the old
"153 blank of 350" figure from 2026-08-08 says very little — most blanks are
blank on the reference too, and several apparent findings were scoring
artifacts (trap 70).

### The three FDC fixes cohort 02 produced

**Force Interrupt on an IDLE controller never raised INTRQ** (`0db06c8`). Every
command write clears `s_intrq` and only `STATE_ENDCOMMAND` sets it; the busy
path reached it via `STATE_ABORT`, the idle path just cleared error bits and
stopped. Xanadu writes `$D8` to an idle FDC and polls `$FD1F` b6 — this core
answered `$3F` 2,159,554 times. Fixed Xanadu Disk A and Xanadu Scenario II.

**Multi-disk `.d77` containers were never parsed** (`6f1512d`). Identification
required the header's size field to equal the file size *exactly*, which a
container never satisfies; and `img_size` is `[19:0]`, a 1 MB ceiling, so a
2.4 MB container truncated to 397,888 and no comparison could match. **28
images in the collection are containers and 16 distinct images are over 1 MB.**
(Corrected: the earlier figure of 19 counted duplicate paths; deduplicated by
content, as `cohort.py` counts, it is 16.) Fixed
XANADU.D77. The same commit applies the `.d77` write-protect byte, correcting
two wrong claims in `FDC.v` — 77AVEMU *does* read it (`d77.h:1034`) and it does
*not* break Thexder.

**A lying sector count broke the track scan** (`348aaa0`). Marchen Veil's
tracks 5/side 0 and 32/side 1 declare `nsec=256` while holding ten sectors,
shuffled so sector 1 is last. The count was taken as its low byte, so 256
became 0. A track now ends where the next present track begins, and the count
is capped at 32.

### Marchen Veil is a PARTIAL fix

It boots and draws its SACOM / ALU corp. splash instead of a blank screen, and
the scan is provably correct — 828 sectors, exactly the true count. But it
**stalls at that splash through frame 1980**, where the reference is at its
title screen (40,942 bytes). The disk is being read correctly now; whatever
stops it next is a separate, undiagnosed fault.

### What cohort 03 got wrong, in both directions

Neither row `compare-ref.py` flagged meant what the verdict column said, and
they were wrong in **opposite** directions. Trap 70's own test — render the
reference at several frames and check the PNG size actually changes — settled
both in about ten minutes. Run it before triaging anything.

| row | verdict | what it actually is |
|---|---|---|
| Ys - Ancient Ys Vanished Omen `[a]` | CORE-BLANK | **A real bug, now FIXED (`9b9af08`).** An AV title in the FM-7 set, so as an FM-7 the reference rendered *noise* and both halves of the comparison were junk. Run as `av`, the reference drew its title and this core was blank. Root cause was the D77 scan bound, not video at all. See trap 72 for the disk-set half. |
| Penguin-kun Wars (demo) | CORE-WORSE | **Not a bug.** We draw the title correctly at frame 900, then advance to "1 PLAYER GAME? / PUSH RETURN KEY" by 1000 and wait for input. The reference never leaves the title: byte-identical 83,621 B at frames 2500/3200/4000/5000. We were marked down for reaching a *later* state. |

### The 16 images over 1 MB, re-tested after the scan-bound fix

All 16 swept on **both** machines, before and after, with the "before" built
from `d2840ab` in a worktree in the same session (trap 57). Frame-matched, and
every image hash-verified unchanged either side.

**Four titles moved from blank to rendering.** Two were confirmed byte-identical
to 77AVEMU on all 98,304 VRAM bytes — `[a]` and the plain image are different
files, so this is two independent confirmations, not one measured twice:

| title | machine | before | after | confirmation |
|---|---|---|---|---|
| Ys - Ancient Ys Vanished Omen | fm7 + av | 3,790 | 35,924 | **0 differing VRAM bytes** |
| Ys - Ancient Ys Vanished Omen `[a]` | fm7 + av | 3,790 | 35,924 | **0 differing VRAM bytes** |
| Ys (1985)(PSG) | fm7 + av | 3,790 | 35,924 | 32.2% against 32.1% |
| Reviver | fm7 | 5,492 | 18,374 | 17.8% against 8.9% (we draw more) |

**Four were already working and the fix did nothing for them** — XANADU 38,518
before and after, Quest 18,104, Psy-O-Blade 24,385, Urusei Yatura 5,330.
XANADU was already carried by the container fix in `6f1512d`. Worth stating
because the endpoint alone would credit the scan bound with all eight.

**Machine matters more than expected in this set.** Psy-O-Blade and Urusei
Yatura are blank as FM-7 and MATCH as AV; Reviver and Death Force are the
reverse. Sweeping this set on one machine would have produced a wrong answer
for four of sixteen titles either way.

### The machine audit: 11 of cohort 03's 40 disks are AV software

Trap 72 predicted this; measuring it was cheap and the payoff was large. Screen
each disk with a 300-frame FM-7 run and read the run summary's `UNDECODED ports`
line — an AV title names the AV MMR registers `$FD80`-`$FD93`, or the analog
palette `$FD30`-`$FD34`, or `$FD12`. Forty disks in minutes, against hours for a
re-sweep.

**11 of 40 (28%)** flagged. Re-run under `fm77av` on BOTH sides, **four** go
straight from `BOTH-BLANK` to `MATCH` — they were working the whole time:

| title | as fm7 | as fm77av |
|---|---|---|
| Dragon Buster (Dempa) | BOTH-BLANK | **MATCH**, GRAPHICS 87.3 against 87.2 |
| Mah-jongg Kyo Jidai Special | BOTH-BLANK | **MATCH**, 66.6 against 66.8 |
| Silpheed | BOTH-BLANK | **MATCH**, GRAPHICS 13.3 against 13.3 |
| SIL_A.D77 (a second Silpheed dump) | BOTH-BLANK | **MATCH**, GRAPHICS 13.3 against 13.3 |
| Ys Omen `[a]` | CORE-BLANK | MATCH 32.2 against 32.1 (after `9b9af08`) |
| Gambler Jikotyusinha | MATCH | MATCH |
| Team AB Music Disk | TEXT-ONLY | TEXT-ONLY 2.1 against 2.4 |
| Girls Paradise | TEXT-ONLY | TEXT-ONLY 1.2 against 1.2 |
| FM77AV demo `[Alt 1] [b]` | BOTH-BLANK | BOTH-BLANK — genuinely blank on both |
| OS-9 Level 1 (Disk 2) | TEXT-ONLY | BOTH-BLANK |
| HARRIER1.D77 | BOTH-BLANK | BOTH-BLANK — blank on both machines |

**`BOTH-BLANK` is where this hides.** It reads as "neither side draws it,
probably a data disk", so nothing revisits it — and six of the eleven were
sitting in it. `FM77AV demo [Alt 1] [b]` names the machine in its own filename
and was still swept as an FM-7.

**This caveats the campaign's own numbers.** Cohort 03's split was measured with
roughly a quarter of the cohort on the wrong machine, and cohorts 01 and 02 were
never screened at all — cohort 01's headline, "0 core bugs in 40 disks, all 12
blanks were blank on the reference too", rests on twelve blanks that may include
AV titles scored against FM-7 ROMs. **Screen 01 and 02 before trusting either.**

### Cohorts 01 and 02 screened too: 17 of 80 are AV software

Same 300-frame screen. **17 of 80 (21%)**, consistent with cohort 03's 28%, so
this is systematic across the campaign rather than one unlucky draw. Re-run
under `fm77av` on both sides, **nine MATCH**:

| title | as fm7 | as fm77av |
|---|---|---|
| Albatross (Disk 1) | blank (Aug-8 sweep) | **MATCH** 95.7 against 98.3 |
| Hot Dog `[b]` | "flat white, broken everywhere" | **MATCH** 94.9 against 94.5 |
| Argo | "flat blue, broken everywhere" | **MATCH** 73.2 against 73.8 |
| FM Sound Editor | — | **MATCH** 69.8 against 69.8 |
| `[Compilation]` Game 2 | "2 colours against our 1" | **MATCH** 49.9 against 51.8 |
| Amnork | — | **MATCH** 39.2 against 39.2 |
| Relics | — | **MATCH** 26.7 against 26.7 |
| Mugen Sensi Valis | — | **MATCH** 23.8 against 24.3 |
| Solitaire Royale | — | 61.8 against 82.3 — **a real gap, follow up** |
| Take Out Vol. 6 | — | REF-WORSE: we draw 15.3, the reference is blank |
| F-BASIC V3.3L11, Take Out Vol. 7 A, Kohaku Iro | — | genuinely BOTH-BLANK |

**This retires trap 70's cohort-01 conclusion.** That trap examined cohort 01's
four "actionable" rows and decided each was a title broken on both machines.
Three of the four — Argo, Hot Dog `[b]`, GAME2 — are AV software, and all three
render correctly on the right machine. A flat fill and a noise screen are the
*wrong-machine signature*. `REFERENCE.md` trap 70 is corrected in place.

It also means **cohort 01's "0 core bugs in 40 disks" rested on a
mis-measurement**: its 12 blanks included AV titles scored against FM-7 ROMs,
and at least three of them draw.

### Cohort 04: the corrected pipeline, and what it caught

10 of 40 (25%) screened as AV software — consistent with 28% and 21% before it,
so roughly **a quarter of the FM-7 set is FM77AV software** and the remaining
235 disks will need the same split. Swept 30 as `fm7` and 10 as `fm77av`, four
frames each.

**Zero real core bugs.** Both rows the scorer flagged dissolved, and each was
caught by one of the two steps added this session:

| row | verdict | what it was |
|---|---|---|
| Archon | CORE-WORSE, 4.8 against 58.8 | **The four-frame test.** We draw the title at 600/1000 matching the reference (58.2/58.4 against 58.9/58.3), then run on. The reference follows the SAME trajectory later: ours 1400/1980 = 16.9/4.8 against its 2500/5000 = 17.4/4.7. Same sequence, ours ~2x earlier. |
| GAME3.D77 | CORE-MONO | **The machine screen** — AV software. MATCHes 31.4 against 34.0 as `fm77av`. |

Two more recovered by routing: GAME3 and DAIVA_A (GRAPHICS 9.4 against 9.4,
exact). Pro Yakyu Fan, Deep Forest and Woody Poco all match the reference
exactly — Pro Yakyu Fan being the cohort-02 sector-register fix, confirmed on
its proper machine.

**A lead, not a finding: two titles now run their attract sequence ~2x ahead of
the reference** — Archon above, and Penguin-kun Wars, which reaches its menu
while the reference never leaves its title through frame 5000. The machines
differ by 0.6% in frame rate (59.6374 against 60 Hz), so a 2x gap is not that.
Whatever timer these sequences count on is worth measuring, and it would also
explain REF-WORSE rows recorded elsewhere.

### Open on the FM-7 side

- **Lupin Sansei - Cagliostro no Shiro (Disk B) stalls the simulator**, and it
  is **not** from this session's changes — the pre-`b64f1f7` binary hangs
  identically, and the scan-bound fix cannot touch it (348,848 bytes, under the
  1 MB ceiling, so `scan_limit` is bit-identical to the old expression). The
  curve is a cliff, not a slowdown: frame 40 in 17 s, frame 60 in 25 s
  (0.42 s/frame), frame 80 not reached in 300 s. Frames stop advancing, so
  suspect whatever drives vblank rather than the CPU. It is an AV title
  (`$FD80-$8F`, `$93`, `$FD30-$34`) and this is on the `fm77av` path. It is
  why the row came back NO-SHOT in the sweep.

- **Draw cohort 05.** 235 disks remain. Screen it for machine FIRST, then sweep
  each half on its own machine with `SHOTLIST=600,1000,1400,1980`. On cohort 04
  that pipeline turned two flagged rows into zero real bugs without any
  after-the-fact archaeology.
- **Ys II - The Final Chapter is NOT a bug — cleared as trap 49.** It renders
  **94.48% GRAPHICS at frames 1200 and 1400**, against the reference's 94.5%.
  It is an animated intro and the sweep's frame-1980 sample lands on a blank
  moment between scenes: 1400 draws 94.5%, 1500 and 1600 are blank, 1700 is
  13.0%, 1800 is 20.3%, 1900 is 23.3%, 1980 is blank again.

  `displayPage` is **0 for all 757 `$D430` writes over the whole run** (390x
  `$85`, 355x `$a5`, 12x `$84`), so there is no page flip to chase.

  *(Superseded, twice, and both worth knowing because each was a confident wrong
  answer. First: "an FDC retry storm", from a 37x `$FD18` ratio that was a
  transient confined to frames 11-16 — the loader waiting out the mount scan.
  Second: "draws into the wrong VRAM bank", from a single VRAM snapshot at frame
  2000 showing bank 1 populated and bank 0 empty. At frame 400 the picture is in
  bank 0, correctly; the buffers alternate and one snapshot cannot show that.
  What exposed it was two instruments disagreeing — `DEBUG_VBLOCK`'s per-block
  write counters said bank 0 held the nonzero data while the dump said bank 1
  did. Run from the SAME frame they agree; the snapshot was simply from a
  different moment.)*

- **Death Force is blank on the FM-7: sub BUSY is stuck at 1.** Diagnosed, not
  fixed. `BUSY=1`, `$fd05` reads `$fe`, and the main CPU polls `$FD05`
  **1,094,760 times against the reference's 131,773** — from frame 0 straight
  through, not a transient. The sub CPU runs (19.2M instructions, pc `$c090` in
  sub RAM) but touches `$D40A` only **8 times** against Ys II's 869, so it never
  reaches its idle loop to clear BUSY. Downstream everything starves: reads stop
  after **track 0**, the PSG is never touched (`$FD0D`/`$FD0E`/`$FD15`/`$FD16`
  all zero against 2,088/696/4,530/1,510), not one analog-palette entry is
  written where the reference writes 4,096, and VRAM ends at 147 non-zero bytes
  against 14,349. Same shape as the FM Sound Editor fault: the sub is waiting on
  something this core never answers. Trace the sub side at `$c090` and find what
  it polls.
- **Audit the AV table's 27 BOTH-BLANK rows for machine.** Two of the three bugs
  found in this round were hiding in exactly that verdict, on the wrong machine.
  BOTH-BLANK is the bucket nobody re-examines, which is what makes it worth
  examining.
- **Thexder renders wrong, and the gate has been blessing it.** Our
  `disk-Thexder [b]` shot carries a horizontal band of cyan/white striped
  rectangles that `shots-ref-77avemu/` does not have; agreement against that
  independent render is only **81.6%**. It is NOT new — the previously blessed
  shot has the identical artifacts, so this has been green for as long as the
  row has existed. `shots-ref/` is the core's own output and structurally cannot
  catch it (trap 25); `shots-ref-77avemu/` exists precisely for this and nobody
  had compared this row against it.
- **Marchen Veil's second fault**, above.
- **Daisenryaku draws its title art at frame 400 and then erases it.** The art —
  soldier, tank, aircraft — matches the reference; what never appears is the red
  大戦略FM logo, which the reference has by 604. By frame 600 this core is blank
  (0.2%) and is text-only thereafter. (Superseded: both "reaches its title screen
  at frame 621" and "renders nothing, 3,790 bytes" — each was a single frame, and
  a title that is drawn *and then erased* is invisible to any one sample.
  `docs/REFERENCE.md` corrected.)
- **Re-test the 28 containers properly.** The first pass ran two FM77AV titles
  in `--machine fm7`, so those results are meaningless.
- **The AV numbers above are stale on OUR side.** Re-scoring flagged FM Sound
  Editor, Daiva Story 2 and Mahjong, all fixed this session. The frame-matched
  AV references are rendered and saved in `sweep/renders-postfix/ref-shots`, so
  only our half needs re-running (~3.5 h).

## The RTL fixes, and why they mattered

**`mc6809i.v` — NMI was never masked after reset.** `CPUSTATE_RESET` assigns
`s_nxt = $FFFD`, which satisfied the `s != s_nxt` release condition on the same
cycle that set the mask, so the 6809's documented "NMI masked until S is loaded"
never applied. Invisible on a cold boot; fatal on the FM77AV's `$FD13`
sub-system reset, where the display NMI is already running — the sub CPU takes an
NMI during its `$D000-$D35F` clear loop, before its init reaches `LDS`, pushes 12
bytes to `S=$FFFD` (ROM, discarded), and walks a `NEG <$00` sled through VRAM
for the rest of the run. Fixed Luxsor disk 2.

**`FDC.v` — the sector register belongs to the controller, not the drive.** A
real FM-7 has one WD1793 whose registers all drives share; this core instantiates
one per drive, each with its own register file, so a sector-register write made
while another drive is selected never reaches the drive that needs it. Pro Yakyuu
Fan's loader keeps its place with `LDA $FD1A / INCA / STA $FD1A` and the boot
ROM's drive scan selects drive 1 in the middle of it. Only `addr 2` is mirrored;
the command, track (which this design also uses as head position) and data
registers stay per-drive until something demonstrates otherwise.

**`AVMEM.v` — the TWR window sat 31 KB low.** `$FD92` is an offset *added to the CPU
address*, so register 0 puts the 1 KB window at `$7C00-$7FFF` over physical `$07C00`,
not `$00000` — 77AVEMU (`memory/fm77avmemory.cpp:1239-1243`) and CSP
(`fm7/mainmem_mmr.cpp:16-22`) agree, and `docs/FM77AV.md` had paraphrased it as
`addr[9:0]`, dropping the term. The RTL matched the doc, so reviewing one against the
other agreed. Invisible unless a title both banks code into low RAM page 0 *and* uses
the window: FM Sound Editor copies 4 KB to physical `$00000`, then walks a RAM-size
probe through the window from register `$00` and erases it. See REFERENCE.md trap 64.

**`AVKEYBOARD.v` — the encoder never answered the sub monitor's clock read.** Command
`$80`/`$00` must return **seven** packed-BCD bytes; this core took it as a stub that
consumed its parameter and produced nothing, so `$D432` b7 never cleared. The sub CPU
sat in `BITA $d432 / BNE` at `$DF8B` forever, never reached its idle loop's
`TST $d40a`, and BUSY stayed set — so the main CPU waited on `$FD05` at `$F650` for the
rest of the run. FM Sound Editor made 16 sub calls where the reference made 281. The
command table, its parameter COUNTS (which are load-bearing: the encoder has no framing)
and the one place the two references disagree are in `docs/FM77AV.md`.

**`FLAGS.v` — the `$FD13` sub-monitor reset was blanking the display.** The CRT on/off
latch hung on `SRESETn`, which is `RESETBn & ~AV_SUBMON_RESET`, so a monitor-bank
switch cleared it. Neither reference does: 77AVEMU's `$FD13` resets the sub CPU and
sets BUSY and nothing else (`fm77avio.cpp:193-201`), and CSP's `reset_some_devices`
clears the INS LED, halt, multipage masks and palette but not `crt_flag`
(`display.cpp:71-140`). The two flip-flops that shared that reset now take different
ones — the CRT flag on power-on, the INS LED on `$FD13` as well, which is what CSP
does. Fixed **Daiva Story 2 disk A**, which was drawing the whole time: 4067 non-zero
VRAM bytes against the reference's 4078, into a screen held black.

**`AVMEM.v` + `core.v` — the shared window `$FC80-$FCFF` was open while the sub CPU
ran.** The main CPU reaches it only while the sub is halted: read `$FF`, write
discarded, otherwise. Both references agree and neither confines it to the AV (CSP's
`read_shared_ram` is plain FM-7 code). Mahjong Kyou Jidai *probes* it — `CLR $fc80` /
`LDA $fc80` / `BEQ` — and reading back its own `$00` told it the sub was already
halted, so it skipped the halt and drove the drawing ALU through an aperture that then
correctly dropped the writes: **211 line triggers issued, 10 landed**. Note the read is
served from `core.v`'s `~(SUBSELn | RDQEn)` mux arm and never passes AVMEM's DOUT, so
the gate lives in both files — gating only the write gives byte-identical output, which
looks exactly like a build that did not take.

**`SRAM.v` — and the SAME rule again, because a second write path bypassed it.**
`main_write` was `(~SUBSELn & ~WTQEn) || AV_SHARED_WRITE`; gating only the AVMEM term
left the FM-7's own `$fcxx` decode ungated, so Mahjong's attention bit at `$FC80` was
set while halted and then wiped by the very next `CLR $FC80` with the sub running. With
both gated its **VRAM matches 77AVEMU on all 98,304 bytes**. The lesson is in the
commit: when a rule has two implementations, gate both, and *instrument the gate* —
a `DEBUG_AVDRAW` probe printing accepted-vs-dropped with `sub_open` is what proved the
attention write landed and sent the search after a second writer.

## Tools built this session — use these before inventing anything

Every wrong answer this session came from inferring a measurement the other
machine could have given directly. Three of these are one-liners that existed
only because nobody had asked.

| tool | what it gives |
|---|---|
| `tools/seqdiff.py` | now RE-SYNCHRONISES after a divergence (40-entry look-ahead, 3 to confirm) instead of desynchronising forever. Every row printed is real. **Counts are deliberately not compared** — a count difference is not a divergence, so a retry loop is invisible to it. |
| `--trace-fdc` (harness) | the reference's own FDC log, one line per command with `C`/`H`/`R`. The counterpart of `wd1793.sv`'s `WDMATCH`. This is what cracked Pro Yakyuu Fan. |
| `FM77AV_CPU_DUMP` / `FM77AV_SUBCPU_DUMP` | the reference's logical 64 KB CPU view, the counterpart of `--dump-shadow` / `--dump-shadow-sub`. |
| `FM77AV_MMR_DUMP` + `make DEBUG_MMR=1` | all four MMR segment maps on both machines. Comparing `$FD8x`/`$FD90` write streams structurally *cannot* see a segment-interleaving difference; only the maps can. |
| `make DEBUG_FDC=1` | `WDMATCH` (every sector the controller matched), `WDNOMATCH`, `WDDROP`, a `SECREG` probe, and `D77SCAN done: fmt/tracks/sectors/wp` — the scan summary is the fastest way to tell a disk that will not parse from one that will. |
| `sweep/cohort.py` | draw / retire / status for the 395-disk FM-7 set. `retire` REFUSES unless our side rendered every disk in the cohort, which is the only thing stopping a partial sweep from burying disks permanently. |
| `sweep/sweep-list.sh` | sweep an explicit `images.txt` instead of the whole archive. Same row format and shot naming, so `ref-shots-at-frame.sh`, `compare-ref.py` and `gallery.py` all work on the result unchanged. |
| `sweep/ref-shots-at-frame.sh <dir> 1980 6 fm7` | reference renders at the MATCHED instant. The 4th arg is the machine and defaults to `av` — an FM-7 sweep pointed at AV references scores every row against the wrong machine and nothing announces it. |
| `FM7_VRAM_DUMP` | now works for FM-7 titles too (it was gated AV-only and silently wrote no file). The one measurement that separates "the bytes were never stored" from "the raster will not show them". Note `--av-dump-frame` defaults to 870, so a shorter run writes nothing either. |

### The comparison that works

```sh
# same machine-time instant on both sides: reference frame = round(N * 1.00608)
cd vsim && make DEBUG_FDC=1 -j8
./obj_dir/Vemu --headless --machine fm77av --disk DISK.d77 \
    --stop-at-frame 500 --trace-tail 0 --trace-io /tmp/ours.log
refs/local/fm77av_headless refs/local/fm77av-roms DISK.d77 200000000 \
    /dev/null --stop-at-frame 503 --trace-io > /tmp/ref.log
tools/seqdiff.py /tmp/ours.log /tmp/ref.log 6
```

`1.00608` = `60 × 1024 × 262 / 16e6`. A vsim frame is a real raster frame at
59.6374 Hz; a 77AVEMU frame is exactly 1/60 s of machine time. And note the
gate's shot frame is *not* its stop frame: it runs to `FRAMES` (620) and
photographs at `FRAMES - 20` (600), so the reference renders at **604**.

## Open work, highest value first

0. **Draw cohort 05** (`python3 sweep/cohort.py next --size 40`). 235 FM-7
   disks remain. The rate is roughly 5 real bugs per 160, and **a quarter of the
   set is AV software** — screen before sweeping (`docs/TESTING.md`).
1. **Luxsor disk 1** — see below. Deep, and five hypotheses have died. The TWR
   and encoder fixes do not touch it — every counter over 2000 frames is
   byte-identical against a same-tree baseline built from `1455e4a` in a
   worktree (trap 57). The `$FD13`/CRT fix changes one line, `display OFF` ->
   `display on`, and it is still blank: **its digital palette is all zeros**,
   so all eight colours are black. Measure that before the CPU runaway.
2. **A fresh 68-title AV sweep.** The fixes above are systemic — a memory
   translation, a sub-system handshake, a display latch and a shared-window
   gate — and the set has not been re-measured since. Build the "before" from the same tree in the same
   session (trap 57); the table at the top of this file predates all three.
3. **Shounen Mike** at 85.79 % — close, and the remaining difference is colour:
   the logo reads grey/olive here and green on the reference.
4. **Per-row gate shot frames.** `av-kohakuiro` and `av-wizardry4` are attract
   animations photographed at one global `SHOT_AT`, so they catch whatever
   instant they land on. Kohakuiro draws its logo at frame ~199 and fades by 400.
6. **Cassettes** — separate section in `CONTINUATION.md`, five of six images work
   on hardware.

## Luxsor disk 1 — read this before touching it

**It is NOT a regression.** The build that renders is the one that *loses* the
`$FD05` sub-BUSY race against the reference; HEAD matches the reference there and
goes blank. The old picture was an artifact of being wrong. **Do not revert the
cycle-steal change to "fix" it** — that change is more correct (77AVEMU's
`CRTCHaltsSubCPU` defaults false, XM7's `cycle_steal` true) and gained six titles.

Measured clean, do not re-check: the FDC (first 142 reads identical, zero
NOMATCH), the sector data (~99.8 % over 40,000 bytes, the residual being the
reference's one-position pre-side-effect log shift), the boot ROM's seek logic,
and the MMR (all four segment maps byte-identical, page 6 → `$36` on both).
**Re-check the TWR window**, though — the "640 bytes, zero differ" result predates
the `AVMEM.v` offset fix, and this title's boot-time reads of `$7C00-$7FFF` were
31 KB off the reference's when it was taken.

The live lead: the reference rewrites the loader's dispatch table at `$5090`
twice between frames 240 and 300 and this core never does. Bracketing with
`FM77AV_CPU_DUMP` at a spread of frames works and costs about a minute a sample.

## How to not waste the first hour

These cost real time this session. `docs/REFERENCE.md` traps 55–67 have the full
versions; these are the ones that bit hardest.

- **The build lies.** `make DEBUG_FDC=1` does **not** rebuild if no source
  changed, so you silently run the previous binary. Three wrong answers came from
  this. `touch ../rtl/wd1793.sv` first, and check the size: debug 3533560, normal
  3532536. Byte-identical output after a change means suspect the build.
- **`--dump-shadow` is a HISTORY, not a snapshot.** It records the last byte the
  CPU *saw* at each logical address, so a page the CPU stopped reading keeps stale
  bytes forever. `FM77AV_CPU_DUMP` is a true snapshot. Comparing them, **agreement
  is strong evidence and disagreement is only a question.** I wrote this trap and
  then walked into it (trap 60).
- **Never compare two instruments or two window lengths.** A reconstructed read
  list, a `WDMATCH` list from 120 frames and a register probe from 70 frames told
  three different stories and two became published findings that had to be
  retracted. Write down which instrument produced each side and over what window
  before reading the numbers (trap 63).
- **A reconstruction is not an instrument.** If the reference cannot produce the
  measurement directly, add the print to `tools/77avemu_headless.cpp` rather than
  inferring one from its I/O trace.
- **The checked-in sweep TSVs are a record, not a baseline** (trap 57). Build the
  "before" from the same tree in the same session: `git stash push rtl/`, `make`,
  run, `git stash pop`.
- **A register that flips a title between working and blank is not necessarily
  the register at fault** (trap 55). It happened twice on the same title.
- **`pgrep -fc` gives false zeros** on long command lines; it reported a healthy
  sweep as dead. Use `ps -Ao pid,etime,command`.
- **A blank screen is not always the core's fault**, and a green gate is not
  always coverage: `shots-ref/av-kohakuiro.png` was a blessed blank for a while,
  and no gate test exercises the timer IRQ at all, which is why an unmasked NMI
  survived indefinitely.

## Validating a change

`cd vsim && ./run_tests.sh` — eleven rows, screenshots *and* counters, exits
non-zero on any difference. Both this session's RTL fixes passed it unchanged.
Bless with `BLESS=1 ./run_tests.sh` and say why in the same commit; a blessed
reference with no explanation is indistinguishable from an unnoticed regression
later. For breadth, `sweep/av-sweep.sh <outdir> 6 2000` then
`sweep/compare-ref.py <outdir>` — move the per-frame `_frame_NNNN.png` samples
aside first or they are counted as titles.
