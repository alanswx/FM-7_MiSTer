# Start here

Orientation for picking this branch up cold. Detail lives in
`docs/CONTINUATION.md` (open work, per-title), `docs/REFERENCE.md` (measurement
traps — read section 5 before trusting any number) and `HARDWARE-HANDOFF.md`
(the FPGA side). `CLAUDE.md` has the documentation rules; follow them.

Branch `fdc-d77-support`, pushed to `alanswx`. Working tree clean, gate green.

## State in one screen

Against 77AVEMU over the 68-image FM77AV set (`vsim/sweep/`, both runs at 2000
frames, canonical shot at frame 1980, so the two sides are the same instant):

| verdict | before | after |
|---|---|---|
| CORE-BLANK — reference draws, this core does not | 9 | **6** |
| CORE-WORSE | 3 | 3 |
| TEXT-ONLY | 9 | 9 |
| BOTH-BLANK — neither draws; mostly data/scenario disks, not our bug | 28 | 26 |
| MATCH | 16 | **19** |
| REF-WORSE — this core draws and the reference does not | 2 | 4 |

`results-av-f2000-nmi-secreg.tsv` is the after; `results-av-f2000-postfix.tsv`
the before. **Neither is a valid baseline for a future change** — see trap 57.

Six titles gained MATCH: both FM77AV demo images, Luxsor disk 2, Pro Yakyuu Fan
disk A, and — unplanned — Shounen Mike no Hitoritabi and Woody Poco disk 1. The
last two came free with the systemic fixes, which is the argument for fixing a
CPU or controller bug rather than a title.

## The two RTL fixes, and why they mattered

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
| `make DEBUG_FDC=1` | `WDMATCH` (every sector the controller matched), `WDNOMATCH`, `WDDROP`, and a `SECREG` probe printing every sector-register change with the instance name. |

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

1. **FM Sound Editor** — FDC exonerated by measurement (reads byte-identical to
   the reference, zero NOMATCH). It diverges on a *computed* value: the twelfth
   `$FD88` write maps logical page 8 to `$24` where the reference maps `$38`, and
   it then executes at `$863B` inside that page into a `NEG <$00` sled. Find what
   computes that value.
2. **Luxsor disk 1** — see below. Deep, and five hypotheses have died.
3. **Daiva Story 2 disk A** — reads MATCH → CORE-BLANK in the sweep. **Check
   whether it is the same story as Luxsor disk 1 before assuming it is broken.**
4. **Shounen Mike** at 85.79 %; **Mahjong Kyou Jidai** untouched.
5. **Per-row gate shot frames.** `av-kohakuiro` and `av-wizardry4` are attract
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
reference's one-position pre-side-effect log shift), the TWR window (640 bytes,
zero differ), the boot ROM's seek logic, and the MMR (all four segment maps
byte-identical, page 6 → `$36` on both).

The live lead: the reference rewrites the loader's dispatch table at `$5090`
twice between frames 240 and 300 and this core never does. Bracketing with
`FM77AV_CPU_DUMP` at a spread of frames works and costs about a minute a sample.

## How to not waste the first hour

These cost real time this session. `docs/REFERENCE.md` traps 55–63 have the full
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
