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

**2. FM Sound Editor (69.8% reference, 0.0% here) and Pro Yakyuu Fan disk A
(40.2%, 0.0%): SAME first divergence as Luxsor, THREE DIFFERENT failures.**

Both diverged at `$FD05` b7, `pc=$5043`, main-CPU I/O access 20,604 -- byte for byte
the same divergence as Luxsor disk 2, in the shared FM77AV boot loader rather than in
either title's own code. That is fixed (see item 3). `$FD1D` bits 5:2 was the second
shared divergence and is also fixed. Neither title renders.

**Do not treat the three as one bug from here on.** Traced to frame 500 with the fixes
in, they end up in three unrelated places:

| title | where it ends up | `$FD90` writes |
|---|---|---|
| Luxsor disk 2 | non-terminating MMR copy loop at `$3B7A`-`$3B99` | `$3B52`/`$3B5F`/`$3B6C`, then unbounded at `$3B7B`/`$3B87` |
| FM Sound Editor | `$863D` onward, executing `00 00` as `NEG <$00` over and over | 4 at `$0174`, 1 at `$0185` |
| Pro Yakyuu Fan A | boot ROM FDC poll at `$FE93`-`$FEA0`: `LDA $FD1F` / `BPL` | 7 at `$DFB8` |

*FM Sound Editor is a genuine runaway* -- the main CPU has walked off into zeroed memory
at `$86xx` and is executing it as a `NEG <$00` sled. The old sweep row flagged it
`RUNAWAY-INTO-IO`, which agrees. The question is what transferred control there.

***Pro Yakyuu Fan disk A is the most tractable of the three and should be taken first.***
It is not crashed and not lost: it is sitting in the boot ROM's own FDC data-request
poll, `$FE93 LDA $FD1F / $FE96 BPL`, waiting for a DRQ that never arrives. That is a
bounded, well-specified FDC question with a known-good reference to compare against,
unlike the other two. Note the trap: the `$FD1F` difference at `pc=$01E9` on Luxsor IS
only polling phase and was correctly dismissed as such -- but "it was polling phase on
that title" is not a statement about this one. Check whether DRQ ever asserts here at
all. Item 6 below (FDC lockout periods are not modelled: 1 s after motor on, 60 ms after
head load, drive-register write or step) is the obvious first suspect.

**3. Luxsor disk 2: two real bugs found and fixed, and it is STILL BLANK.**

Read this whole entry before working on the title. It has now produced two confident
wrong answers in a row and the second one was mine.

*Superseded claim 1:* "blanks with `$FD00` b0 = 1, and the cause is not any of the
obvious candidates." Wrong. b0 = 1 is correct and matches 77AVEMU exactly
(`fm77avio.cpp:806`). What b0 selects is a delay constant in the AV boot ROM's `$FF42`
routine -- `LDY #$00E0 / LDA <$00 / ASRA / BCS` with `DP=$FD`, so b0 = 1 keeps Y = 224
and b0 = 0 loads Y = $99 = 153. b0 = 0 was not fixing Luxsor, it was perturbing a race.
See REFERENCE.md trap 55.

*Superseded claim 2 (mine):* "root cause found -- the sub CPU is 2x too slow." The
finding is real and the fix is in, but it is **not** the cause of Luxsor being blank.

What is solid, and is fixed: `MB60H010.v` gave the sub CPU the VRAM address bus only
outside the 640x200 active area, 52.3% of the raster, so a VRAM-bound sub loop ran at
half speed. Both references default to no CRTC halt at all on an AV (77AVEMU
`CRTCHaltsSubCPU = false`, XM7 `cycle_steal = TRUE`) because the AV inherits the FM-77's
cycle steal. Measured against main-CPU `$FDxx` accesses as the shared yardstick, the
sub's `$D40A` read at `$E13B` -- which clears `$FD05` BUSY -- lands at access 17,844 on
the reference and after 21,084 here, against a main-CPU poll at access 20,604 on both.
Details and citations in the "Sub-CPU VRAM arbitration" section of docs/FM77AV.md.

That was the FIRST divergence for **three** titles at once -- Luxsor disk 2, FM Sound
Editor and Pro Yakyuu Fan disk A all diverge at access 20,604, `R $FD05 FE` against
`$7E`, at `pc=$5043`, which is in the shared FM77AV disk boot loader and not in any
title's own code. `$FD1D` bits 5:2 was the second, also shared. Both are fixed.

**And all three titles are still blank.** Luxsor enters the same non-terminating loop
at `$3B7A`-`$3B99` at frame ~375, and the `$FD90` write counts either side of the fix
are identical -- 25 each at `$3B52`/`$3B5F`/`$3B6C`, then unbounded at `$3B7B`. The boot
handshake now resolves the way the reference resolves it and the title's own code still
fails.

*Superseded claim 3 (also mine): "it is executing misaligned bytes / garbage."* Traced
into, it is not. `$3B49`-`$3B76` is a clean, correctly terminating loop that copies three
bytes per pass through the MMR window -- `CLR $fd90` / `LDD ,X` / `STA ,U` /
`STB $2000,U`, then `$fd90 <- 1`, then `$fd90 <- 2`, `PULS B,X` / `DECB` / `BNE $3b49`.
It runs its 25 passes and exits. `$3B78` is then `LDB #$0f` -- B enters the next loop as
**15**, a perfectly ordinary count -- and falls into `$3B7A`, which is the same shape.

**`$FD90` is the MMR segment select, so the bytes at a given logical address change as
this loop runs.** That is why a disassembly of `$3B8F`-`$3B99` shows `STB $c486`,
`FCB $02`, `STD $906f`, `SUBB #$5a`: the disassembler reads whatever bank is mapped when
it looks, which need not be the bank the CPU fetched from. Register values in the trace
are real (B genuinely walks d3, 79, ..., 5d, 03), but the instruction text is not
trustworthy inside an MMR-banked loop. Do not read "illegal opcode in a hot loop" as
"the CPU has crashed" here -- check the mapping first.

*So what the arbitration fix bought* is a correct sub-CPU speed, agreement with the
reference through two more readbacks, and the removal of the first divergence so the
next one can be seen. It bought no pixels. Do not let the commit message make you think
Luxsor is close.

*Where to look next.* The main-CPU `$FDxx` stream is close to exhausted as an instrument
here: after the two fixes the only difference left in the first 40 frames is `$FD1F`
DRQ polling phase at `pc=$01E9` (the reference gets DRQ on its third poll, this core is
still spinning), which shifts `seqdiff`'s alignment and hides anything after it. Two
things worth doing before anything else:

  * Teach `seqdiff.py` to collapse polling reads properly. It already collapses runs of
    identical accesses and has `VALUE_UNCOMPARABLE = {'FD1B'}`; a run whose VALUES differ
    (3F,3F,3F... against 3F,3F,BF) does not collapse to the same key on both sides, so
    one status poll desynchronises the rest of the trace. Until that is fixed the tool
    cannot answer "is there a later divergence".
**The MMR is NOT the fault, and here is the evidence so nobody re-runs it.** Two
checks, both negative:

  * *The code page cannot move under it.* The boot ROM at `$E49E`/`$E4A3` programs all
    four segments identically -- `$FD90 <- 0`, then `$FD80`-`$FD8F` = `$30`-`$3F`, and
    again for segments 1, 2 and 3 -- so logical page 3 maps to physical `$33000` in every
    segment and the `$FD90` writes inside the loop cannot change the bytes being fetched.
  * *The whole MMR enable sequence matches the reference exactly.* Every `$FD93` write
    agrees in PC and value on both machines, in order: `6006 01`, `6109 BF`, `6119 3F`,
    `FC79 00`, `E085 00`, `E497 00`, `EBBE 80`, `E4C4 80`, `E4CC 00`, `E4D5 00`,
    `E12E 00`, `E231 80`, `E27B 00`, `EBBE 80` x6, `E1D8 80`, `E213 00`, `EE54 00`,
    `EE77 00`, **`EEA1 3E`**. `$FD93` b7 is `mmr_enable`, so that last one DISABLES MMR
    immediately before the loop runs -- on both machines. The `$FD90` writes inside the
    loop are no-ops on both. The reference's next `$FD93` write is `E5B0 00`, which this
    core never reaches because it is still in the loop.

**So the two machines agree on the entire main-CPU `$FDxx` stream up to `$EEA1` and
diverge only in what happens after.** With MMR off, the loop's `LDD ,X` at `X=$05DE`
reads through the plain FM-7 layout at physical `$305DE` and returns `$0000` here; the
loop then copies those zeros. The remaining question is therefore about MEMORY CONTENTS,
not about any register: what should be at `$05DE` by frame 375, and why is it zero here?

*The instrument for that has not been built.* `--dump-shadow` gives the main-CPU bus
shadow on this core, and `tools/77avemu_headless.cpp` has no equivalent. Adding a memory
dump to the reference harness -- the same shape as `--stop-at-frame` -- would make the
two directly comparable and is probably the highest-value tooling work left on the disk
side. Do that before spending more time reading traces.

**4. Mahjong Kyou Jidai (66.8% reference, 82.7% here, 7.8% agreement).** The one
broken title with no shared cause. Untouched.

**5. `vsim/shots-ref/` is stale, and one of its rows is a BLESSED BLANK.**
`run_tests.sh` reports COUNTERS on every FM-7 row -- main 5555 -> 9387 per frame
-- which is `6a7030e`'s 1.67x speedup, not a regression. Re-bless in its own
commit, saying so, and check the two SCREEN+CNT rows (Thexder, av-demo) are phase
shifts before accepting them.

**`shots-ref/av-kohakuiro.png` is a solid black frame.** Kohakuiro no Yuigon disk
1 also renders blank at HEAD today -- 3790 bytes at frames 700 and 900, this
core's blank-PNG size -- while `sweep/results-av-f700.tsv` records 16857 bytes for
it. So the title regressed on some earlier core AND the blank was then blessed,
which is the one failure this gate exists to prevent: a row that can never fail
because its reference is the failure. Do not bless a row without looking at the
picture. Wizardry IV wants the same look -- its blessed shot has four detailed
sprites and HEAD frame 700 renders three garbled ones, which may be a regression
or may be a different animation instant; nobody has established which.

**Trap for whoever picks this up:** `sweep/results-av-*.tsv` are NOT a valid
baseline for today's tree. They predate the clock commit and several others.
Comparing a change against them attributes pre-existing state to the change --
which happened here: Kohakuiro's blank and Wizardry IV's blobs were both read as
damage from the VRAM arbitration change and are present at HEAD without it.
Build the baseline from the same tree you are changing, in the same session.

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
