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

**2. FM Sound Editor and Pro Yakyuu Fan disk A: both still blank AFTER the NMI fix, and
both now have a HEALTHY sub CPU.** Re-measured from scratch on the fixed build -- the
earlier traces for these two were taken with a wrecked sub CPU and everything derived
from them was retracted.

*Both sub CPUs are fine now.* At frame 500 each is parked in the ROM idle loop at
`$E13E`-`$E148` polling `$D382`/`$D380`, exactly like the reference. So these are genuine
MAIN-CPU faults, not knock-on from item 3b. (Check this first on any new title --
REFERENCE.md trap 62.)

*Where each one ends up:*

| | main CPU at frame 500 |
|---|---|
| FM Sound Editor | runaway: `NEG <$00` sled from `$863B` |
| Pro Yakyuu Fan A | boot ROM DRQ poll, `$FE93 LDA $FD1F / BPL` |

**Both share one shape: the reference runs a transfer routine this core never enters at
all, and this core falls back to a slower path.**

*FM Sound Editor* -- every FDC transfer this core makes matches the reference exactly:
`$FF98` 69,120 both, `$FED3`/`$FEDA` 270 both, `$521F` 256 both, `$518D`/`$5194` 1 both.
The reference ALSO runs a routine across `$F650`-`$F7EE` -- 411,632 accesses at `$F650`
alone -- reading 20,992 bytes at `$F6F1` and 82 iterations each at `$F72C`/`$F733`. **This
core executes nothing in `$F6xx`-`$F7xx` whatsoever.** The initiate ROM is `$FF` across
that whole span, so it is RAM-resident code; the question is what loads it and why we
never get there.

*Pro Yakyuu Fan A* -- `$FF98` 4,096 both, `$521F` 1,024 both, `$FEDA`/`$FED3` 4 both. The
reference reads 60,416 bytes at `$E142` and **this core reads none there**, while this
core reads 248,654 at `$FE98` against 20,480 and 26,624 at `$0174` against 2,048 -- twelve
to thirteen times as many, i.e. heavy retrying on the slow path. FDC commands issued tell
the same story: 274 read-sector against 86, 39 RESTORE against 5, 37 SEEK against 9, 13
FORCE INTERRUPT against 1. Still ZERO `$FD03` reads, so it never gets a timer IRQ either,
unlike Luxsor which the NMI fix cured.

Note `$E142` holds `20 18 96 0b` (`BRA $E15C`) in our initiate ROM, which is NOT a
`$FD1B` read -- and `$E142` is below `$FC00`, hence MMR-mappable. The reference is running
RAM-resident code there too.

*The sharpest fact for each, and it is the same fact:* **neither title ever executes the
code that ENABLES the timer IRQ**, because that code lives in a RAM-resident driver the
reference installs and this core does not.

  * *Pro Yakyuu Fan A* makes **zero** `$FD02` writes. The reference makes one,
    `VALUE:05` at `MAIN:E18B` -- bit 0 keyboard plus bit 2 timer. Memory dumps at the
    same instant (ours frame 500, reference 503) show why: at `$E18A` the reference holds
    `86 05 97 02` = `LDA #$05 / STA <$02`, and with `DP=$FD` that IS the `$FD02` write.
    This core holds `cc c0 00 fd` there. Likewise `$E142`, where the reference reads
    60,416 sector bytes, holds `b6 fd 1b a7 80 20 f4` = `LDA $FD1B / STA ,X+ / BRA` on the
    reference and `20 27 04 97` here. **Both machines have RAM at `$E1xx`** -- both differ
    from the initiate ROM, which is `$FF` across `$E180`-`$E19F` -- so this is not a
    mapping question, it is that we have different BYTES there.
  * *FM Sound Editor* makes the same two `$FD02` writes as the reference (`$10` at
    `$016A`, `$40` at `$8347`) and the reference makes 163 MORE, alternating `$40` and
    `$44` at `$F916` -- bit 2 again -- inside the same RAM-resident region as the `$F650`
    routine.

*What is NOT the difference:* the boot loader. `$5000`-`$50FF` is byte identical between
the two machines, 640 observed bytes and zero differing. And the MMR: this core writes
each `$FD8x` exactly once with the boot ROM's identity map (`$30`-`$3F`), while the
reference remaps `$FD80`/`$FD81` repeatedly (`$00 $10 $12 $14 $18` / `$01 $11 $13 $15`)
to load into different physical banks -- but that remapping is done BY the driver we
never install, so it is downstream, not upstream.

*Pro Yakyuu Fan's first real `seqdiff` divergence is unchanged by the NMI fix*: access
42288, where this core runs the empty-drive poll at `$0449` seven times (28 extra
collapsed entries) and the reference proceeds directly to `W $FD1A 01 pc=$FE4C`. Item 2's
earlier analysis of that scan still stands -- both machines select empty drive 1, both
read `$84`, both time out identically on a fixed 16-bit counter. The difference is that
the reference runs the scan once and this core runs it seven times.

*So the question for both is: what installs the driver at `$E1xx`/`$F6xx`, and what does
this core put there instead?* Compare `--dump-shadow` against `FM77AV_CPU_DUMP` at
several frames through the load and find the first frame at which `$E142` differs; that
brackets the write. Do NOT read anything into the whole-image page diff -- by frame 500
the two have long since diverged and almost everything differs for uninteresting reasons
(REFERENCE.md trap 60).

*The one benign difference to ignore in both traces:* `W $FD1B` at `pc=$FED6`. That is the
data-register write/read-back test at `$FECA` and both machines pass it; only the
register's idle content differs. It repeats every ~780 accesses and dominates `seqdiff`
output. Worth reading anyway: ours ping-pongs between `$FD` and `$02`, exact complements,
meaning nothing writes our data register between probes, while the reference's values
vary because its FDC is transferring in between.

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
