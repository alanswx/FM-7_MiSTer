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
