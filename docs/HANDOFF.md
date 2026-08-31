# Start here

Orientation for picking this branch up cold. Detail lives in
`docs/CONTINUATION.md` (open work, per-title), `docs/REFERENCE.md` (measurement
traps — read section 5 before trusting any number) and `HARDWARE-HANDOFF.md`
(the FPGA side). `CLAUDE.md` has the documentation rules; follow them.

Branch `fdc-d77-support`, pushed to `alanswx`. Working tree clean, gate 11/11.

**The single most useful thing to know before you start:** most of what looks
like a core bug in this campaign has turned out to be a MEASUREMENT defect —
the wrong machine, the wrong frame, or the wrong reference constant. Of the
candidates chased most recently, three of four dissolved. Read
`docs/REFERENCE.md` traps 70 and 72-77 before triaging anything; each one cost
hours and each is a specific, repeatable check.

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
well. The three titles verified individually as gained by those fixes are FM
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

**Coverage: 240/395 (60.8%).** Cohorts 01-06 retired.

| cohort | result |
|---|---|
| 01 | **0 core bugs in 40 disks.** All 12 blanks were blank on the reference too |
| 02 | **4 real bugs**, 3 fixed. 15 MATCH, 14 BOTH-BLANK, 5 TEXT-ONLY, 1 REF-WORSE |
| 06 | **1 real bug, known**: LUXSOR_1 blank against the reference's 27.1%, reproducing the Luxsor disk-1 fault on an INDEPENDENT dump while LUXSOR_2 matches exactly. 19 MATCH, 14 BOTH-BLANK/TEXT-ONLY, 2 REF-WORSE. 9 of 40 AV |
| 05 | **0 core bugs in 40 disks.** 19 MATCH, 12 BOTH-BLANK, 9 TEXT-ONLY. 9 of 40 screened AV. Nothing flagged actionable on either half |
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

### What the cohort campaign has established

Method lives in `docs/TESTING.md`; the traps it cost are 70 and 72-77 in
`docs/REFERENCE.md`. What matters here is the state.

**A quarter of the "FM-7" set is FM77AV software.** Screened by a 300-frame run
per disk, reading the run summary's `UNDECODED ports` line for `$FD80`-`$FD93`,
`$FD30`-`$FD34` or `$FD12`. Five cohorts, 200 disks, all in a 21-28% band:
01+02 17/80, 03 11/40, 04 10/40, 05 9/40 — **about 90 of the 395 are AV
software**, and for the 195 still unswept the screen is not prudence, it is the
difference between a verdict and a coin flip. Sweeping those as an FM-7 scores them against the wrong ROM set, and
`BOTH-BLANK` is where they hide — it reads as "probably a data disk" and nothing
revisits it.

**15 titles were recovered by nothing more than running them on the right
machine**, all previously recorded as blank or broken:

| title | as fm7 | as fm77av |
|---|---|---|
| Albatross (Disk 1) | blank | MATCH 95.7 / 98.3 |
| Hot Dog `[b]` | "flat white, broken" | MATCH 94.9 / 94.5 |
| Dragon Buster (Dempa) | BOTH-BLANK | MATCH 87.3 / 87.2 |
| Argo | "flat blue, broken" | MATCH 73.2 / 73.8 |
| FM Sound Editor | — | MATCH 69.8 / 69.8 |
| Mah-jongg Kyo Jidai Special | BOTH-BLANK | MATCH 66.6 / 66.8 |
| `[Compilation]` Game 2 | "2 colours against our 1" | MATCH 49.9 / 51.8 |
| Amnork | — | MATCH 39.2 / 39.2 |
| GAME3.D77 | CORE-MONO | MATCH 31.4 / 34.0 |
| Relics | — | MATCH 26.7 / 26.7 |
| Mugen Sensi Valis | — | MATCH 23.8 / 24.3 |
| Silpheed, SIL_A.D77 | BOTH-BLANK | MATCH 13.3 / 13.3 |
| DAIVA_A.D77 | BOTH-BLANK | MATCH 9.4 / 9.4 |
| Ys Omen `[a]` | CORE-BLANK | MATCH 32.2 / 32.1 (after `9b9af08`) |

**Cohorts 01-03 were scored before the pipeline was corrected**, so their
verdict splits are soft — cohort 01's "0 core bugs, all 12 blanks were blank on
the reference too" rests on blanks that included AV titles scored against FM-7
ROMs, and at least three of them draw. Cohort 04 is the first run with machine
screening and four-frame sampling, and it produced 0 core bugs in 40 disks with
both flagged rows caught by the new steps rather than by later archaeology.

**Still open from the sweeps**, beyond the list below:

- **Re-test the 28 containers properly.** The first pass ran two FM77AV titles
  in `--machine fm7`.
- **Solitaire Royale** is 61.8 against 82.3 on the CORRECT machine — a real gap,
  unexamined.
- **Team AB Music Disk No. 0 and ... (2D) Disk 1** show nothing (0.04%) where the
  reference shows a static 2.0% text line, at all four sampled frames on both
  sides. Cohort 06, AV. Same shape as Jesus below.
- **Jesus (1987)(ENIX)** shows nothing where the reference shows a static 0.66%
  text line, at all four sampled frames on both sides. Persistent and small;
  neither side runs the game, but we are strictly worse. Cohort 05, AV.
- **Take Out Vol. 6** is REF-WORSE, unexamined.


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
- **Thexder's 81.6% gate agreement is draw-progress PHASE, not wrong pixels.**
  (Superseded claim, mine, from earlier the same day: "Thexder renders wrong and
  the gate has been blessing it." That was based on one frame. It is wrong, and
  so was the retraction I then made off frame 400 — see below.)

  Measured at four matched instants:

  | our f | ref f | agreement | ours | reference |
  |---|---|---|---|---|
  | 400 | 403 | 99.98% | **3.9% / 1 colour** | **3.9% / 1 colour** |
  | 600 | 604 | 81.58% | 58.8% / 6c | 56.7% / 6c |
  | 800 | 805 | 82.91% | 61.0% / 6c | 59.4% / 6c |
  | 1000 | 1006 | 85.40% | 60.4% / 6c | 60.7% / 6c |

  **Frame 400's 99.98% is an abstention** — both sides are near-blank, the same
  failure mode as av-kohakuiro. The reference is text-only at 3.6-3.9% from
  frame 302 through 503 and the title appears between 503 and 604, so **600 is a
  legitimate sample point and there is no better one.** Do not re-pin this row.

  The difference is a progressive draw running ahead of the reference. At each
  sample a band exists in ours that the reference has not drawn yet, and the
  reference has it by the next sample:

      f600   rows 92-107   ours white+cyan 3066   ref 0
      f800   rows 60-67    ours            3215   ref 0
      f800   rows 95-107   ours            2756   ref 2297   <- caught up
      f1000  rows 60-63    ours            1535   ref 1507   <- caught up

  Same "we are ahead" shape as Archon and Penguin-kun Wars, and this one
  QUANTIFIES the lead, because both sides sit on an identical text screen until
  one of them starts drawing:

  | frame | ours | reference |
  |---|---|---|
  | 400 | text 3.88% | text 3.88% |
  | 450 | **lowcolour 43.66%** | text 3.88% |
  | 500 | **lowcolour 56.44%** | text 3.88% |
  | 600 | lowcolour 58.78% | lowcolour 56.70% |

  We start drawing between 400 and 450; the reference between 503 and 604.
  **We are 120-150 frames — 2 to 2.5 seconds — ahead on a disk-paced draw.**

## Three titles run AHEAD of the reference, and the cause is measured

Thexder (above), Archon (attract sequence ~2x early) and Penguin-kun Wars
(reaches its menu while the reference never leaves its title through f5000) all
run ahead. The frame-rate difference between the machines is 0.6% and the timer
is now correct to 0.002%, so neither explains it.

Thexder is the one with a mechanism attached: its draw is paced by the disk
load, and 2-2.5 s is a lot of sectors. **The hypothesis is that this core's FDC
delivers data faster than a real drive** — no rotational latency, optimistic
seek, or a step rate that is too quick.

**MEASURED, and confirmed.** Neither FDC trace carries a timestamp, so instead
of patching vendored source: run the reference to six stop-frames and count its
cumulative `IO:FD18 VALUE:80` commands, and bin ours by the frame column its
`--trace-io` already prints. Thexder, same disk, same 417 sectors on both sides:

| frame | reference | ours |
|---|---|---|
| 100 | 0 | 0 |
| 200 | 40 | **100** |
| 300 | 129 | **207** |
| 400 | 229 | **328** |
| 500 | 382 | 417 (done) |
| 600 | 417 | 417 |

We finish the load ~100 frames early, which accounts for the 120-150 frame
drawing lead directly. The gap is widest at the start: 2.5x by frame 200.

**And our rate is not physically plausible.** A 2D drive is 300 RPM = 200 ms =
11.93 frames per revolution, 16 sectors of 256 B per track:

| | sectors/frame |
|---|---|
| 1:1 interleave, zero rotational latency — the PHYSICAL MAXIMUM | 1.34 |
| 2:1 interleave | 0.67 |
| 3:1 interleave | 0.45 |
| **ours, measured** | **1.04** (1.00 early) |
| reference, measured | 0.93 (**0.40** early) |

**(Superseded claim, mine: "ours is 78% of the physical maximum, only reachable
with no rotational latency — add latency to wd1793.sv." That inference is
WRONG and it was briefly ranked as the top open item.)**

1.04 is *below* 1.34, so our rate is physically achievable, and two further
measurements say it is not even aggressive:

- Thexder's image stores sectors **1..16 in physical order** on every track,
  i.e. a 1:1 layout as recorded.
- It requests them **largely sequentially** — `1,4,5,6 … 4,5,6,7,9,10..16 …
  1,2,3..16`.

Sequential reads off a 1:1 track arrive one sixteenth of a revolution apart:
12.5 ms, or 1.34/frame. **Ours is 16.8 ms/sector — slightly SLOWER than the
ideal, not faster.** It is the reference's early 0.40/frame (42 ms/sector) that
is slower than a 1:1 layout permits.

So the honest state is: **the lead is real and reproducible, but its cause is
not established.** Ours is plausible for a 1:1 disk; the reference is
conservative; and a `.d77` cannot settle which is right, because the format
records the sector order a dumper wrote and many dumpers write logical order
regardless of the physical interleave. Do not "fix" the core's timing on this
evidence — a change that slows every disk title in the gate and four retired
cohorts needs better grounds than a comparison against the slower of two
emulators.

**What would settle it**, in order of strength: real FM-7 hardware; the
`refs/fm7-docs` manuals on the MB8877's sector timing and the drive's specified
transfer rate; or CSP as a third opinion, since it is the primary authority and
disagrees with 77AVEMU on the timer constant already.

`wd1793.sv` does model the index hole (free-running counter, `s_index <= cnt <
100`) but only for status bit 1; a sector read is served as soon as its SD block
lands. `seektimer` is 0x3FF at the 1 MHz `ce` = 1.02 ms, so it is not the
limiter either. If latency is ever added, that is where it goes.

  **What is actually left is small**: rows 2-46 differ in the GREEN plane only
  (3,394 bytes), and the colour histograms there are near-identical — blue
  17,131 against 16,223, black 9,350 against 10,245. That is a dithering or
  pattern difference of a few hundred pixels, not a structural fault. Worth a
  look, but it is not an 18% defect.
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

## Tools — use these before inventing anything

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

0. **Draw cohort 07** (`python3 sweep/cohort.py next --size 40`). 155 FM-7
   disks remain. The rate is roughly 5 real bugs per 200, and **a quarter of the
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

**Two constraints from cohort 06 that were not available before, both cheap and
both narrowing:**

1. **It reproduces on an INDEPENDENT dump.** `LUXSOR_1.D77`
   (md5 `62c6c90f8843bdad05fec7d906ecdea4`) is a different file from
   `Luxsor (FM77AV) (Disk 1).d77` (`5da20f511fdbd946fa8c26643d78c9e8`) and fails
   identically: ours blank 0.0% at all four sampled frames, the reference
   drawing GRAPHICS at all four (98.3 / 20.3 / 26.6 / 27.2%). **It is not a bad
   image.**
2. **Disk 2 of the same game is PERFECT.** `LUXSOR_2.D77` matches the reference
   exactly, 81.7% against 81.7%. So the machine runs this title's code and
   renders its graphics correctly — whatever disk 1 does differently is where
   the fault is, and a diff of what the two disks ask the FDC and the sub system
   to do is a much smaller search than the five hypotheses already dead.

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
