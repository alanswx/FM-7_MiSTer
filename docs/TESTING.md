# Testing

Two levels: an 8-row regression suite that must stay green, and a breadth sweep
over the whole floppy collection.

## The regression suite

```sh
cd vsim
./run_tests.sh                 # every test
./run_tests.sh basic           # only tests matching a substring
BLESS=1 ./run_tests.sh         # accept current behaviour as the new reference
FRAMES=1200 ./run_tests.sh     # run longer
```

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
new `.d77` into `../software` does not break the suite.

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
