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

**3. `$FD00` b0 should read 1 and does not.** The manual is explicit (I/O map
page 1-9: `0:1.2M / 1:2M`) and the clock is now genuinely 2 MHz, so 1 is the
honest value. Setting it blanks Luxsor disk 2 at every frame sampled from 1000
to 2400 -- genuinely blank, not phase. 77AVEMU returns `$7F` there and runs the
title fine, so this is a second bug in this core that the bit merely exposes.
**It is NOT what blocks the three titles above** -- building with b0 = 1 leaves
all three unchanged to the decimal.

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

**Nothing loads, on either machine, from any image.** But the picture changed
substantially with `cc9e464` and the harness fix below -- the two machines now
agree, which they did not before.

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

On a commercial dump (Fighter), **both machines reach F-BASIC `Searching` and
stop there**. The reference: exit 0, motor turning, `tape_ptr` advancing past
11000. This core: motor on 87.8% of the run, 162019 cassette-bit edges, 37% of
the image consumed. They agree.

### Ruled out, with measurements -- do not re-check

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

1. **Run both machines long enough to finish a load.** Every run so far stopped
   while the tape was still moving. The reference at 8M steps had only reached
   `tape_ptr=11220`; give it 60M and see whether `Searching` ever resolves. If
   neither ever loads, that is a different and much more specific problem than
   "tapes do not work".
2. **Then use `seqdiff.py`.** It is available for tapes for the first time. The
   two machines agree at the screen level, so the first `$FDxx` divergence is
   the whole question.
3. Settle the 1.846-vs-2.0 discrepancy above.

### The magazine type-ins

`magazines/Program Pochette 1984 03 (J OCR)/` has seven FM-7 type-in programs
with `program.bas` and `program.t77` each. All seven sit at F-BASIC `Searching`,
for the reasons above -- **not** because the programs or the transcriptions are
wrong. Their own `commercial-tape-test/` control reached the same conclusion
independently.

If they need to run before cassettes work, the disk route sidesteps it entirely:
77AVEMU's `D77FileSystem::SaveFMFile(disk, data, filename)` takes exactly the
same FM-file format `FM7Lib::TextTo0A0` already produces, so it is the existing
generator with the last step swapped. Disk loading is the most exercised path in
this project.
