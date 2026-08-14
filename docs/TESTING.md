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

## The breadth sweep

```sh
cd vsim/sweep
./sweep.sh <outdir> [jobs] [frames]        # e.g. ./sweep.sh /tmp/sw 12 1500
```

Extracts the Neo Kobe floppy collection, runs every `.d77`, and writes
`results.tsv` with `MAIN_PF  SUB_PF  PNG  IO  NOTES  TITLE`.

Recorded results live in `vsim/sweep/*.tsv` and are the baseline for per-title
comparison. Join on `TITLE`.

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

`--trace-av-video [file]` adds the AV video write log: main-CPU aperture writes
(`AVVRAM`), sub-CPU VRAM writes (`SUBVRAM`), drawing-ALU read-modify-writes
(`ALUW`, with the bytes read and written), main-CPU MMR writes into the sub I/O
page (`MMRSUBIO`, with the sub-halt state) and the sub CPU's own `$D410-$D42B` /
`$D430` writes (`SUBDRAW`). It is off by default because it fires on nearly
every bus cycle of an AV run.
