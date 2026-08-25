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

*(Superseded claim: "waiting for a DRQ that never arrives." Wrong -- read off a
16-instruction tail snapshot, which is a picture of wherever the run happened to stop,
not evidence of a hang. DRQ asserts 149,750 times.)*

The title's own probe routine, disassembled from a `--dump-shadow` at frame 30:

```
$0430  LDB $FFE0 / ORB #$80 / STB $FD1D   ; drive from $FFE0, motor on
$0438  LDA $FD18 / BITA #$C1 / BEQ $0481  ; ready and idle? -> done
$043F  LDA #$D0 / STA $FD18               ; force interrupt
$0446  LDX #$0000
$0449  LDA $FD18 / BITA #$81              ; poll NOT READY (b7) | BUSY (b0)
$044E  BEQ $0455                          ; clear -> done
$0450  LEAX -1,X / BNE $0449              ; else spin, X wraps = 65536 times
```

`$FFE0` is the boot ROM's current-drive byte, loaded at `$FEF5` from `$FD1D` b1:0. Both
machines select drive 1 here, which is EMPTY, read `$84` (not ready, track 0) and time
out -- `BITA #$81` cannot clear with b7 set. **That half is identical and correct on
both. Do not "fix" the empty-drive status**; `$84` matches the reference exactly.

The two measured differences, at frame 500:

| | `$FD18` = `$84` | `$FD18` = `$86` (+DRQ) | polls at `$0449` |
|---|---|---|---|
| reference | 65,530 | 6 | 65,536 = 1 x 2^16 |
| this core | 457,443 | 1,309 | 458,752 = **7** x 2^16 |

  1. *We call the routine seven times where the reference calls it once.* The loop is a
     fixed-count timeout, so this is the CALLER retrying, not the FDC. `$0430` is
     reached via `$0343 LBSR $0430` from `$0308 BSR $0343`. Nobody has looked at what
     decides to retry.
  2. *Per call, DRQ asserts ~187 times here against 6 on the reference* -- on a drive
     with no disk in it, after a Force Interrupt. That is an FDC-side difference and the
     better lead of the two. `FDC.v`'s `empty_core_dout` answers `$84` for the status
     register, but the DRQ path is not obviously gated the same way.

Note the trap that nearly caught this twice: the `$FD1F` difference at `pc=$01E9` on
Luxsor genuinely IS polling phase and was right to dismiss. That is a statement about
Luxsor. Same register, same-looking difference, different title, different question.

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
diverge only in what happens after.**

*Superseded claim 4 (mine): "the loop reads `$05DE` and gets `$0000` here, so what should
be there and why is it zero?"* The premise was wrong. `FM77AV_CPU_DUMP` now exists on the
reference harness (logical 64 KB, the counterpart of `--dump-shadow`) and the answer is
that **`$05DE` reads `$00` on the reference too**, and `$3B7A`-`$3B99` is **byte identical
on both** (`4f f7 02 fd c0 26`). Of the 126 bytes our CPU observed in the whole `$3xxx`
page, none differ; of 4096 in `$E000`, six do. So neither the data the loop copies nor
the code it runs is the difference. That retires the memory-contents hypothesis for the
loop itself.

*How to use the new dump, and its one big caveat.*

```
FM77AV_CPU_DUMP=ref.bin refs/local/fm77av_headless ROMS disk.d77 200000000 \
    /dev/null --stop-at-frame 382
vsim/obj_dir/Vemu --headless --machine fm77av --disk disk.d77 \
    --stop-at-frame 380 --dump-shadow ours.bin
```

Frame 380 here is frame 382 there (x1.00608, trap 58). Compare only bytes the core
actually observed -- `--dump-shadow` writes a `.known` mask beside the image for exactly
that. **A difference is weak evidence and agreement is strong evidence**: once the two
machines take different branches their RAM diverges for entirely uninteresting reasons,
and at frame 380 they already have. At that instant the reference is at `pc=$ff9c` with
its sub CPU parked at `$c099` -- the same `$D380` command wait ours sits in -- so the
`$5xxx`, `$8000`-`$C000` and `$9000`+ differences in a raw diff are execution drift, not
findings. Use it to confirm that something you suspect is the SAME, or to look at a
region neither machine has written yet.

**3b. ROOT CAUSE CANDIDATE FOR ALL THREE BLANK AV TITLES: a spurious sub-attention
FIRQ steals the timer interrupt.** Found after items 2 and 3 above had exhausted every
other instrument. Read this before touching any of the three.

*The symptom, measured on all three:*

| `$FD03` reads (timer-IRQ handler) | reference | this core |
|---|---|---|
| Luxsor disk 2 | 22,554 | **0** |
| Pro Yakyuu Fan disk A | 9,809 | **0** |
| FM Sound Editor | 7,662 | **0** |

`$FD03` read acknowledges the timer/printer IRQ (77AVEMU `fm77avio.cpp:663-666`, "RFD03
seems to clear timer and printer irq"). The reference runs its handler at
`$E5AB`/`$E5B7`/`$E5DA`/`$E5E6` 11,277 times on Luxsor; **this core reaches those
addresses zero times.** All three titles write `$FD02 <- $05` at `pc=$E51D` -- bit 0
keyboard plus bit 2 timer -- identically on both machines, so the enable is not the
problem, and `TMMASK = ~m77[2]` decodes it correctly.

*The branch, caught in a `--trace-cpu` window at frame 370:*

```
$eea1  STA $fd93   cc=eFhInzvc   ; I set, interrupts masked (both machines agree here)
$eea4  PULS CC,A,DP,PC           ; cc -> efhinzvc, I CLEAR
$efe1  LDX $804c                 ; S drops by 3 = a FIRQ push (PC+CC), not an IRQ's 12
$3b1a  BNE $3b15   cc=eFhInzvc   ; F and I set: we are IN the FIRQ handler
```

`$3B1A` is the FIRQ vector and `$E5A9` the IRQ vector, and **both vectors are identical
on both machines** (checked in the memory dumps). The instant the loader unmasks, this
core has a FIRQ pending and the reference has an IRQ pending. FIRQ outranks IRQ on a
6809, so whoever has FIRQ pending takes it.

*Why we have one and the reference does not:*

`TIMER.v:143-155` -- `attn_pend` is SET when the sub CPU reads `$D404` and cleared only
when the main CPU finishes reading `$FD04`; `FIRQn = m45_q8n & BREAKn` with
`m45_q8n = ~attn_pend`. Both machines read `$FD04` exactly twice, at `pc=$6120` and
`pc=$5013`, early in boot, and never again. So one stray `$D404` read leaves FIRQ
asserted for the rest of the run.

| sub-CPU `$D404` accesses | |
|---|---|
| reference, whole run | **0** |
| this core, first 100 frames | **23** |

**So the bug to find is why this core's SUB CPU reads `$D404` at all.** Narrowed since:

*It is NOT the `$D500-$D7FF` alias.* `SDECODE.v`'s `subio_alias_block` already blocks
that on the AV, and the trace filter is on the ADDRESS, so these are genuine `$D404`
accesses.

*It is a real, legitimate instruction.* The sub monitor at `$FF63` is

```
$FF63  STB $D381    ; result byte into shared RAM
$FF66  BITA $D404   ; raise attention -> main-CPU FIRQ
$FF69  PULS Y,PC
```

-- the command-completion notify -- and those bytes are **identical on both machines**.
So the sub is not executing corrupt code; it is finishing a command and signalling, which
is exactly what it is supposed to do. The reference's sub simply never gets there.

**The refined question is therefore: what command is this core's main CPU sending to the
sub that the reference's is not?** The 24 notifies cluster in frames 27-37. `$D380` is
the command byte the sub polls at `$C096`; the main side reaches it through its shared-RAM
window at `$FC80-$FCFF`. Diff the two machines' `$D380`-`$D3FF` contents over frames
20-40 with the new dumps, and find who writes the command.

*A red herring, killed, so nobody re-runs it:* the sub-CPU VECTOR TABLE looks completely
wrong in `--dump-shadow-sub` -- FIRQ `$1800` against the reference's `$FDAC`, IRQ `$0000`
against `$E06E`, only NMI matching. **It is not wrong.** `rtl/roms/subsys_m154.rom.mem`
(which `SMEM.v:41-43` selects for `submon_sel == 0`, the Type C default the AV falls back
to) holds `SWI3/SWI2/SWI/RESET $E000`, `FIRQ $FDAC`, `IRQ $E06E`, `NMI $FEBF` -- exactly
the reference's table. The shadow is a HISTORICAL record of bytes the CPU once observed,
not a snapshot of the current mapping, so a region read under an earlier mapping keeps
the older bytes. Same class of trap as trap 57: check the artifact against the ROM file
before believing it.

*Why nothing caught it:* no working test exercises the timer IRQ. F-BASIC writes
`$FD02 <- $40`, the 2019 AV demo polls and reads `$FD03` zero times. A dead timer
interrupt is invisible to the entire gate.

*What was ruled out first, so it is not re-run:* every main-CPU `$FDxx` access agrees up
to `$EEA1`; all 7,168 sector bytes transferred through `$01EE` are IDENTICAL (100.00%
once the reference's one-position pre-side-effect log shift is undone -- see
`VALUE_UNCOMPARABLE` in seqdiff.py); `$05DE` is `$00` on both; `$3B7A`-`$3B99` is byte
identical; of 126 observed bytes in the `$3xxx` page none differ. The FDC, the loaded
data and the executed code are all the same. Only the interrupt differs.

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
