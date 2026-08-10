# Hardware reports — the FPGA side's log

Rolling log from the hardware side (Quartus 17.0.2 → DE10-Nano → headless
screenshots), counterpart to `DERIVED_CLOCKS.md`. Newest state at the top;
sections below are in the order they were written and are kept as history.

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
ffmpeg -f v4l2 -i /dev/video4 -vf "select=gte(n\\,40)" -frames:v 1 out.png
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
without m46 the screen stays blank. Not a fix, and not enough runs to be
significant, but it points the same way as the rest of the `FLAGS` work.

## What would help from your side

A verified-bank regression between the build where OS-9 genuinely booted
(`b34171e`/`649d054` era, where the shell ran `dir`) and current head. This side
can bisect on hardware now that selection is trustworthy, but each point costs a
15-minute Quartus build, so a sim-side narrowing of which commit changed OS-9's
behaviour would cut that down a lot.
