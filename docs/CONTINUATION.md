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

**2. Pro Yakyuu Fan disk A is FIXED. FM Sound Editor is FIXED too, by two unrelated
faults: the TWR window sat 31 KB low, and the keyboard encoder never answered the
sub monitor's real-time-clock read.**

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

*FM Sound Editor -- the `$FD88` divergence is FIXED and the cause was the TWR window,
not anything that computes a bank number.* (Superseded claim: "it diverges on a COMPUTED
value -- find what computes the 12th `$FD88` write". The write at `pc=$9289` is
`LDA 2,S / STA $FD88`, a RESTORE from the stack, so `$24` was never computed: it is the
caller's `A`, read because the banked routine the trampoline called never ran and so never
consumed its stack parameter.)

`$FD92` is an OFFSET added to the CPU address, not a base -- see `docs/FM77AV.md` and
REFERENCE.md trap 64. `AVMEM.v` dropped the `$7C00`, so every TWR window sat 31 KB low.
Measured end to end on this title:

| frame | what happens | ours, before |
|---|---|---|
| 22-24 | 4096 bytes copied to physical `$00000` through MMR page 8 = `$00` | correct, `phys=$00000` on every write |
| 221-265 | an `$ff`-write / read-back / `$00`-write RAM-size probe walks the TWR window from register `$00` to `$70` | landed on `$00000-$073ff` instead of `$07c00-$0efff`, erasing the code |
| 267 | the trampoline at `$95AA` maps page 8 back to `$00` and `JSR $8000` | 4 KB of zeroes, a `NEG <$00` sled |
| 268 | `LDA 2,S / STA $FD88` restores the wrong stack byte | `$24`, and the machine is lost |

With the fix the main-CPU `$FDxx` stream matches 77AVEMU for the whole 700-frame run
except for the OPN status read below and one `$FD05` sub-BUSY spin count. Everything
downstream moved with it: I/O cycles 434,533 -> 1,200,565, `$D40A` accesses 1/0 -> 17/16,
PSG `$FD0D` writes 0 -> 72, `$FD37` `$00` -> `$88`, and the main CPU now reaches `$F650`
(the sub-command handshake) where CONTINUATION previously recorded it never did.

*The SECOND fault, found the same way and also fixed: the keyboard encoder never
answered the RTC read.* With the TWR fix in, the title still rendered black at 300, 500
and 700 (PNG 3790) with VRAM **entirely empty** -- 0 of 98,304 bytes non-zero, against
25,051 in the reference. Nothing had ever been drawn. Traced by counting rather than by
diffing, because `seqdiff.py` deliberately does not compare counts (see its docstring):
the main CPU issues **16** sub calls in 700 frames where the reference issues **281**,
and from frame 286 it does 676,356 reads of `$FD05` at `$F650` waiting for a BUSY that
never clears.

The sub CPU was the one stuck. `--trace-sub-cpu` over frames 285-291:

```
$de74  LDA #$80 / JSR $df7b       ; encoder command $80 = read the real-time clock
$de79  CLRA     / JSR $df7b       ; parameter $00 = read
$de7d  LDU #$d383 / LDA #$07      ; SEVEN bytes expected back
$df89  LDA #$80
$df8b  BITA $d432                 ; wait for b7 to clear -- a reply byte is waiting
$df8e  BNE  $df8b                 ; 22,514 times and counting
```

`AVKEYBOARD.v` accepted `$80` as a stub that consumed its parameter and produced nothing,
so b7 never cleared, the sub never got back to its idle loop's `TST $d40a`, BUSY stayed
set and the main CPU waited on it for the rest of the run. See `docs/FM77AV.md` for the
command table this now implements and for the one place the two references disagree
(the fourth RTC byte's bit layout, where this core follows CSP).

**With both fixes the title RENDERS**, and every counter lands on the reference's:

| | blank | rendering |
|---|---|---|
| main-CPU IRQs in 721 frames | 1 | **6,390** |
| sub calls (`$D40A` writes) | 16 | **281** -- the reference's exact count |
| sub BUSY at the end | 1, stuck | 0, idle |
| frame-500 / frame-700 PNG | 3790 / 3790 | 6772 / 7313 |

Frame 700 is the reference's frame-704 screen: the synth panel, the slot and numeric
pads, and the "ANALOG MODE FOR BEGINNERS / MANUAL MODE FOR EXPERTS" prompt.

*One difference left, and it is small:* the picture sits about 25 raster lines higher
than the reference's, with `scroll = $1b80` where the reference's frame is offset
differently. Compare `$FD17`/`$FD18` scroll handling against 77AVEMU before assuming it
is the core -- the two harnesses render at different heights (640x200 here, 640x400
there), so measure it, do not eyeball the two PNGs.

*One real remaining `$FDxx` divergence, and it is probably benign.* The YM2203 status read:

```
$ef0a  LDA #$04 / STA $fd15     ; command 4 = read status
$ef0f  LDA $fd16                ; ours $80 or $00; reference always $7C
$ef15  TSTA / BPL $ef1b         ; wait for BUSY (b7) to clear, 255 tries max
```

77AVEMU hardcodes `0b01111100 | timerA | timerB` and **never sets BUSY**
(`fm77av/sound/fm77avsound.cpp:210-214`). jt03 models BUSY, so over 700 frames this core
reads `$FD16` 339 times (243 `$80`, 96 `$00`) against the reference's 97, all `$7C`. The
loop is bounded and always falls through, so it costs time, not correctness -- but the
low five bits also differ and no title has been shown to read them.

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

**The loader's dispatch table at `$508C` differs -- but it is NOT corrupted here, it is
UNUPDATED here.** (Superseded claim: "the table is corrupted". The TWR window both
machines copy it from is byte-identical.) Traced the whole
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

*Where the table comes from, measured.* `--trace-mem 5090-5093` shows exactly ONE write on
this core, at frame 6 from `pc=$613B`, which is a block copy:

```
$6133  LDU #$7C00     ; source = the TWR window
$6136  LDX #$5000     ; dest
$6139  LDD ,U++
$613B  STD ,X++
$613D  CMPX #$5280    ; 0x280 bytes
```

**And the TWR window is byte-identical between the two machines** -- 640 observed bytes,
zero differing at frame 6, with `$7C90` holding `23 01 b4 c6` on BOTH. So both copy the
same bytes into `$5090`, and this core's value is what the copy put there.

**Therefore the reference UPDATES those table entries later and this core never does.**
Entries 0, 2, 3 and 8 match because nothing updates them; 1, 4, 5, 6, 7, 9, 10, 11 differ
because the reference rewrites them and we do not. Entry 8 being intact is why the
track-16 reads succeed and loop -- the core indexes a stale-but-valid entry.

*Bracketed by dumping `FM77AV_CPU_DUMP` at a spread of frames.* The reference rewrites
`$5090` **twice**, both between frames 240 and 300: `23 01 b4 c6` -> `b6 51 fb f6`
(which disassembles as `LDA $51FB`, i.e. it loads CODE over that region) -> `00 08 01 0a`.
This core never rewrites it at all.

**And the divergence is isolated to ONE page.** Comparing `--dump-shadow` against
`FM77AV_CPU_DUMP` at the moment BEFORE the reference's rewrite (ours 240, reference 241):

| page | observed | differ |
|---|---|---|
| `$0000` `$1000` `$2000` | 9,881 | **0** |
| `$5000` (the loader) | 640 | **0** |
| **`$6000`** | **369** | **369 -- every byte** |
| `$8000`-`$B000` | VRAM / aperture | all (expected once execution diverges) |

`$6xxx` is where the copy routine at `$6133` lives. At frame 6 **both machines hold it
byte-identically** (`ce 7c 00 8e 50 00 ...`). By frame 241 the reference's logical `$6133`
reads `$CC` -- which is 77AVEMU's fill for never-written physical RAM
(`memory/fm77avmemory.cpp:149`), so it is real content and not a dump artifact -- while
this core still sees the loader there.

**RETRACTED -- the `$6xxx` difference is an artifact of REFERENCE.md trap 60, which I
wrote earlier the same day and then walked into.** `--dump-shadow` is a HISTORY of the
last byte the CPU saw at each logical address; `FM77AV_CPU_DUMP` is a true SNAPSHOT of
current memory. This core read `$6133` at frame 6 and never again, so its shadow still
shows the loader while real memory has moved on. The reference's `$CC` is current reality.
**Nothing was wrong with `$6xxx`.**

Settled by building the instrument instead of inferring: `DEBUG_MMR=1` on this core and
`FM77AV_MMR_DUMP` on the harness both print all four segment maps. At frame 241 they are
**byte-identical**:

```
ours  en=1 seg=3 | s0..s2: 30 31 32 ... 3f | s3: 34 31 32 33 34 35 36 37 ...
ref   en=1 seg=3 | s0..s2: 30 31 32 ... 3f | s3: 34 31 32 33 34 35 36 37 ...
```

Same enable, same segment, same maps, page 6 -> `$36` on both. **The MMR is not the
difference**, and neither is the segment interleaving the previous note suspected.

*Where that leaves it.* The comparison at frames 240/241 is worthless for any page the
core has stopped reading, which is most of them -- so the only trustworthy rows in that
table are the ones the core was still actively touching. **Redo it with a live snapshot on
both sides, or restrict it to addresses the shadow's `.known` mask says were read
recently.** Until then the honest position is that the divergence has been narrowed to
the loader's dispatch table not being rewritten, and no further.

*Still true and still the lead:* the reference rewrites `$5090` twice between frames 240
and 300 and this core never does. Find what executes that rewrite on the reference --
bracketing with `FM77AV_CPU_DUMP` works and cost about a minute per sample.

*Measured clean and not worth re-checking:* the FDC (first 142 reads identical, zero
NOMATCH), the sector data (~99.8% over 40,000 bytes), the TWR window (640 bytes, zero
differ), the boot ROM's seek logic, and the loader region `$5000`-`$50FF` itself at the
moment before the rewrite.

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

***Daiva Story 2 disk A is FIXED. Luxsor disk 1 is not.***

  * **Daiva Story 2 - Memory in Durga disk A** -- the `$FD13` sub-monitor reset was
    clearing the CRT on/off latch. It was drawing correctly the whole time: 4067
    non-zero VRAM bytes at frame 1980 against the reference's 4078, into a screen held
    blank. See `docs/FM77AV.md`, the sub-system section, for what `$FD13` does and does
    not reset on the two references. Frames 1100/1400/1700/1980 go 3790/3790/3790/3790
    to 8538/3867/7550/7422, and frame 1980 is the reference's picture.
  * **Luxsor disk 1** -- still blank. The TWR and keyboard-encoder fixes do not touch
    it at all: over 2000 frames every counter is byte-identical (16,655,821 main
    instructions, `pc now $014e`, sub 95.9% halted, `$fd05` reads `$fe`), measured
    against a same-tree baseline built from `1455e4a` in a worktree as trap 57
    requires. The `$FD13`/CRT fix moves **exactly one line** of that summary --
    `display OFF` -> `display on` -- and nothing else; the screen is still 3790 at
    all four sampled frames. Its own signature is a RUNAWAY: 12 instruction fetches
    from the `$fdxx` I/O window, IRQ asserted and never taken, and **the digital
    palette is all zeros**, i.e. all eight colours black. With the display now
    enabled, that palette is the next thing to measure -- dump VRAM and compare the
    `$FD38-$FD3F` write stream against the reference before assuming the CPU runaway
    is the whole story.

*Not a regression, do not chase:* **Wizardry IV disk A** reads MATCH -> CORE-BLANK in the
table and is fine. Its samples are 12222 / 10635 / 10411 / 7143 bytes -- it renders
throughout, and only the frame-1980 canonical lands mid-transition. The gate, which shoots
at frame 600, passes it byte-identically. Trap 49.

**4. Mahjong Kyou Jidai Special disk 1 -- FIXED, bar the title lettering.** The main
CPU reaches the shared window `$FC80-$FCFF` only while the sub CPU is halted; this core
let the write through, so the title's probe read back its own `$00`, concluded the sub
was already halted, skipped the halt, and drove the drawing ALU through an aperture that
then -- correctly -- dropped the writes. **211 line triggers issued, 10 landed.** See
`docs/FM77AV.md` for the rule and both references' citations.

| | before | after | reference |
|---|---|---|---|
| PNG at 1100/1400/1700/1980 | 13838 (all) | **42341** (all) | -- |
| VRAM non-zero at frame 1980 | 6,343 | **33,098** | 33,017 |
| VRAM bytes equal to reference | 63,150 | **92,704** | of 98,304 |
| main-CPU `$D42B` / `$D411` writes | 550 / 279 | **485 / 278** | 485 / 278 |

The ALU command stream is now the reference's **exactly**, and the frame-45 divergence is
gone -- `W $FD05 80 pc=$1F0C`, the halt that was being skipped, now matches.

*Measured clean along the way, do not re-check:* the FDC (110,784 data bytes both sides),
`$FD37` (3 accesses, same values and PCs), the digital palette (29 writes, identical), and
**the Bresenham line engine** -- `DEBUG_AVDRAW` now prints `LSTART`/`LEND` with a step
count, and every line that started also finished at its exact endpoint
(`(262,0)-(182,80)` in 80 steps, `(401,199)-(489,111)` in 88). The engine was never the
fault; the writes never arrived.

*What is left, and it is a SECOND and unrelated fault: the sub-system BUSY flag never
clears, so the main CPU spins instead of issuing the sub calls that draw the title
kanji.* At `$2F87`, the wait-for-not-busy at the head of a sub call:

| at `$2F87` | reads `$FE` (busy) | reads `$7E` (free) | halts at `$2F8E` |
|---|---|---|---|
| ours | 2,353,206 | **3** | 3 |
| reference | 1,137,557 | **33,973** | 33,972 |

The main CPU makes 1,314,548 reads of `$FD05` at that one PC after frame 700 and gets
free three times in 1100 frames. **`seqdiff.py` reports the whole 1100-frame window as
clean** apart from two known-benign rows -- it collapses runs, so a spin loop is
invisible to it (trap 65). The tell was the raw line counts, ours 2,902,173 filtered
against the reference's 1,785,020, and a histogram of what ours does that the reference
does not.

The lettering itself is confined to VRAM **rows 16-83**; below row 84 the two machines
are byte-identical. Render the two dumps to compare -- the reference's band carries
麻雀名時代 SPECIAL over the artwork, ours carries the artwork alone.

*Ruled out for the lettering, with measurements -- do not re-check:* the ALU line engine
(command streams byte-identical, only PSET and TILEPAINT, compare never enabled), the
plane mask `$D41B` (applied, `AVHDRAW.v:284-286`), the compare path (matches 77AVEMU
`fm77avcrtc.cpp:849-877` including the `condition&1` sense), the sub CPU's own VRAM
writes (a uniform full-screen clear, 1600 per 20-row band across all 200 rows), and the
MMR VRAM aperture gate (`DEBUG_AVDRAW`: 55,444 accepted writes, **zero** blocked, zero
ALU intercepts).

*The lead.* Our sub executes ~100,000 `$D40A` command cycles over 2000 frames against the
reference's ~36,000 pro-rata, and BUSY ends stuck set (`BUSY=1 SHALTn=1 SHALTACn=1`) with
the sub CPU running. The sub monitor's idle loop clears BUSY once at `$E382` (`TST $d40a`)
and then polls `$D382` without re-reading `$D40A`, so BUSY should sit CLEAR while it
idles. Find why ours does not. **Note the BUSY set/clear semantics are trap 55 territory
and the references disagree** -- 77AVEMU argues from the schematic that the halt
ACKNOWLEDGE raises the flag (`fm77av/fm77avio.cpp:65-100`), `FLAGS.v` follows MAME and CSP
in raising it on the halt REQUEST. Do not change that without a same-tree sweep.

*One divergence remains in 700 frames* (besides the benign `$FD1F` FDC logging shift):
`R $FD3C` returns `$00` here against the reference's `$FC`. `PAL.v` now fills the five
unused bits with 1s as both references do, and that read STILL returns `$00` -- so
`PALDATA` is not being captured on that access at all. The capture is a filtered leading
edge of `RDQEn` qualified by `~PLTREGn`; a read-modify-write like the `CLR $FD3C` this
title uses may not present it the way a plain load does. Unverified, and benign here
because `CLR` discards what it read.

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
