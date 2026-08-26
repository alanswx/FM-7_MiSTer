# Where to pick this up

Open work on the two media paths, disks and cassettes, with what is already
known so nobody re-derives it. Everything here is measured unless it says
otherwise. `TODO.md` holds the wider board; this file is the media detail.

Method that has been carrying every investigation: run the same title on this
core and on 77AVEMU, and diff the main-CPU `$FDxx` streams with
`tools/seqdiff.py`. The two machines match port, value AND program counter for
tens of thousands of accesses, so the first divergence is a single readback and
can be fixed one at a time. Read the tool's docstring before trusting its
output -- only the first divergence or two are real.

---

## Disks

### Fixed recently, for context

* `$fd13`'s sub-CPU reset now sets BUSY (`2fbd296`). Took Shounen Mike from 0.1%
  coverage in 2 colours to **99.9% in 200**, agreement 0.10% -> 85.79%. It had
  been reverted once because it appeared to break Valis disk 2; that regression
  was the CPU clock, and with the clock fixed Valis is unchanged at 98.32%.
* The CPU clocks (`6a7030e`): both CPUs at 8 MHz, plus the AV's MMR-conditional
  drop. Hardware-confirmed.
* The scroll-offset aperture and `$D430` b2 fine scroll (`c50a852`), the ALU
  register aperture (`b7df560`), the absent-drive busy period (`3546ea4`), and
  four main-I/O readbacks (`794d016`, `9af9c4f`).

### Open, highest value first

**1. Shounen Mike is at 85.79%, not 100%.** The remaining 14% is unexamined. Its
`$FD05` handshake was the breakthrough; look next at what it does after the sub
CPU restarts.

**2. Pro Yakyuu Fan disk A is FIXED. FM Sound Editor is not, and its cause is a third,
unrelated one.**

*Pro Yakyuu Fan disk A -- FIXED.* The SECTOR register belongs to the CONTROLLER, not to a
drive. A real FM-7 has one WD1793 whose track/sector/data registers are shared by every
drive; this core instantiates one `wd1793` per drive, each with its own register file, so
a sector-register write made while another drive is selected never reaches the drive that
needs it. The loader keeps its place with `LDA $FD1A / INCA / STA $FD1A` at `$FE65` and
the boot ROM's drive scan selects drive 1 in the middle of it, so drive 0's register was
one behind and sector `12:0:1` was never read. Every later byte then landed 1024 out of
place, which is why the driver it builds at `$E142`/`$E18A` came out as garbage and never
reached the `STA <$02` that enables its timer IRQ. `FDC.v` now mirrors sector-register
writes to both instances -- addr 2 only. Frame-900 PNG 3790 (blank) -> 12258, real
graphics.

*FM Sound Editor -- NOT fixed, and the FDC is exonerated.* With the same matched-window,
same-instrument comparison (`WDMATCH` here, `--trace-fdc` there), **its read sequence is
byte-identical to the reference** for every read in the window -- including the
`1:12:7:2:13:8:3:14:9...` interleave across its 16-sector tracks -- with zero NOMATCH. It
gets all its data correctly. It then diverges on a COMPUTED value:

```
$FD88 writes (logical page 8 mapping)
  ours: 38 38 38 38 38 00 01 0f 38 38 00 [24]
  ref : 38 38 38 38 38 00 01 0F 38 38 00 [38] 00 38 00 38 07 06 07 38 ...
```

Eleven identical writes, then this core maps page 8 to physical `$24` where the reference
maps it to `$38` -- and immediately executes at `$863B`, INSIDE that page, into a
`NEG <$00` sled, where it stays. Its sub CPU is healthy and it services zero timer IRQs
because it never gets that far. It does reach `$F920` (so part of the RAM-resident code
runs) but never `$F650`.

*Next for it:* find what computes the 12th `$FD88` value. The write is at a known PC in
this core's trace; trace the main CPU across it and compare the inputs. Do NOT go back to
the FDC -- it is measured clean.

**3b. FIXED (Luxsor disk 2): the 6809 core never masked NMI after reset.**

`mc6809i.v` released the NMI mask on `s != s_nxt`, and `CPUSTATE_RESET` assigns
`s_nxt = $FFFD` -- so the reset sequence cleared the mask on the cycle that set it, and
NMI was never masked after reset at all. Per the 6809 spec it must stay masked until S is
LOADED, which is what protects the window between reset and the init's `LDS`.

Harmless on a cold boot; fatal on a WARM reset, which is what the AV's `$FD13`
sub-system reset is -- the display NMI is already running. Luxsor writes `$FD13` at
`pc=$E48A` on frame 27; the sub restarts at `$E000`; an NMI lands during its
`$D000-$D35F` clear loop before the init's `LDS`; the 12-byte push goes to `S=$FFFD`
(ROM) and is discarded; the handler returns through a `PULS` reading ROM and the sub
walks a `NEG <$00` sled through VRAM from `$8DE0` for the rest of the run.

The knock-on is why this was invisible from the main CPU. The sub's periodic timer
handler still worked, and it ends `STB $D381` / `BITA $D404` -- the command-complete
notify -- so every tick set `attn_pend` and asserted the main CPU's FIRQ. `attn_pend`
clears only on a main-CPU `$FD04` read, and the main read `$FD04` exactly twice, both on
frame 6. FIRQ therefore sat asserted from frame 27, and when the loader unmasked at frame
370 (`PULS CC` at `$eea4`) it instantly took that stale FIRQ into `$3B1A` instead of the
timer IRQ at `$E5A9`.

Fix: `if ((s != s_nxt) && (CpuState != CPUSTATE_RESET))`. Measured on Luxsor, 920 frames:
sub `$D404` notifies 24 -> 0; main `$FD03` reads 0 -> 18,806 (reference 22,554);
frame-900 PNG 3,790 -> 25,250, and it is the GAME -- playfield, LUXSOR logo, score and
status panels. No regression: av-demo 5805/6767, Wizardry IV 12522/11720 and Kohakuiro
unchanged.

**FM Sound Editor and Pro Yakyuu Fan disk A are NOT fixed by it** and remain blank
(3812 at frame 700, 3790 at 900). They share the zero-timer-IRQ symptom but, as item 2
records, they fail in different places -- Sound Editor runs away into a `NEG <$00` sled
at `$863D` on the MAIN CPU, Pro Yakyuu Fan repeats its whole drive scan seven times.
Re-measure both from scratch now that the sub CPU survives its reset: the old traces
were taken with a wrecked sub and every downstream conclusion from them is suspect.

*Why nothing caught the NMI bug:* no gate test performs a warm reset with an NMI source
live, and neither F-BASIC nor the 2019 AV demo takes a timer IRQ at all.

**3c. Full 68-title AV sweep after the NMI and sector-register fixes.** Both sweeps at
2000 frames, canonical shot at frame 1980, so the two sides are the same instant and
comparable (`vsim/sweep/results-av-f2000-nmi-secreg.tsv` against
`results-av-f2000-postfix.tsv`).

| verdict | before | after |
|---|---|---|
| CORE-BLANK (reference draws, this core does not) | 9 | **6** |
| CORE-WORSE | 3 | 3 |
| TEXT-ONLY | 9 | 9 |
| BOTH-BLANK | 28 | 26 |
| MATCH | 16 | **19** |
| REF-WORSE | 2 | 4 |

*Gained (6 to MATCH):* the two FM77AV demo images, Luxsor disk 2, Pro Yakyuu Fan disk A,
**Shounen Mike no Hitoritabi** and **Woody Poco disk 1**. The last two were never
investigated for this -- they came free with the systemic fixes, which is the point of
fixing a CPU or controller bug rather than a title.

*Partly gained:* Mahjong Kyou Jidai Special disk 1, CORE-BLANK -> CORE-WORSE.
Kugyokuden disk 1 and World Golf II disk 1 went BOTH-BLANK -> REF-WORSE, i.e. this core
now draws where neither machine did.

**BISECTED: Luxsor disk 1's regression is `c3b270c`, the cycle-steal change -- and it is
NOT any one of its four files.** Every step measured, screenshot at frame 1980
(blank = 3790, good = 12214):

| build | result |
|---|---|
| session start `d09fe5d` | **12214** renders |
| HEAD (all four fixes) | 3790 blank |
| sector-register mirroring | exonerated -- its 15 sector reads are byte-identical to the reference, zero NOMATCH |
| NMI mask reverted | 3790 -- not it |
| `$FD1D` reverted | 3790 -- not it |
| **cycle-steal reverted (4 files)** | **12214 -- THIS IS THE CAUSE** |
| raster window widened 2/8 -> 4/8 | 3790 -- **not a threshold**, any cycle-steal breaks it |
| `SCASSEL` restored in `alu_access` | 3790 -- not ALU aperture-port displacement |
| `SVWEn` back to blanking-only | 3790 -- not sub writes during active display |

So it is the `SCASSEL` widening in `MB60H010.v` itself, and none of the three consequential
changes that ride on it.

**AND IT IS NOT A REGRESSION AT ALL -- cycle-steal made this core MORE correct and
unmasked a pre-existing fault.** `seqdiff` against the reference, both builds, same
machine-time window:

| build | first divergence from 77AVEMU |
|---|---|
| cycle-steal REVERTED (renders!) | access 20,604, `R $FD05 FE` against `$7E` |
| HEAD, cycle-steal ON (blank) | **none** -- matches the reference there |

That `$FD05` b7 difference is the sub-BUSY race. **The build that RENDERS is the one that
LOSES it**; the build that matches the reference goes blank. Disk 1's old picture was an
artifact of losing a race, exactly like `$FD00` b0 on disk 2 -- REFERENCE.md trap 55,
written earlier in the same session for the same title.

With HEAD, every `seqdiff` divergence on this disk is the benign `$FED6` data-register
read-back test. The main-CPU `$FDxx` stream matches the reference completely and the
screen is still blank, which is where disk 2 was before the NMI fix.

**Where it actually fails, `WDMATCH` against `--trace-fdc` over matched windows** (ours
frame 1200, reference 1207):

```
read #142   both:  39:0:3 39:0:4 39:0:5 39:1:1
read #143   ref :  4:0:1 4:0:2 4:0:3 4:0:4 4:0:5 4:1:1 ... 5:0:1   <- carries on loading
read #143   ours:  16:0:5 16:1:1 16:1:2 16:1:3  16:0:5 16:1:1 ...  <- retries forever
```

555 reads here against 183 there by the same frame. **The first 142 reads are identical**,
zero `WDNOMATCH`, and the transferred data matches ~99.8% across 40,000 bytes (the residual
being the reference's one-position pre-side-effect log shift at run boundaries -- the same
figure Pro Yakyuu Fan showed when its streams were effectively identical).

So: same sectors, same bytes, no read failures -- and then the loader picks a different
next track and loops on four sectors of track 16 for the rest of the run.

**Traced to the exact instruction.** At frame 488 the boot ROM's read entry runs

```
$FE89  LDU #$FFE1     ; per-drive tracked head position table
$FE8C  LDB $FFE8      ; drive number
$FE8F  LDA B,U        ; table[drive] -> $10 = 16
$FE91  STA <$19       ; -> $FD19 track register
$FE93  LDA 4,X        ; DESIRED track from the caller's block, X=$5082 -> $10
$FE95  CMPA B,U       ; equal, so no seek is even needed
```

`$FFE1+drive` is the boot ROM's tracked head position and it is written only at `$FE99`,
from that same `4,X`. **Both the tracked position and the requested track are 16, and they
agree** -- so the boot ROM and the FDC are doing exactly what they are told. The number 16
comes from the caller's parameter block at `$5086`, filled by the TITLE's own loader.

**ROOT CAUSE: the loader's dispatch table at `$508C` is corrupted.** Traced the whole
chain, every step measured:

```
$5044  LDA $0043,PCR   ; block counter at $508B = $21 = 33
$5048  LSRA / ROLB     ; track = 33>>1 = 16, side = 33&1 = 1
$504A  STA $0038,PCR   ; -> $5086 track, $5088 side
```

and the counter itself comes from a 4-byte-per-entry TABLE at `$508C`:

```
$500D  LEAY $007B,PCR  ; Y = $508C
$5011  LSLB / LSLB     ; index = B*4, B=8 -> $20
$5013  LEAY B,Y        ; Y = $50AC, entry 8
$501B  LDA 1,Y         ; $20 -> the block counter -> track 16
```

Comparing `--dump-shadow` against `FM77AV_CPU_DUMP` at a matched frame (ours 485,
reference 488), **8 of the table's 12 entries differ and 106 bytes differ across
`$5000`-`$50FF`**:

| entry | ours | reference |
|---|---|---|
| 0 | `31 07 02 01` | `31 07 02 01` same |
| 1 | `23 01 b4 c6` | `00 08 01 0a` |
| 2, 3 | | same |
| 4 | `12 d7 1e c6` | `31 10 01 03` |
| 5 | `57 d7 1e 16` | `39 12 03 04` |
| 6 | `01 a1 a6 e4` | `00 15 04 06` |
| 7 | `81 03 26 0b` | `00 1a 03 08` |
| **8** | `31 20 05 01` | `31 20 05 01` **same** |
| 9, 10, 11 | | differ |

The reference's entries are a coherent progression -- second byte `08 10 12 15 1a 22`;
ours are noise in those slots. **Entry 8, the one this core happens to index, is intact**,
which is exactly why the track-16 reads succeed and loop forever: the core is faithfully
executing a valid entry of a corrupted table. Nothing downstream is broken.

*Next, and it is a narrow question:* what corrupts `$5000`-`$50FF`? The sector DATA is
right -- the first 142 reads are identical to the reference and the transferred bytes match
~99.8% over 40,000. So either the loader is written to the wrong ADDRESS, or something
overwrites it after loading. `--trace-mem 5090-50bf` from frame 0 will name the writer, and
whether the bad bytes ever arrive correctly and are then clobbered.

*So the fault is in the title's loader, which computes track 16 where the reference
computes 4, having read byte-identical data up to that point.* The next step is to find
what the loader at `$50xx` uses to compute it -- `--trace-mem 5080-508f` across frames
480-490 will show what fills the block and from where. Note the loader lives in RAM loaded
from this same disk, so `--dump-shadow` against `FM77AV_CPU_DUMP` at a matched frame will
say whether the two machines even have the same loader code at that address.

**The obvious explanation is DISPROVEN, do not re-propose it.** "The sub CPU is now too
fast" fails twice over: 77AVEMU has NO CRTC halt at all (`CRTCHaltsSubCPU = false`), so its
sub runs faster still and it renders this disk; and measured here the sub halts at frame
274 with cycle-steal against 279 without, essentially identical. **The sub is not where the
difference is.**

**What actually changes is the MAIN CPU.** At frame 500, with cycle-steal it is still in
the boot ROM's sector-transfer loop at `$FF94`-`$FF9C`; without it the main has already
reached the title's own code at `$4087 STA $FD34`, a palette write. And it reads MORE, not
less -- 152 READ SECTOR commands and 155,179 `$FD1B` data reads against 143 and 146,718.
So it is not "slower", it is taking a path that loads more.

*The open question, stated precisely:* **how does a change to SUB-CPU VRAM arbitration
alter the MAIN CPU's path through its own loader?** `SCASSEL` reaches the main side only
through `SBLANKn` (whose value is provably unchanged -- `HBLANKn & VBLANKn` before and
after), `$D430` b7 and `$FD12` b1 (both built from `SBLANKn`), and `video_block`. Find the
main-CPU-visible input that moved. `seqdiff` between a cycle-steal build and a reverted one
on this disk is the obvious next instrument and has not been run.

*The trade is currently net positive and should NOT be reverted casually:* cycle-steal
gained six titles (both demo images, Luxsor disk 2, Pro Yakyuu Fan disk A, Shounen Mike,
Woody Poco disk 1) and lost two. Reverting costs four titles and undoes the fix that made
Luxsor disk 2 work.

***Two REAL regressions, both confirmed across all four sampled frames*** (1100, 1400,
1700, 1980 -- blank at every one, so not the fixed-frame phase artifact of trap 49):

  * **Daiva Story 2 - Memory in Durga disk A**: MATCH -> CORE-BLANK. Was 9.2% coverage.
  * **Luxsor disk 1**: MATCH -> CORE-BLANK. Was 23.0% coverage. Note disk 2 of the same
    title was FIXED in the same session, which makes this the sharpest lead: the same
    loader, one disk gained and one lost.

Both need bisecting across the four RTL changes of this session -- `c3b270c` cycle-steal,
`5431674` `$FD1D`, `6aefa9f` the NMI mask, and the sector-register mirroring. Take Luxsor
disk 1 first for the disk-2 contrast.

*Not a regression, do not chase:* **Wizardry IV disk A** reads MATCH -> CORE-BLANK in the
table and is fine. Its samples are 12222 / 10635 / 10411 / 7143 bytes -- it renders
throughout, and only the frame-1980 canonical lands mid-transition. The gate, which shoots
at frame 600, passes it byte-identically. Trap 49.

**4. Mahjong Kyou Jidai (66.8% reference, 82.7% here, 7.8% agreement).** The one
broken title with no shared cause. Untouched.

**5. `vsim/shots-ref/` is stale, and one of its rows is a BLESSED BLANK.**
`run_tests.sh` reports COUNTERS on every FM-7 row -- main 5555 -> 9387 per frame
-- which is `6a7030e`'s 1.67x speedup, not a regression. Re-bless in its own
commit, saying so, and check the two SCREEN+CNT rows (Thexder, av-demo) are phase
shifts before accepting them.

**`shots-ref/av-kohakuiro.png` is a solid black frame -- and that is NOT a regression.**
*(Superseded claim: "the title regressed on an earlier core and the blank was then
blessed." Disproven by frame-by-frame comparison against 77AVEMU.)* Kohakuiro no Yuigon
disk 1 paints the RIVERHILL SOFT logo at frame **199** and has faded it out by 400; the
reference does the same at its own 200/400 and is then black from 600 through 2400. The
gate photographs at `SHOT_AT = FRAMES - 20` = 600, which is 400 frames after the only
thing the title draws. The core is right and the shot frame is wrong.

`av-wizardry4` is the same story: today's core at frame 400 is **byte-identical** to the
previous blessed shot, and at 800 it is on the same three-portrait "DISPELL" stage
77AVEMU reaches at its 800. The 1.65x clock speed-up moved the attract animation past
frame 600. Not a regression either.

**What IS wrong is the gate's choice of instant.** Both rows are now blessed mid-nothing
or mid-transition, which is a weak reference by `run_tests.sh`'s own stated criterion --
"they render the SAME thing at 700 and 2000 frames". Give those two rows their own shot
frame (Kohakuiro wants ~200) rather than the global `FRAMES - 20`, or drop them for
titles that hold a stable picture. Open work.

One genuine core-vs-reference difference did surface from the new 77AVEMU set: on
Wizardry IV this core overprints the title text and drops the `S) ゲームをはじめる`
line. It is in the OLD blessed shot too, so it is long-standing rather than new.

**Trap for whoever picks this up:** `sweep/results-av-*.tsv` are NOT a valid
baseline for today's tree. They predate the clock commit and several others.
Comparing a change against them attributes pre-existing state to the change --
which happened here: Kohakuiro's blank and Wizardry IV's blobs were both read as
damage from the VRAM arbitration change and are present at HEAD without it.
Build the baseline from the same tree you are changing, in the same session.
And note the second half of that mistake: neither is a REGRESSION either. Both
are the attract animation at a different phase, because the shot frame is fixed
and the core got 1.65x faster. Trap 49 again.

**6. FDC lockouts are not modelled.** FM-Techknow page 180 documents fixed
periods where the MB8877A will not start a read/write: 1 s after motor on, 60 ms
after head load, drive-register write, or step. `FDC.v` has one 4000-cycle busy
period. Possibly relevant to Pro Yakyuu Fan.

---

## Cassettes

**Tapes are NOT broken. Every run ever made here was far too short.**

With the harness fixed (below), the reference on a commercial dump (Fighter) at
60,000,000 steps reaches:

    Searching
    Found: Fighter

`tape_ptr` climbs past 344000. At 8,000,000 steps the same run shows only
`Searching` with `tape_ptr=11220` -- which is the state every previous
investigation stopped at and recorded as failure, including this project's own
`magazines/.../commercial-tape-test/` control and its conclusion that "the
cassette-image decoding/loading path" was at fault. **It was not; the runs were
just short.** A tape load is minutes of machine time, not the ~20 s a disk title
needs, and every tape harness default here is sized for disks.

Budget accordingly: 60M reference steps to reach `Found:`, and on this core the
equivalent is many thousands of frames (a 3700-frame run is nowhere near).

### The harness bug that hid everything

`tools/77avemu_headless.cpp` never bound the data recorder's `Outside_World`.
`FM77AVDataRecorder::Move` dereferences it the moment a tape moves
(`fm77avtape.cpp:260`); it defaults to nullptr and is assigned only in
`FM77AVThread` (`fm77avthread.cpp:45`), the GUI runner this harness does not
use. **Every reference tape run died of SIGSEGV the first time the motor
turned** -- exit 139, truncated log, no screenshot. Disks never touch that path,
which is why it went unnoticed for the life of the project.

Every earlier tape note here concluded "77AVEMU cannot drive tapes". It can.
Fixed, one line, plus enabling 77AVEMU's own `autoLoadTapeFile` autostart, which
triggers on sub-system command `$04` rather than at a fixed instruction count.

### What is true now

On Fighter both machines behave the same way and neither is wrong: they boot
F-BASIC, accept `RUN""`, start the motor and search. The reference, given enough
steps, finds the file. This core has not yet been run long enough to say -- a
16100-frame run was still in flight when this was written; **finish it and
record the result here.**

Numbers from this core on a 3700-frame run, for scale: motor on 87.8% of the
run, 162019 cassette-bit edges, 37% of the image consumed. All healthy, just
unfinished.

### Ruled out, with measurements -- do not re-check

* *The t77 tick.* Corrected to the reference's exact `NANOSEC_PER_T77_ONE = 9000`
  in `e17550c` (was 9.125 us). The decode model now matches the reference in
  every respect -- level rule, duration byte, 2-byte stride -- and tapes still do
  not load.

* *The images.* Commercial dumps (Fighter, Hydlide, Sokoban) fail exactly like
  the generated magazine tapes.
* *The tape generator.* `tools/make_fm7_basic_t77.cpp` already uses 77AVEMU's own
  `T77Encoder::EncodeFromFMFile` via `FM7Lib::TextTo0A0`.
* *Pulse decode.* `DEBUG_TAPE=1` shows clean alternating entries at exactly the
  `0x1A`/`0x30` widths 77AVEMU's decoder defines for off/on bits.
* *The port interface.* `PERIPHERAL.v` matches MAME's `fm7.cpp`: motor from the
  `$FD00` write latch bit 1, tape out on `CN3[4]`, `$FD02` read b7 = cassette in
  with bits 6:1 high.
* *Playback rate.* Forcing the tick from 9.125 us to 8.458 us -- the value that
  hits the manual's 1600 baud -- moves edges 162019 -> 174939 and consumption
  37% -> 40% and changes nothing else.

### The format, from the Fujitsu manual

System Specifications 1.12.4, and section 1b of `REFERENCE.md`: the FM-7 varies
pulse WIDTH, not carrier frequency. Bit 0 is one 2400 Hz wave (416.7 us), bit 1
one 1200 Hz wave (833.3 us); a frame is a start bit, 8 data bits LSB first, and
TWO stop bits; 1600 baud is the average when 0s and 1s are equally common.
`t77_decode.v` names these "1200 baud" and "2400 baud" half-bits, which is the
FSK model and the wrong one for this machine.

**Unresolved, and worth settling first.** If bit 1 is one 1200 Hz wave and bit 0
one 2400 Hz wave, bit 1 must take exactly TWICE as long. In the t77 images
`0x30`/`0x1A` = 48/26 = **1.846**, not 2.0. Either the t77 tick is not linear in
time or the images encode something other than the idealised waveform. Do not
derive a tape clock from the manual's microseconds until this is answered.

### Next steps

**1. `$FD05` b7 diverges at power-on, on the FM-7, at access #2.** This is the
first thing `seqdiff.py` finds on a tape run and it blocks using the tool there
at all:

    frame 0   ours  R $FD05 FE pc=$FE1E      reference  R $FD05 7E pc=$FE1E

b7 is sub-BUSY. `2fbd296` (the `$fd13` reapply) changed FLAGS.v from
`if (~RESETBn) m44_8 <= 1'b0` to setting BUSY at reset, and that reaches **every**
machine, FM-7 included. 77AVEMU sets `subSysBusy=true` on reset too
(fm77av.cpp:624), so the polarity is probably right and what differs is how fast
the sub monitor clears it -- it clears when the sub reaches its idle loop and
reads `$d40a`. **Check this against the FM-7 gate before anything else**:
`run_tests.sh` reports SCREEN+CNT on disk-Thexder and av-demo, and that has been
attributed to the clock commit's 1.67x speedup without anyone separating the two
changes. If `2fbd296` moved Thexder, it needs to be known.

**2. Then the tape diff is usable.** Once power-on agrees, `seqdiff.py` on a tape
run gives the same one-readback-at-a-time loop that has worked everywhere else.

**3. Give tape tests their own time budget.** A tape load is minutes of machine
time; a disk title is about twenty seconds. Sizing tape runs like disk runs is
what produced years of "tapes do not work". Useful figures: snake-apple's tape is
~41000 entries at ~9 us each, about 14 s, so this core reaches END OF TAPE by
roughly frame 900 -- if it has not synced by then it never will, and a longer run
tells you nothing. Fighter is ~146 s of tape and needs ~16000 frames to finish.

**4. Settle the 1.846-vs-2.0 discrepancy** in the recorded bit widths against the
manual's idealised waveform.

### Crash Ball: the dump is good, the fault is ours, and it is NOT the obvious thing

The hardware side reported it failing `Found: CRB` -> `Device I/O Error`, twice,
deterministically. Settled and handed back: **the image is fine** -- the
reference loads and plays it (74.0% coverage in 4 colours, `tape_ptr` ending at
397946 of 1807930) -- and the failure reproduces exactly in simulation, so it can
be chased here.

**Where it fails.** After the header block is found, so the loader is reading a
data block and rejecting it: a checksum or framing case, not sync.

**The obvious lead, and why it is wrong.** Crash Ball's image is measurably
unlike the tapes that work. Level bytes `$81` appear 9574 times against
Sokoban's 192; durations spread across 22-55 where working tapes cluster at
25/27/47/50; and most strikingly it holds **391 zero-duration entries** where
every working tape has one or two:

    Crash Ball  entries=903957  dur==0: 391   dur<=4: ~800
    Sokoban     entries=646766  dur==0: 2     dur<=4: 11
    Space Warp  entries=119251  dur==0: 1     dur<=4: 3
    FM Racer    entries=234159  dur==0: 2     dur<=4: 9

Zero-duration entries ARE handled differently here than in the reference.
77AVEMU computes `dur * NANOSEC_PER_T77_ONE`, so a zero ends at the instant it
begins and `MoveTapePointer`'s while-loop steps past without ever applying its
level (fm77avtape.cpp:99-122); `t77_decode.v` latches it and holds the level for
a full 9 us tick, injecting a transition the tape does not contain.

**Fixing that as described BREAKS working tapes.** Tried: skip the entry, do not
latch `s` or `len`. Crash Ball still fails, and snake-apple -- which loads and
plays today -- degrades to `Found:` followed by garbage characters. Reverted. The
likely reason is that skipping without latching leaves the PREVIOUS level held
for the extra tick, which shifts the following segment rather than removing time.
A correct fix has to consume the entry in **zero** time, which the current
one-entry-per-`clk_9us` structure cannot express; it needs the fetch path to be
able to retire several entries in a single tick, the way the reference's
while-loop does.

So: the zero-duration divergence is real and worth fixing properly, but it has
not been shown to be Crash Ball's cause, and the naive fix is a regression.

### The magazine type-ins

`magazines/Program Pochette 1984 03 (J OCR)/` has seven FM-7 type-in programs
with `program.bas` and `program.t77` each. All seven sit at F-BASIC `Searching` --
but so did every commercial tape until the runs were made long enough, so this
is very likely the same run-length problem and **not** evidence about the
programs or the transcriptions. Re-run them at the budget above before
concluding anything about the listings.

If they need to run before cassettes work, the disk route sidesteps it entirely:
77AVEMU's `D77FileSystem::SaveFMFile(disk, data, filename)` takes exactly the
same FM-file format `FM7Lib::TextTo0A0` already produces, so it is the existing
generator with the last step swapped. Disk loading is the most exercised path in
this project.
