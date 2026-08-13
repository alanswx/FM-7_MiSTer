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
PSG bus: $fd0d writes 4096  $fd0e writes 2048  cen ticks 18130034  {bdir,bc1} seen 00 10 11
PSG channels: dac_a max 4095  dac_b max 4095  dac_c max 2048
```

**A PSG max of 0 with non-zero `$fd0e` writes is the signature of a broken bus
handshake** — the software is programming the chip and nothing is landing. That
is exactly what a whole run of Thexder looked like before the fix.

## Differential VRAM comparison against 77AVEMU (FM77AV)

A screenshot says the picture is wrong. It does not say whether the raster reads
VRAM wrongly or whether the wrong bytes are in VRAM, and those two have nothing
in common as bugs. Dump both machines' video memory and diff it.

```sh
# Reference. Build Mutsu first (tools/README-77AVEMU.md), then:
FM77AV_VRAM_DUMP=/tmp/ref-vram.bin /tmp/fm7-77avemu-build/fm77av_headless \
    /tmp/fm77av-roms path/to/image.d77 20000000 /tmp/ref.png

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
