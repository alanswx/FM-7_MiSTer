# Start here

Orientation for picking this branch up cold. Detail lives in
`docs/CONTINUATION.md` (open work, per-title), `docs/REFERENCE.md` (measurement
traps — read section 5 before trusting any number) and `HARDWARE-HANDOFF.md`
(the FPGA side). `CLAUDE.md` has the documentation rules; follow them.

Branch `fdc-d77-support`, pushed to `alanswx`. Working tree clean, gate green.

## State in one screen

Against 77AVEMU over the 68-image FM77AV set (`vsim/sweep/`, both runs at 2000
frames, canonical shot at frame 1980, so the two sides are the same instant).
`results-av-f2000-shared-window.tsv` is the after, `results-av-f2000-nmi-secreg.tsv`
the before — the two are one session apart, so the difference is exactly the
fixes below:

| verdict | before | after |
|---|---|---|
| CORE-BLANK — reference draws, this core does not | 9 | **4** |
| CORE-WORSE | 3 | **2** |
| TEXT-ONLY | 9 | 9 |
| BOTH-BLANK — neither draws; mostly data/scenario disks, not our bug | 28 | 26 |
| MATCH | 16 | **22** |
| REF-WORSE — this core draws and the reference does not | 2 | 4 |

Gained: FM Sound Editor, Daiva Story 2 disk A, Mahjong Kyou Jidai disk 1 — the
last matching 77AVEMU on **all 98,304 VRAM bytes**.

What is left on the actionable list, worst first:

| ours | ref | title |
|---|---|---|
| 0.0 | 27.3 | Luxsor disk 1 — runaway into `$fdxx`, IRQ asserted never taken |
| 6.8 | 10.2 | Wizardry IV disk A — **probably trap 49, not a real row**; it renders throughout and only the fixed 1980 sample lands mid-transition, and the gate passes it byte-identically at 600. Check other frames before working on it. |
| 0.1 | 9.6 | Little Box disk A — main CPU at 816 instr/frame against a healthy ~7400 |
| 0.0 | 9.6 | In the Dream disk A — sub 65% halted, BUSY stuck at 1 |
| 21.1 | 85.3 | How Many Robot disk 0 — uninvestigated |
| 10.0 | 74.7 | Gambler Jikochuushinha — uninvestigated |

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

These cost real time this session. `docs/REFERENCE.md` traps 55–66 have the full
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
