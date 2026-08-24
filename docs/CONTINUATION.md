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
(40.2%, 0.0%).** Both diverge at `$FD1D` pc=$FEF0 in the boot ROM. **Do not chase
`$FD1D` itself** -- the Fujitsu manuals define b0/b1, b6 and b7 only, both
references agree on all of those, and building with 77AVEMU's form for the
undefined bits 5:2 changes neither title (tested). The lead is what those titles
do *after* it. Note they diverge at the same instruction as Shounen Mike did, so
the `$FD05`/BUSY family is worth trying first.

**3. Luxsor disk 2 blanks with `$FD00` b0 = 1, and the cause is NOT any of the
obvious candidates.** b0 = 1 is correct (see `c88c1db`) and is what makes
cassettes work, so this is the price currently being paid for them. Luxsor goes
from 81.9% coverage in 33 colours to blank at every frame from 1000 to 2400.

Chased with `tools/seqdiff.py` against a full reference trace. **The two streams
stay structurally aligned** -- same port and same PC -- through the entire boot
and into Luxsor's own loader, with only two value differences the whole way:
`$FD05` b7 and `$FD1D` b5:2. **Both were tested and neither is the cause:**

* *`$FD1D` bits 5:2.* Built with 77AVEMU's form (cleared, so `$FD1D` matches the
  reference exactly). Luxsor still blank.
* *`$FD05` b7 / BUSY-on-reset.* Built with `2fbd296`'s reset behaviour backed out
  so b7 matches the reference. Luxsor still blank.
* *The FDC.* Not it either. Both machines issue an identical command history --
  4x RESTORE at `$5159`, then the same seven READ SECTORs at `$01E3` -- with
  identical register setups, and **both read `$FD18` status `00` seven times at
  `$01F8`**, so every sector read completes successfully on this core too. A
  `$FD1F` DRQ difference at `pc=$01E9` looks like a smoking gun and is not one;
  it is polling phase, and the reads succeed either side of it.
* *`$FD00` itself.* With b0 = 1 this core's 300 `$FD00` reads match the reference
  exactly, value and PC, and they are all from boot ROM addresses (`$FF44`,
  `$51CB`) -- Luxsor's own code never reads it.

So b0 changes something in the **boot ROM's** path that this core then handles
differently, and it is not visible in the main-CPU `$FDxx` stream at all. Next
place to look is the `$D4xx` sub-system side, which `seqdiff.py` deliberately
does not compare (see REFERENCE.md trap 43) -- or the video path, since the
symptom is a blank screen on a machine whose disk reads all succeed.

**4. Mahjong Kyou Jidai (66.8% reference, 82.7% here, 7.8% agreement).** The one
broken title with no shared cause. Untouched.

**5. `vsim/shots-ref/` is stale.** `run_tests.sh` reports COUNTERS on every FM-7
row -- main 5555 -> 9387 per frame -- which is `6a7030e`'s 1.67x speedup, not a
regression. Re-bless in its own commit, saying so, and check the two SCREEN+CNT
rows (Thexder, av-demo) are phase shifts before accepting them.

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
