# Testing

Two levels: a small regression suite that must stay green, and a breadth sweep
over the whole floppy collection.

## The regression suite

```sh
cd vsim
./run_tests.sh                 # every test
./run_tests.sh basic           # only tests matching a substring
BLESS=1 ./run_tests.sh         # accept current behaviour as the new reference
FRAMES=1200 ./run_tests.sh     # run longer
ALLDISKS=1 ./run_tests.sh      # include disks that have no reference yet
```

### What it covers

Boot (F-BASIC and the three DOS ROMs), the keyboard and shift tables through
F-BASIC, one disk title, and **one FM77AV title**. The AV row runs CaptainYS's
2019 demo from `software/FM77AV/`; by the shot frame that demo has programmed
all 4096 palette entries, filled all twelve 320-mode bit planes through the main
CPU's MMR aperture, driven `$D430`/`$D410` from the main CPU while the sub CPU
is halted, and started drawing text through the MB61VH010 ALU. Until it was
added the suite had **no AV coverage at all**, which is how a broken `$D430`
page select and a missing drawing ALU both survived unnoticed.

The suite is a gate, not a sweep. It runs disk titles that already have a
blessed screenshot; a `software/` tree holding a few hundred images would
otherwise turn a five-minute gate into a six-hour one. `ALLDISKS=1` runs
everything found, which is what you want when adding titles — and for a whole
collection use the breadth sweep below, which parallelises.

It compares **both halves** against `shots-ref/` and exits non-zero on any
difference:

* the **screenshot**, byte for byte
* the **counters** — frames, main/frame, sub/frame, I/O cycles — exactly. The
  sim is deterministic, so these do not drift on their own.

The two catch different bugs and neither subsumes the other. An extra interrupt
firing moves the counters while leaving the screen identical; a rendering change
moves the screen without touching the rates.

Counters are keyed on the **requested** frame count, so `FRAMES=1200` against a
620-frame reference compares nothing rather than reporting eight bogus failures.
A test with no reference reports `new` and does not fail the run, so dropping a
new `.d77` into `../software` does not break the suite — but see `ALLDISKS`
above: by default a disk with no reference is not run at all.

### Blessing

When a change intentionally alters behaviour, `BLESS=1` updates screenshots and
counters together so they cannot drift apart. It blesses only the tests that
actually ran, so a filtered run will not wipe references for what it skipped.

**Record why in the same commit.** A blessed reference with no matching
explanation is indistinguishable from an unnoticed regression later — which is
exactly how `shots-ref/` once rotted three months behind the core while the
suite compared nothing and still exited 0.

**Check every row actually ran before accepting a bless.** A row whose sim was
killed reports `?` counters plus `MAIN-STALLED SUB-STALLED NO-SCREENSHOT` — and
`BLESS=1` writes `0 0 0` into `counters.tsv` for it, because the counter row
falls back to zero while the screenshot copy is simply skipped. That is a
poisoned reference that will then "pass" nothing. Two rows were killed this way
by a `pkill -f Vemu` from another shell in the same checkout; `EXE=` exists to
run around that.

`shots-ref/` is the core's own output, so it cannot see a fault that moves the
whole picture (trap 25). `vsim/shots-ref-77avemu/` holds an independent 77AVEMU
render of the same rows at the same instant for exactly that reason —
informational, never a gate, scored with `sweep/compare-ref.py`.

## The breadth sweep

```sh
cd vsim/sweep
./sweep.sh <outdir> [jobs] [frames]        # e.g. ./sweep.sh /tmp/sw 12 1500
```

Extracts the Neo Kobe floppy collection, runs every `.d77`, and writes
`results.tsv` with `MAIN_PF  SUB_PF  PNG  IO  NOTES  TITLE`.

Recorded results live in `vsim/sweep/*.tsv` and are the baseline for per-title
comparison. Join on `TITLE`.

### Covering the collection in cohorts

Our side of a full sweep is roughly a day at 12 jobs; the reference side is
minutes. Sweeping everything on every change is therefore not a thing anyone
will actually do, and "we swept it a while ago" is how the Aug-8 FM-7 numbers
went 151 commits stale without anyone noticing. The method is to sweep a random
**cohort** at a time, retire it once it is genuinely covered, and draw the next
one from what is left. `cohort.py` keeps the bookkeeping:

```sh
cd vsim/sweep
python3 cohort.py status                 # coverage so far
python3 cohort.py next --size 40         # draw -> cohorts/NN-images.txt
cp cohorts/NN-images.paths /tmp/cNN/images.txt
MACHINE=fm7 ./sweep-list.sh /tmp/cNN 8 2000
./ref-shots-at-frame.sh /tmp/cNN 1980 6 fm7
python3 compare-ref.py /tmp/cNN
python3 cohort.py retire NN /tmp/cNN     # only if our side rendered all of them
```

**A cohort is covered when OUR side rendered every disk in it, not when it was
drawn.** A sweep that returns 37 renders for 40 disks and gets retired anyway
buries three disks permanently: nothing downstream looks for them again, and
the coverage count cheerfully reads 40. `retire` recounts against the outdir and
refuses if any disk is missing a render, naming the ones it would have buried.
That refusal is the whole point of the subcommand -- retiring is a one-line
`mv` otherwise.

**A cohort can contain FM77AV software.** The FM-7 set is not curated by
machine, so a cohort may draw an AV title; swept as an FM-7 the reference
renders *noise* and this core renders blank, which scores CORE-BLANK and reads
as a core bug. The run summary detects it without eyeballs — an AV title run as
an FM-7 shows the AV MMR registers in its `UNDECODED ports` line, `$FD80`-`$FD93`.
Re-run any such row as `av` on **both** sides before triaging it. See trap 72;
this is the same fault already recorded against the 28 multi-disk containers.

Disks are deduplicated **by content**, not by name: the collection ships the
same image under several paths (663 FM-7 files, 401 distinct). Six are excluded
because their safe-names collide with another disk's, and they are listed in
`cohorts/excluded-name-collisions.txt` rather than dropped silently -- see trap
68. Sweeping those six needs `sweep_one.sh` to disambiguate the name first.

Cohort *N* is seeded from its own number, so it is reproducible from the number
plus the retired set with no hidden state. The retired lists in
`cohorts/*-images.retired` are data and belong in git; the renders do not.

When every cohort is retired, `cohort.py all <outdir>` writes one list of every
distinct disk for a final validation pass. That run is there to confirm nothing
regressed across the cohorts -- it is not where the bugs are expected to be
found, because by then each disk has already been through a cohort.

### Scoring the FM-7 sweep against 77AVEMU

The AV sweep has been joined to the reference; **the FM-7 sweep has not, ever**.
Its blank count therefore has nothing behind it -- on the AV side, 27 titles
that the sweep called blank were blank on the reference too. A blank count that
has not been through `compare-ref.py` is an upper bound, not a bug list.

77AVEMU does run FM-7 software, under `--fm7`, and it boots a **different ROM
set** that way. Both halves of the join must be told:

```sh
cd vsim/sweep
./sweep.sh /tmp/fm7sw 12 2000                     # MACHINE defaults to fm7
./ref-shots-at-frame.sh /tmp/fm7sw 1980 6 fm7     # 4th arg -- the default is av
python3 compare-ref.py /tmp/fm7sw
```

`compare-ref.py` joins purely on filename and knows nothing about the machine,
so **an FM-7 sweep pointed at AV references scores every row against the wrong
machine and nothing announces the mismatch** -- the rows just look bad. The
fourth argument is the whole defence.

Use `ref-shots-at-frame.sh`, not `ref-sweep.sh`: the latter renders by 6809
instruction count, which is the wrong unit the moment a picture is scored
against a vsim screenshot. The frame-matched renderer samples the reference at
`round(vsim_frame * 1.00608)` -- 1980 -> 1992 -- because a vsim frame is a real
raster frame at 16 MHz / (1024 x 262) = 59.6374 Hz while a 77AVEMU frame is
exactly 1/60 s.

Two titles confirming the path works end to end, rendered at frame 1992:

| title | reference PNG |
|---|---|
| Thexder `[b]` (known-good control) | 351,646 B |
| Albatross Disk 1 (blank in the Aug-8 sweep) | 57,173 B |

Albatross is the one that matters: the reference draws a title the sweep scored
blank. The same disk under the AV default renders differently again (Thexder
356,545 B vs 351,646 B), which is the cheap check that the flag is actually
reaching the reference.

### Killing a sweep does not kill the sweep

`sweep.sh` and `av-sweep.sh` drive `sweep_one.sh` through `xargs -P`. Killing
the driver script leaves that `xargs` reparented to init and **still running**:
it keeps spawning simulator processes and keeps appending to the same
`results.tsv`. Restarting the sweep on top of that gives two sweeps writing one
file — every title appears twice, the machine carries double the load, and the
whole thing takes twice as long for no extra coverage.

The tell is duplicate titles in `results.tsv`, or a load average around twice
the job count. Check for the orphan before restarting:

```sh
ps -o pid,ppid,command -ax | grep '[x]args -0 -P'
```

and kill the `xargs` itself, not just the driver.

### Triage by instruction rate, not by screenshot

A screenshot cannot tell "crashed into a CWAI" from "idling at a screen it
already drew" from "running happily and choosing not to draw". `main/frame` can.
A 6809 at 1.2288 MHz retires roughly 5000 instructions per 60 Hz frame; an order
of magnitude below that means it is not running code.

| rate | screen | reading |
|---|---|---|
| low | blank | crash — expect a CWAI or a runaway in page zero |
| low | content | title idling at a screen it already finished |
| high | blank | executing fine, not drawing |

A blank 640x200 PNG is **~3790 bytes**. Anything within a few hundred bytes of
that is a line or two of text, not a working screen — treat 3976 or 4056 as
"near-blank", not as a render.

### Counting honestly

The raw image count is **not** a title count. Before quoting a pass rate,
subtract:

* **boot sectors that cannot boot** — some deliberately halt with
  `ORCC #$50 / STA $fd03 / BRA *`, others are a single repeated byte ($e5
  blank-format fill, $00, $ff). `vsim/sweep/bootsector.py` identifies these
  straight from the image.
* **secondary disks of multi-disk sets** — data and scenario disks that were
  never bootable.
* **save / user disks** — likewise.
* **`[b]` images** — known-bad dumps.
* **titles MAME's own software list marks unsupported** — see
  `docs/REFERENCE.md`.

Quoting the raw figure badly overstates the failure rate.

### Comparing two sweeps

**Only compare runs with the same frame count.** Both the screenshot frame and
`main/frame` depend on it:

* the screenshot is taken at a fixed frame, so two runs shoot at different
  points in each title's life
* `main/frame` is an average over the whole run, so a title that works and then
  stalls shows a *lower* average in a longer run

Comparing a 1500-frame run against a 700-frame baseline manufactured six
regressions that did not exist, and hid a gain (Greed Disk 1 read as
`4781 -> 3790`; at matched frames it was `4781 -> 5417`).

A change that alters **timing** breaks fixed-frame comparison even at equal
frame counts, because every title's boot shifts. After such a change, re-check
each apparent regression at a longer frame count before believing it — three
"regressions" once turned out to be large gains that simply had not drawn yet at
frame 680.

### Verifying a suspected regression

Do not argue from rates. A/B it:

```sh
git checkout <pre-fix-commit> -- rtl/FILE.v
cd vsim && make && ./obj_dir/Vemu ... > before.log
git checkout HEAD -- rtl/FILE.v
cd vsim && make && ./obj_dir/Vemu ... > after.log
```

Identical output means the change is not responsible — but see the
measurement traps in `docs/REFERENCE.md` first: identical output is also what a
patch that never reached the binary looks like.

## Driving the reference: keys and a joystick

`refs/local/fm77av_headless` takes the same input options as `vsim`, keyed off
**machine time** rather than an instruction count, because the two machines
share no instruction count and do not even agree on the main CPU's clock.

**The two frame units are not the same length** (superseded claim, corrected:
this said "the frame numbers mean the same thing on both"). A reference frame is
exactly 1/60 s; a vsim frame is a raster frame off the core's video timing,
16 MHz over a 1024 x 262 raster, 59.63740 Hz. So

    reference_frame = vsim_frame * 60 * 1024 * 262 / 16000000 = vsim_frame * 1.00608

+6 frames per 1000 — 4 at the gate's shot frame, 12 at the sweep's 2000, 22 at
3700. It only matters where the picture is still moving, which is exactly the
case trap 49 is about.

```sh
refs/local/fm77av_headless refs/local/fm77av-roms game.d77 60000000 out.png --fm7 \
    --key 700:MID_SPACE:40  --joystick 1200:right+a:600  --shot-every 1500
```

* `--key F:NAME[:HOLD]` — `NAME` is 77AVEMU's own label. The FM-7 has three
  space bars (`LEFT_SPACE`, `MID_SPACE`, `RIGHT_SPACE`) and its function keys are
  `PF1`-`PF10`; there is no `SPACE` or `F1`, and an unknown name is reported
  rather than silently ignored. Modifiers are a **prefix** — `SHIFT+2`,
  `CTRL+C`, `GRAPH+A` — because `FM77AVKeyboard::Press` takes the modifier state
  as an argument; pressing `LEFT_SHIFT` as its own key types the *unshifted*
  character and reads as a keyboard fault in whatever is under test.
* `--joystick F:B[:HOLD]` — `B` is `+`-separated: `up down left right a b`.
* `--shot-every N` — a PNG every N frames, which is how you watch an attract
  sequence instead of guessing at it.
* `--stop-at-frame N` — end the run at machine-time frame N instead of after
  `steps` instructions, so a render can be compared against a vsim screenshot at
  the same instant. `steps` stays as a backstop and the run warns loudly on
  stderr if the backstop is what stopped it. `vsim/sweep/ref-gate.py` uses this
  to render the whole `run_tests.sh` gate into `vsim/shots-ref-77avemu/`; see
  the README there.

**Answer questions about the software on the reference first.** "Which key
starts this game" is a fact about the game, not about our RTL, and asking it on
the core under test conflates "we typed the wrong key" with "the core dropped
the key". The reference is also about fifty times faster: 200 M instructions is
about ninety seconds, where the same machine time in Verilator is hours.

### What that immediately settled about Thexder

Thexder **cannot be started by a key or a stick**, and it is not a core problem:

* Its attract loop runs for *minutes* of machine time — title, then credits,
  then back — so a 1500-frame Verilator run only ever sees the first screen, and
  everything looks unresponsive.
* All **100** of 77AVEMU's real key labels were pressed in turn on the
  reference. Not one changes the screen. Pressing later, or hammering a key
  every 300 frames across a 200 M-instruction run, only shifts the animation
  phase.
* It never reads PSG registers 14 or 15 at all — 1686 register writes in a
  Verilator run with a stick held, every one of them tone, noise, envelope or
  amplitude.

### Which titles actually read a joystick

`Port::Read()` stamps `lastAccessTime` and power-on zeroes it, so the driver's
`GAMEPORT` line is free proof that a title polled the stick. Over the 67 AV
images, **20 do**:

```
Deep Forest · Digital Devil Story · Dragon Buster · Gambler Jikochuushinha
How Many Robot · Kugyokuden · Luxsor 1+2 · Mugen Senshi Valis 1+2
Pro Yakyuu Fan · Psy-O-Blade · Reviver · Shounen Mike no Hitoritabi
The Return of Ishtar (both dumps) · The Tower of Druaga (both dumps)
Woody Poco · Urusei Yatsura
```

Six of those read **port 1** as well, so they are the two-player tests.

**Test the joystick on an FM77AV title, not an FM-7 one.** 77AVEMU routes the
gameport only through the `$FD15`/`$FD16` YM2203 window
(`fm77avsound.cpp:182-186`); a read of PSG register 14 through the FM-7's
`$FD0D`/`$FD0E` window returns the AY's own register (`:428`) and never reaches
the port. CaptainYS says why in `fm77avkeyboard.h`: gamepads became common
"after Fujitsu released YM2203C expansion card". On a base FM-7 the stick is a
minority path — most games read the keyboard — which is a fact about the
machine, and it is why hunting for an FM-7 joystick title kept coming up empty.

## The FM77AV breadth sweep

```sh
cd vsim/sweep
./av-sweep.sh /tmp/avsw 8 2000            # outdir, jobs, frames
python3 classify.py /tmp/avsw/shots /tmp/avsw/results.tsv
```

The AV set is picked out of `software/D77` by `(FM77AV)` in the file name --
that is how the collection marks the AV release of titles that also shipped for
the FM-7. Ys, Silpheed, Dragon Buster and others exist as both, and **the AV
disk will not boot as an FM-7**, so `sweep_one.sh` takes a `MACHINE` env var.
Sweeping the AV set without it reports a uniform "nothing boots", which reads
as a core failure rather than as the wrong switch.

### Looking at all 68 of them at once

```sh
cd vsim/sweep
./av-sweep.sh  renders 8 2000        # this core, one PNG per title
./ref-sweep.sh renders 6             # 77AVEMU, the same list
./gallery.py   renders               # -> renders/gallery.html
```

`renders/` is gitignored: the PNGs are regenerable and they change every time a
title is fixed, while the numbers worth keeping go in `vsim/sweep/*.tsv`.

The page pairs each title's two renders, sorts least-agreeing first, and gives a
per-title agreement figure computed in **palette-nibble space** — necessary,
because the two emulators expand a 4-bit gun level differently and a byte-exact
comparison calls every non-black pixel different. It also resamples to the
logical grid: this core emits 640x200 always (320 mode is pixel-doubled by
design), the reference emits 320x200 in 320 mode and line-doubles 640x200 into a
640x400 buffer, so comparing raw scores two identical pictures as unrelated.

**The agreement figure is not a pass mark**, and the page says so. The two
machines stop at points chosen independently, so a title mid-fade or mid-attract
differs for no reason worth chasing. Two worked examples of why the eye beats
the number here: Dragon Buster scores badly and is *correct* — its cave screen is
grey on both machines and our greys match the reference nibble for nibble, we
are simply not as far into the game; and Luxsor renders 98% coverage in 369
colours and is *wrong*.

### Screenshot size is not enough triage here

The FM-7 sweep classifies on PNG size: ~3790 bytes is blank. That does not
survive contact with the AV, which has a third state:

| bytes | what it is |
|---|---|
| ~3790 | blank |
| **~5182** | **the AV F-BASIC banner** — the disk did *not* boot and the machine fell through to BASIC. By size alone this reads as "renders something". |
| 4000+ | could be either a real frame or a near-blank with a line of text |

`classify.py` separates them on coverage and colour count, which is what
actually distinguishes them: the banner is one colour over ~2% of the screen, a
320x200 game frame has many colours over a large area. It merges the
instruction rates back in, because a screenshot still cannot tell "idling at a
finished screen" from "crashed" -- that part of `sweep.sh`'s method is
unchanged.

### AV titles need far more frames than FM-7 titles

The 2019 demo needs ~560 frames just to reach its gradient, and games do
considerably more disk loading before drawing anything. **A blank at 700 frames
is not evidence of a broken title.** Sweep the AV set at 2000 and compare
against the 700-frame run before calling anything a failure.

## Joysticks

They hang off the PSG's I/O ports, so they ride on the same `$fd0d`/`$fd0e` bus
handshake the sound does — a change to one moves the other. `make sound-test`
covers the register path; the integration proof is the F-BASIC sequence from
`docs/IO_MAP.md`, driven in the simulator:

```sh
./obj_dir/Vemu --headless --bootrom 0 --key-hold 3 --joystick 300:up+a:4000 \
    --key 400:'poke64782,15' --key 484:@RETURN ...      # see IO_MAP.md for the full line
```

With stick 0 held up+A it prints **238**. `make DEBUG_JOY=1` adds a line per
selection and per read (`JOYSEL port_b=20 -> stick 0`, `JOYRD ... -> ee`), which
is what to look at when the screen says 255.

**`--joystick-hold` only affects `--joystick` options that come after it.** A
press with the default 10-frame hold is released almost immediately, so a stick
"does nothing" in a test that reads it hundreds of frames later. Prefer the
per-action form, `--joystick <frame>:<buttons>:<hold>`, which cannot be ordered
wrongly. Reading 255 (`$ff`, "no stick selected") when the trace shows the
selection succeeded means exactly this: the stick was released, not misrouted.

## The kanji ROM lives in SDRAM

At 128 KB it was 128 M10K, 23% of the device, and it is the only ROM that could
move: everything else is fetched by a CPU every bus cycle or by the raster every
character cell. It arrives as `releases/boot.rom` on **ioctl index 0**, which the
MiSTer framework uploads at core start, so it needs no user action.

Nothing in the regression suite reads the kanji window, so `make kanji-test` is
the only thing covering it -- the download, the SDRAM base address, the arbiter
and `KANJI.v`'s prefetch:

```sh
cd vsim && make kanji-test          # samples glyph words, compares with the file
```

It has already earned its place twice. `ioctl_index[15:6] == 0` (copied from
another core) matches indices 0-63, which includes the **tape** at index 1 and
would have written tape bytes to the kanji base; and `vsim/sim.v` instantiates
the SDRAM controller with `.we ( tape_download & ioctl_wr )` where the FPGA top
has the operands reversed, so an edit missed it and kanji was never written at
all. Both look like nothing without a readback.

The simulator loads `../releases/boot.rom` by default; `--boot-rom <file>`
overrides it.

## Listening to the sound

Nothing in the suite checks audio, and for the life of the project nothing ever
had: the simulator only clocked `audio.Clock()` when a window was open, so every
headless run produced silence by construction. Both PSG bugs — the `$fd0d`/
`$fd0e` handshake being backwards, and a 28-bit mix expression truncated to 16 —
survived because of that gap.

```sh
cd vsim
make sound-test                                    # directed: does a register write make sound?
./obj_dir/Vemu --headless --bootrom 0 \
    --disk '../software/D77/Thexder (Game Arts).d77' \
    --stop-at-frame 900 --wav /tmp/thexder.wav
```

The run summary also prints a census that answers "is anything reaching the
DAC" without opening the file:

```
audio  : PSG max 10238 (nonzero 233965093)  core_audio max 10238  AUDIO_L max 10238
PSG bus: $fd0d writes 4096  $fd0e writes 2048  cen ticks 18130034  cmd[1:0] seen 0 2 3
PSG channels: dac_a max 4095  dac_b max 4095  dac_c max 2048
```

**A PSG max of 0 with non-zero `$fd0e` writes is the signature of a broken bus
handshake** — the software is programming the chip and nothing is landing. That
is exactly what a whole run of Thexder looked like before the fix.

The chip is a `jt03` (jotego/jt12) and serves both machines: the FM-7's PSG and
the FM77AV's YM2203 are the same block, addressed through `$fd0d`/`$fd0e` with
the command masked to two bits and, on the AV, `$fd15`/`$fd16` with all four.
`cmd[1:0] seen` is the low half of that command register — 2 is "write data" and
3 is "latch address", so a run showing only 0 never programmed anything.

`make sound-test` also covers the AV window directly, including the status read
(command 4) that Ys spins on: an undecoded `$fd16` returns `$ff`, bit 7 reads as
permanently busy, and the game never leaves its wait loop.

## Differential VRAM comparison against 77AVEMU (FM77AV)

A screenshot says the picture is wrong. It does not say whether the raster reads
VRAM wrongly or whether the wrong bytes are in VRAM, and those two have nothing
in common as bugs. Dump both machines' video memory and diff it.

```sh
# Reference. Prebuilt in refs/local -- see tools/README-77AVEMU.md if missing.
FM77AV_VRAM_DUMP=/tmp/ref-vram.bin refs/local/fm77av_headless \
    refs/local/fm77av-roms path/to/image.d77 20000000 /tmp/ref.png

# This core, at a chosen frame.
cd vsim
FM7_VRAM_DUMP=/tmp/ours-vram.bin ./obj_dir/Vemu --headless --machine fm77av \
    --disk path/to/image.d77 --stop-at-frame 2050 --av-dump-frame 2000
```

Both files are 98304 bytes in the same layout: **bank 0 then bank 1, each blue,
red, green, each gun two 8 KB halves**. Diff them slice by slice — 12 slices of
8 KB. Identical slice *contents* sitting in different banks is a page-select
bug, not a raster bug.

The ROM directory for the reference is `refs/fm77av.zip` unzipped with
upper-case names (`FBASIC30.ROM`, `INITIATE.ROM`, `SUBSYS_A/B/C.ROM`,
`SUBSYSCG.ROM`, `KANJI.ROM`).

**Align on what is on screen, not on a frame number.** This core reaches the
2019 demo's fully-typed title around frame 2000; the reference reaches it in
20 M instructions. Diffing at mismatched points shows the untyped text as a
whole-plane difference.

`FM7_PAL_DUMP` writes the FM77AV analog palette as 4096 lines of
`index blue red green`, taken at the same `--av-dump-frame`. It is the read-back
that catches a palette which is accepting no writes at all — replay the
`$fd30-$fd34` writes out of a `--trace-io` log and diff the two tables. That is
how the dead `$FD30` decode was found, and "every entry still equals its index"
is what a write-only register file looks like.

### Comparing pixels with 77AVEMU: use nibbles, not bytes

The two disagree on the DAC. `PAL.v` expands a 4-bit gun level with CSP's
`{n,$F}`, 77AVEMU replicates the nibble; every non-black pixel therefore differs
and a byte-exact comparison reports 100% mismatch whatever the truth is. Both
keep the level in the **high** nibble, so shift each side right by 4 first.

Sweep a horizontal offset while you are at it. A whole-picture shift is
invisible to this project's own screenshots — they are the core's output, so
they shift with it — and it presents as colour noise on dithered art, not as a
displacement.

### Checking the raster phase without a reference at all

```sh
cd vsim
FM7_VRAM_DUMP=/tmp/v.bin ./obj_dir/Vemu --headless --machine fm77av \
    --disk '../software/D77/Wizardry IV (FM77AV) (Disk A).d77' \
    --stop-at-frame 620 --av-dump-frame 600 \
    --screenshot 600 --screenshot-name /tmp/s.png
../tools/raster_phase.py /tmp/v.bin /tmp/s.png          # add --320 for 320 mode
```

It predicts each pixel's palette code from the core's own VRAM and asks which
horizontal offset lets a single palette explain the screen. The answer must be
`dx=0`; anything else is a displaced picture. Use a title that is *static* at
the dump frame and does not scroll (Wizardry IV for 640, Deep Forest for 320).

**It only discriminates well in 640 mode.** Eight colour codes over a whole
screen means a wrong offset has to reuse a code on a differently-coloured pixel,
and it does, constantly — the spread is 99% at the right offset against 89-94%
either side. In 320 mode there are thousands of codes, most of them nearly
unique to one pixel, so *every* offset scores about 99.97% and the peak means
little. Check 320 alignment against 77AVEMU instead, and note that a one-pixel
error there is visible as the doubled pair disagreeing with itself rather than
as a displacement.

**Measure the assembled core, not a bench over its modules.** A standalone
Verilog bench instantiating MB60H010 + CRTRAM + PAL, wired as `core.v` wires
them and sampled as `sim.v` samples, still reported the 640-mode picture one
column left of where the assembled core actually put it — it agreed with the
reference on 320 and disagreed on 640, and would have baked in a one-pixel
error. It is deliberately not in the tree.

`--trace-av-video [file]` adds the AV video write log: main-CPU aperture writes
(`AVVRAM`), sub-CPU VRAM writes (`SUBVRAM`), drawing-ALU read-modify-writes
(`ALUW`, with the bytes read and written), main-CPU MMR writes into the sub I/O
page (`MMRSUBIO`, with the sub-halt state) and the sub CPU's own `$D410-$D42B` /
`$D430` writes (`SUBDRAW`). It is off by default because it fires on nearly
every bus cycle of an AV run.
