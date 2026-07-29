# FM-7 core — what is left to do

Produced by reading `rtl/` against the three emulators in `refs/` and by running
the core in `vsim/`. Every item is tagged:

- **[verified]** — reproduced in `vsim/`, with the command to reproduce it.
- **[read]** — found by comparing source to a reference; not yet exercised.

Reference shorthand:

| | |
|---|---|
| **MAME** | `refs/mame/src/mame/fujitsu/fm7.cpp`, `fm7.h`, `fm7_v.cpp`. The most readable I/O map and the one this document cites most. |
| **CSP** | `refs/common-src-project/src/vm/fm7/` (Takeda Toshiya's common source project). The most complete FM-7: full keyboard tables, kanji, FDC, joystick, bubble casette. |
| **77AV** | `refs/77AVEMU/src/fm77av/` (CaptainYS). Cleanest structure, and the best source for CRTC/render behaviour and `.T77` handling. |

---

## Where the core is right now

**The core boots F-BASIC and runs programs.**

```
FUJITSU F-BASIC Version 3.0
Copyright (C) 1981 By FUJITSU/MICROSOFT
30530 Bytes Free

Ready
print 1234
 1234

Ready
```

Seven fixes got it there — P0-1, P0-3, P0-4, P1-1, P3-1, P3-6, and a `vsim`
harness bug. Before them the screen was black and both CPUs were deadlocked.

Two of those (P0-1 and P0-4) turned out to be **the same bug on the two
different CPUs**: an I/O read strobe qualified by `E` alone, which collapses at
the exact edge `mc6809i` latches the data bus. Worth remembering — if a third
read path ever misbehaves, check its qualifier first.

What works now: both `mc6809i` cores; the `m139` main-bus decode and the
`SDECODE` sub-side I/O map (both byte-for-byte what MAME maps); the shared-RAM
aperture and the main/sub halt handshake; the raster, character generator and
palette; the `$fd03` interrupt cause register; and the keyboard, for the
unshifted character set.

**The floppy path now works.** `.d77` images mount, are parsed into a per-sector
table at mount time, and the DOS boot ROM reads real sector data out of them —
byte-for-byte what is in the file. See P4-1: the parser was the planned work,
but three separate faults between the CPU and the controller had to be cleared
first, one of which was P0-1's E-qualified-read-strobe bug for the third time.

**Thexder boots from disk and renders its title screen**, with stock ROMs:

```sh
cd vsim && ./obj_dir/Vemu --headless --bootrom 0 --stop-at-frame 700 \
    --disk "../software/Fujitsu FM-7/Thexder (Game Arts)/Thexder [b].d77" \
    --screenshot 680 --screenshot-name shots/thexder.png
```

By frame 680 the title artwork is up and the credit line reads
"Copyright mcmlxxxv GAME ARTS Co.,Ltd. / Hibiki Godai / Satoshi Uesaka".
Both CPUs are running the game: the main decompressing at `$1a0d`, the sub
running an unrolled VRAM blitter at `$c054`.

Note **`--bootrom 0`**: bank 0 of the boot ROM is the one that loads a boot
sector at `$0100`, which is what real disks require — see P3-6b, and fix
`ROMS.v`'s bank selection so the OSD's four settings map onto the four banks.

**Disk F-BASIC boots all the way to `Ready`, interactively.** This is the
strongest end-to-end evidence the floppy path is right — it exercises the DOS,
not just a game's own loader, and it takes keyboard input:

```sh
cd vsim && ./obj_dir/Vemu --headless --bootrom 0 \
    --disk "[Compilation] Game 013.d77" \
    --key '700:1' --key '730:@RETURN' --key '820:2' --key '850:@RETURN' \
    --stop-at-frame 2200 --screenshot 2180
```

```
DISK VERSION
How many disk drives      ? 1
How many disk files(0-15)? 2

FUJITSU F-BASIC Version 3.0
Copyright (C) 1981 By FUJITSU/MICROSOFT
25662 Bytes Free

Ready
```

Both prompts are answered from the command line and echo correctly. **25662
bytes free against cassette BASIC's 30530** — the DOS takes the difference,
which is the right shape.

**The 77AVEMU demo disk boots too**, showing `YS-DOS V1.0 by CaptainYS 2019`,
which is a useful independent check: it is the reference emulator author's own
image, not a commercial title.

### P4-6 [FIXED] The Quartus build could not have compiled the FDC

`files.qip` did not list `rtl/wd1793.sv`, so the FPGA build had no definition for
the module `FDC.v` instantiates. `vsim` has its own file list in
`vsim/Makefile`, which is why this never showed up in simulation. Fixed.

**`files.qip` is the canonical list**, and the header of `FM-7_MiSTer.qsf` says
so: *"Do not add files to project in Quartus IDE! It will mess this file! Add
the files manually to files.qip file."* The qsf `source files.qip` at line 78.

The qsf had also accumulated a duplicate per-file list -- 39 assignments the
Quartus IDE injects back in whenever the project is opened in the GUI. Removed.
If it reappears, delete it again; it is not the list to maintain. Nothing was
lost: every entry was already in `files.qip`, including `rtl/pll.v -library pll`,
which `rtl/pll.qip` supplies properly with the library qualifier anyway.

**`rtl/wd1793_dpram.v` is deliberately NOT in `files.qip`.** The name is
misleading: it defines a module called `dpram`, an `altsyncram` wrapper that
nothing instantiates. The `wd1793_dpram` that `wd1793.sv` actually uses is
defined at the bottom of `wd1793.sv` itself as inferred dual-port RAM, so the
file is self-contained. Listing the stray file would only drag an unused Altera
primitive into synthesis. It is still in the `vsim` file list, harmlessly, since
Verilator never elaborates an uninstantiated module.

Verified both tops connect every one of `core`'s 28 ports, with none left over.

### P4-5 [FIXED] Every simulation froze at frame ~2666 — `(int)main_time`

`SimBlockDevice::BeforeEval` took its cycle count as `int`, and the call site
truncated: `blk.BeforeEval((int)main_time)`. `main_time` is a `vluint64_t` that
advances once per simulated 48 MHz cycle, so at 60 Hz it passes **INT_MAX
(2147483647) at frame ≈ 2666** (~800k cycles a frame). The cast then goes
negative, the very first line of the function —

```cpp
if (cycles < 2000) return;      // "wait until the computer boots"
```

— becomes permanently true, and **the block device silently stops servicing
every request from that moment on**. Fixed by widening the parameter to
`uint64_t` and dropping the cast.

This is a simulation-harness bug, not RTL. Nothing on hardware is affected. But
it invalidates *any* vsim result past frame ~2666, which is worth knowing before
trusting a long run: `run_tests.sh` uses `FRAMES=620` and never reached it,
which is why it stayed hidden.

**How it presented.** Loading a machine-language game out of Disk BASIC hung
with the main CPU spinning in the boot ROM's transfer loop, DRQ and INTRQ both
dead:

```
$ff94  LDB  <$1f     ; DP=$fd -> $fd1f
$ff96  BPL  $ff9e
$ff9e  LSLB
$ff9f  BPL  $ff94    ; neither -> spin
```

Fixed: the DMA now runs on to LBA 427 instead of freezing at 418, and the CPU
leaves the wait loop. (It then crashes into low memory executing `CLR <$ff` /
`STU $ffff` — a separate, later fault, and real progress.)

**Four wrong answers came before the right one, all from `$display`:**

1. *"The sim leaves `sd_ack` stuck high."* Never demonstrated.
2. *"Stale bits in `ack` clear `sd_rd` before the block device sees it."*
   Disproved — flushing `ack` per request changed nothing at all, instruction
   counts byte-identical at 19088384 / 32418615. Reverted.
3. *"The block device is idle and consistent at the stall."* Wrong: that printf
   run hit its 3000 s timeout *before* the stall and was reporting the quiet
   period preceding it.
4. *"So the fault is in the RTL after all."* Also wrong.

What actually found it: a **VCD** (`--vcd`, added for this) showing the
controller assert `sd_rd` and wait correctly while `ce` kept ticking — proving
the RTL innocent — and then a probe that printed **nothing at all**, because the
guard it sat behind had already gone dead. The silence was the evidence.

Two lessons worth keeping: check that a long run actually reached the event
before believing what it says about it; and when a bug survives two rounds of
printf, stop adding printfs.

### P4-8 [NEXT] Ys runs its own code for thousands of frames and draws nothing

Re-run long now that P4-5 makes frames past ~2666 trustworthy. At frame 4500,
with the keypress fed:

- Screen blank throughout (frames 1500, 2500, 3500, 4480 all identical).
- Both CPUs live and doing real work -- 4294 main / 7673 sub per frame. Main is
  at `$1424 BEQ / $1440 LDB 6,X / $1442 BITB #$40`, i.e. Ys's own loaded code
  testing a bit in a structure. Not a wait loop, not garbage, not a wedge.

**Two display suspects checked and cleared**, both against CSP rather than by
reasoning:

- **`$fd37` plane mask.** Ys writes `$00` exactly once. In CSP a plane is
  fetched when `!multimode_dispflags[i]` (`vram.cpp:512`) and
  `dispflags[i] = (dispmask & (1<<i)) != 0`, so `$00` means **show all three
  planes**. `FLAGS.v` has `DPAGE1 = m46[4]` and `PAL.v` has
  `clr1 = DPAGE1 | m25_3`, so `$00` shows everything here too. Same polarity,
  not the fault.
- **`$d408` CRT switch.** Already cleared earlier: Ys's last access is a *read*,
  which is CRT-on in CSP (`display.cpp:560`) and in `FLAGS.v`.
- Sub-side display offset `$d40e`/`$d40f` are written `$00`/`$00`, i.e. no
  offset.

**Measured, and the answer is "nothing is drawn" -- the video path is not at
fault.** Cumulative sub-side VRAM writes over frames 0-1400, against Thexder as
a working control:

| | writes | zero | nonzero |
|---|---|---|---|
| Ys | 75496 | 75089 | **407 (0.5%)** |
| Thexder | 94886 | 72727 | 22159 (23.4%) |

Ys touches VRAM plenty -- 75k writes spread evenly over the three planes
(24839 / 24581 / 26076), about 1.5 screens' worth -- but **99.5% of it is
zeros**. It is clearing the screen and painting 407 bytes of actual content.
Thexder, which renders correctly, is 23% non-zero.

So: the display is on, the planes are unmasked, the offset is zero, the sub CPU
is drawing, and what it draws is blank. **Stop looking at the video path.** The
fault is upstream -- Ys is not reaching the code that produces graphics. Chase
it from the main CPU at `$1424`/`$1440` instead, and find what it is waiting on
or looping over.

A trap worth noting from this measurement: a *low* write count proves nothing.
Sampling frames 3000-3020 gives Ys 16 writes and Thexder **0**, and Thexder is
displaying a full title screen at the time -- the image is already in VRAM and
needs no rewriting. Only a cumulative count from reset, with the data values
checked, says anything useful.

### P4-7 [NEXT] CHAN.POP loads further, then runs off into low memory

With P4-5 fixed, `run"CHAN.POP"` from Disk BASIC gets measurably further -- the
loader reaches LBA 427 instead of freezing at 418, 860 DMA requests -- and then
the main CPU ends up executing data as code in page zero and loops there:

```
$009d  SUBB #$0f
$009f  NEG  <$3f
$00a1  SUBB #$00
$00a3  NEG  <$0f
$00a5  SUBB #$ff
```

No disk activity at all after LBA 427, and both CPUs stay live (4747 main / 9284
sub per frame at frame 5200), so this is a wild jump, not a wedge. Screen still
reads `Loading GAME Program`.

**Not a bad DOS vector, despite appearances.** `JSR <$de` at `$7555` with
`DP=00` calls `$00de`, which holds `7e f1 7d` = `JMP $f17d` -- correctly
installed, and the call works. Two separate passes over this mistook that
legitimate vector call for the crash, because a filter looking for "first
execution in `$00xx`" lands on it. Find where control *leaves* the loaded
program instead; the last sane PC is in the `$75xx` region.

**A second game title now loads.** `Ys (FM7) (Disk A).d77` reads the sectors it
actually asks for, streams tracks off both sides, and loads a clean contiguous
24 KB into `$8000-$dfff` through the `$fd0f` RAM-mode window. It does not yet
render. Getting there needed P4-1j, and the interesting part is what P4-1j was
*not*: three separate subsystems were suspected, instrumented, and cleared —
the sector match, the halt handshake, and the shared-RAM aperture were all
already correct, and so was the boot ROM bank. The bug was one register write
per command being dropped between the CPU bus and the controller, invisible to
every check that asked "did the read work?", because the read always worked.

**Two methodology notes earned the hard way**, both of which produced confident
wrong answers before being caught:

- **A trace that hits `--trace-max` was truncated from the start of the run**,
  not the end. Check the frame range and compare the line count against the cap
  before believing any trace. (`--trace-from` now applies to the memory traces,
  which it previously did not.)
- **Reconstructing state from the bus log is not the same as asking the RTL.**
  A Python decoder that inferred `(track, side, sector)` from `$fd18-$fd1b`
  traffic reported two sectors returning the wrong side's data; a `$display` in
  the RTL's own match arm showed all 19 matches exact. Instrument the decision,
  not its inputs.

Getting that far needed two fixes with nothing to do with the FDC, both on the
sub CPU, and both worth knowing about:

- **`$fd05` bit 7, the halt acknowledge, was permanently 0**, so any code that
  halted the sub CPU and waited for it hung. Fixing it also cleared a
  `boot-basic` regression the FDC work had exposed — the same stuck flag seen
  from the other side.
- **The sub CPU was running at half speed** (P0-6). It is meant to be the
  *faster* of the two CPUs, and software leans on that.
- **And then losing another ~55% of its cycles to a blanket VRAM halt** (P0-7),
  which is now a proper per-access wait state. Between them the sub went from
  2001 to 8538 instructions/frame.

**Joysticks work** (P4-2), on the PSG's I/O ports, verified end to end by
driving the PSG by hand from F-BASIC. `vsim` can inject them:
`--joystick <frame>:<buttons>[:<hold>]`.

Next: P2-1 (`KEYBOARD.v` has no ctrl/graph/kana tables), the `ROMS.v` bank
selection, and following Thexder past its load.

`vsim/shots-ref/` is the booting baseline.

---

## Done

| | |
|---|---|
| **P0-1** | `$fdxx` reads returned `$ff` — I/O read decoder now gated by `RDQEn` (`core.v`) |
| **P0-3** | `TIMER`/`FLAGS`/`SOUND` latched the read bus on writes — now `MDATABUS_out` (`core.v`) |
| **P1-1** | Character cells loaded the previous cell's VRAM byte — shift-register load delayed one `CLKSYS` (`MB60H010.v`) |
| **P3-6** | `bootrom_sel` setting 2 picked an unbootable combination — `SW2[0]` → `|SW2` (`ROMS.v`) |
| **P3-1** | `IRQn` stuck asserted — timer-IRQ clear moved to `CLKSYS` with priority over the tick (`CLKCTRL.v`). Interrupts 2 → 10395; F-BASIC now reaches `Ready` |
| **P0-4** | Sub CPU read `$ffff` from `$d400` — same `E`-qualified read strobe bug, now `(SEB\|SQB)` (`SDECODE.v`). Keys echo; BASIC runs |
| **P2-1a** | SHIFT never worked: modifier state was inverted, and `m132` latched on `posedge press_btn` so pressing SHIFT itself delivered a stale code (`KEYBOARD.v`). Uppercase, `+ * " ( ) = < > ?` all type now |
| **P0-5** | Main CPU ran at the FM-8's 2 MHz, not the FM-7's 1.2288 MHz — `core.v` tied `CLKCTRL.SW2` to 0 (`core.v:226`). Instruction rate 9107 -> 4916 per frame |
| **P4-4a** | `$fd02` read bits 6..1 came from `CN2`, an undriven wire; tape input did not read high with the motor off (`PERIPHERAL.v`) |
| **P4-4b** | Tape played past end of image into stray SDRAM; `addr` powered up at `$62` instead of `$16` (`t77_decode.v` + both top levels latch `image_size`) |
| **P4-1a** | `.d77` mount-time parser in `wd1793.sv`: format sniffing, track offset table, per-track sector records, per-sector CRC status. Verified sector-for-sector (1265/1265) against a reference decode of `Thexder [b].d77` |
| **P4-1b** | `blk_size` never fetched a second 512-byte block for 128/256-byte sectors, so any sector straddling a block boundary read half stale data — 593 of Thexder's 1265 (`wd1793.sv`) |
| **P4-1c** | `MFD.v` declared `FD_Dout` and never assigned it, so the CPU's write data never reached the FDC and every command byte arrived as `$00` |
| **P4-1d** | FDC register writes were single-`CLKSYS` pulses handed to a module that samples on a 1 MHz `ce` — measured 11 writes issued, 0 received. Accesses are now latched and stretched (`FDC.v`) |
| **P4-1e** | `$fd1f` read decode was qualified by `E` alone, so the CPU latched `$ff` (DRQ and INTRQ always set) and the sector-read loop never terminated — **P0-1 for the third time** (`MFD.v`) |
| **P4-1f** | `s_index` read as permanently asserted with no disk in the drive — an empty drive claiming something was spinning in it (`wd1793.sv`) |
| **P4-1h** | `SRAM.v` let main-CPU writes into the shared window through outside a halt; the address mux then misdirected them to whatever address the sub CPU was driving. Gated by `SHALTACn`, matching MAME's `main_shared_w` |
| **P4-1g** | `$fd05` bit 7 reported only `BUSY`, and `FLAGS.v` holds `BUSY` asynchronously cleared *while the sub CPU is halted* — so software that requests a halt and polls for it to take effect hung forever. Now `BUSY \| ~SHALTACn`, matching MAME's `sub_busy \|\| sub_halt` (`TIMER.v`) |
| **P0-6** | **Sub CPU ran at half speed.** `SCPUCLK` took `SCLK2` (4 MHz, E = 1 MHz) in FM-7 mode; MAME has the FM-7 sub at `16.128MHz/2` = 8.064 MHz, E = 2.016 MHz — the sub is meant to be the FASTER of the two CPUs. `SCLK2` is the keyboard MCU's clock, per `MB60H010.v`'s own label. Sub rate 2001 → 3820 instructions/frame. **P0-5 again, on the other CPU** (`CLKCTRL.v`) |
| **P0-7** | **Sub CPU lost ~55% of its cycles to a blanket VRAM halt.** `FLAGS.v` asserted `SHALTn` for the whole display period whenever the `$d409` mode flag was set, whether or not the sub was touching VRAM — because `MB60H010.v` only hands it the VRAM address bus during blanking (`SVRADRS = SCASSEL ? sub : raster`), so an access mid-display lands at the raster's address. Replaced with a real wait state on the access itself (`sub_vram_wait` in `core.v`, stalling `SCPUCLK`); neither `nHALT` nor `nDMABREQ` could express one, as mc6809i samples both at `CPUSTATE_FETCH_I1`. Sub rate 3976 → 8538 instructions/frame **with the display still clean** |
| **P1-4** | **`$fd37` was not writable at all.** The `x74138_m93` driving `WFD37n` is enabled by `FD0Xn` (`$fd00-$fd0f`), so with `G2A = MADDRBUS[3]` its `Y7` is `$fd07`, not `$fd37`. The multi-page register read back `$00` for ever and every game's VRAM plane selection was silently ignored. Decoded directly from `m22_q8` now, qualified by `WTQEn` (`MDECODE.v`), and latched on the leading edge (`FLAGS.v`) |
| **P4-1j** | Two FDC register writes one bus cycle apart lost one of the pair. The core accepts a write only on a rising edge *as it samples it* on a `ce` tick, so a strobe that goes low and high again entirely between two ticks is never seen as an edge. Ys sets track+sector with one 16-bit store to `$fd19`, lost every sector write, and re-read one sector into three different buffers — status `$00` and byte-perfect data each time. A write is now held back only when the core has not yet *sampled* the strobe low (`gap_done`), so isolated writes keep their exact original timing (`FDC.v`) |
| **P4-1i** | `SEEK` set the head position but not the TRACK REGISTER. A real WD179x steps until the two agree (MAME `wd_fdc.cpp:412`, stepping at `:439`), so after a seek they always match; here `$fd19` read back stale. RESTORE and STEP already maintained it — SEEK was the odd one out (`wd1793.sv`) |
| **harness** | `sim.v` treated `ce_pix` as a one-cycle enable when it is a 2/3-duty clock, doubling every pixel |

---

## P0 — blockers

### P0-1 [FIXED] Every `$fdxx` read returned `$ff` to the CPU

**This is the bug that keeps the screen black.** The main CPU never sees a real
value from any I/O port: not the sub-system BUSY flag, not the keyboard, not the
timer.

`MDECODE.v`'s read decoder (`x74138_m52`) is enabled by `RDEn`, and
`MCPU.v:56` defines

```verilog
assign RDEn  = ~(x74244_Y[6] & x74244_Y[5]);   // ~(RWB & EB)
```

`RDEn` therefore deasserts the instant `E` falls — which is the same instant
`mc6809i.v` latches the data bus (`always @(negedge E)`). By then `RFD05n` has
already gone high and `core.v`'s read mux has fallen through to its
`~IOSn ? 8'hff` default. Real hardware survives this on 74LS138 propagation
delay and the 6809's data-hold window; zero-delay RTL does not.

Contrast the ROM/RAM path, which works: it uses `RDQEn = ~(RWB & (QB|EB))`.
`Q` falls a quarter-cycle *after* `E`, so that strobe still spans the latching
edge.

Evidence — the bus carries `$7e`, the CPU loads `$ff`:

```sh
cd vsim
./obj_dir/Vemu --headless --stop-at-frame 62 --trace-mem fd04-fd05 \
    --trace-cpu io.log --trace-from 60 --trace-until 60 --trace-max 12
#   60 mem  R $fd05 -> $7e  ...  pc=$f899
./obj_dir/Vemu --headless --stop-at-frame 62 --trace-cpu m.log \
    --trace-from 60 --trace-until 60 --trace-max 4
#   60 main  $f899  96 05  LDA <$05   a=ff ... dp=fd
```

**Fix, verified.** One line in `core.v` — enable the I/O read decoder with the
strobe that spans the latching edge:

```diff
 MDECODE u_MDECODE(
   .MADDRBUS ( MADDRBUS ),
-  .RDEn     ( RDEn     ),
+  .RDEn     ( RDQEn    ),
```

With that in place the machine boots: the `$d40a` handshake goes from 1 access
to 40+ in 60 frames, the sub CPU starts executing its drawing routines, and
**F-BASIC prints its banner** ("FUJITSU F-BASIC Version 3.0 / Copyright (C) 1981
By FUJITSU/MICROSOFT / 30530 Bytes Free").

Treat that diff as a proof, not necessarily as the final patch. Two things to
decide before committing it:

- `RDEn` also gates `RFD0Fn`, which is used as an *edge* (`pre = ~RFD0Fn` in
  `ROMS.v`) to flip the boot-ROM/RAM switch. Widening it widens that edge too.
  Check the ROM/RAM switch still behaves after the change.
- The cleaner structural fix is to stop deriving read data from an E-qualified
  strobe at all: decode `$fdxx` reads from `IOSn` + address + `RWB` and let the
  bus mux be stable for the whole cycle, the way MAME and CSP model it. That
  removes a whole class of latent races rather than this one instance.

### P0-2 [verified] `ROMS.v` boot-ROM select needs a reset *edge*, not a level

`ROMS.v:51` latches the boot-ROM select with a flip-flop **clocked by reset
being asserted**:

```verilog
wire ck = ~RESETBn;
always @(posedge pre, posedge clr, posedge ck)
  ...
  else ff_q <= m120_q;
```

If `RESETBn` is already low at power-on, `~RESETBn` never has a rising edge,
`ff_q` keeps its power-on `0`, `RAM1HB2n` stays high, the F-BASIC ROM is never
chip-selected, and every read of `$8000-$fbff` returns `$00`. The boot ROM then
does `LDX $fbfe` (getting `$0000`) and `JMP ,X`, and the machine executes zeroed
RAM forever.

`vsim` works around this by running 64 cycles with reset **low** before
asserting it (`sim_main.cpp`, `reset_prologue`). That models a power-on pulse,
and it is what made everything downstream visible.

**Action:** decide whether the FPGA build is actually guaranteed that edge.
`FM-7_MiSTer.sv:276` uses `reset = RESET | status[0] | buttons[1]`, and `RESET`
from `sys/` is asserted at power-on. If it is high from the first clock, this
flip-flop is relying on Quartus's power-up state. Rewriting it as a normal
synchronous reset-and-load removes the dependency entirely.

### P0-3 [FIXED] `TIMER`, `FLAGS` and `SOUND` latched the *read* bus on writes

`core.v` connects three modules to `MDATABUS_in` (the read mux) where they need
`MDATABUS_out` (the value the CPU is writing):

| Module | `core.v` line | Register affected |
|---|---|---|
| `TIMER` | 343 | `$fd03` beeper/timer command (`cmd <= MDATABUS_in[...]`) |
| `FLAGS` | 413 | `$fd37` VRAM access / display page latch (`m46 <= MDATABUS_in`) |
| `SOUND` | 652 | `$fd0d` PSG BDIR/BC1 (`{bdir,bci} <= MDATABUS_in[1:0]`) |

During a write cycle `MDATABUS_in` resolves to the `~IOSn ? 8'hff` default, so
all three always latch `$ff`. `$fd37 = $ff` means every VRAM plane is
deselected for CPU access and every display page is off — so this will bite as
soon as P0-1 is fixed and software starts using multi-plane graphics.

`PERIPHERAL` (line 365), `KEYBOARD` (630) and `PAL` (616) already take
`MDATABUS_out` and are correct — the fix is to make these three match.

MAME reference: `multipage_w` (`fm7_v.cpp`) stores `data & 0x77`; the core
should end up with the same bit layout in `FLAGS.m46`.

---

## P1 — display path

### P1-1 [FIXED] Glyphs were corrupted on screen although VRAM was correct

Two independent faults, one in `rtl/` and one in the sim harness.

**`rtl/MB60H010.v` — the shift register loaded the wrong cell.** `CRTRAM`'s VRAM
is a synchronous-read RAM (`q` follows `addr` by one `CLKSYS`) while `SVRADRS`
is combinational on `xx`. At a character boundary the RAM has only just sampled
the new address, so its output still holds the *previous* cell — and `SFTLODn`
loaded on exactly that edge. Every character came out with a duplicated column
("FUJIITSU F-BASIIC"). `SFTLODn` is now registered one `CLKSYS` (a third of a
pixel), which lets `q` settle first.

**`vsim/sim.v` — the harness doubled every pixel.** `ce_pix` is `SFTCLK`, which
`clk_en` drives as a real 16 MHz *clock*, high for two of every three `clk_sys`
cycles — not a one-cycle enable. `sim.v` passed it straight to `CE_PIXEL`, so
`sim_main` sampled each pixel twice and the picture came out 2x wide. Now
edge-detected into a one-cycle pulse.

That second one is worth a look on the hardware side too: `FM-7_MiSTer.sv:369`
hands the same 2/3-duty signal to the MiSTer scaler as `CE_PIXEL`, and a scaler
`ce_pix` input normally expects a one-cycle enable.

Verify with:

```sh
cd vsim && make && ./obj_dir/Vemu --headless --stop-at-frame 260 \
    --screenshot 255 --screenshot-name shots/boot.png
```

### P1-5 [verified] The reference emulators disagree on VRAM plane order — MAME is the odd one out

Worth recording before someone "fixes" the display to match MAME.

| VRAM plane | MAME | CSP | 77AVEMU | this core |
|---|---|---|---|---|
| `$0000` | blue | blue | plane 0 | blue |
| `$4000` | **green** | **red** | plane 1 | **red** |
| `$8000` | **red** | **green** | plane 2 | **green** |

MAME's `fm7_v.cpp:1173-1178` reads `code_g` from `+0x4000` and `code_r` from
`+0x8000`. CSP's `vram.cpp:512-514` does the opposite, and 77AVEMU's
`srcColor` builds its index from plane 0/1/2 in the order that agrees with CSP.
**This core follows CSP** (`SDECODE.v`: `SDRAMBn`=$0000, `SDRAMRn`=$4000,
`SDRAMGn`=$8000) and is believed correct. Changing it to match MAME would swap
red and green over the whole display.

The palette byte layout is NOT in dispute — MAME and CSP agree it is
`b`=bit0, `r`=bit1, `g`=bit2, and the top levels match
(`VGA_R=grb[1]`, `VGA_G=grb[2]`, `VGA_B=grb[0]`).

**General lesson: prefer CSP as the primary reference for FM-7 behaviour, with
77AVEMU as the tiebreaker** — it carries notes from experiments on real
hardware. MAME's FM-7 driver is useful mainly for the I/O map; it is littered
with `BAD_DUMP` and disabled code (its VRAM-access halt is commented out at
`fm7_v.cpp:643`).

### P1-2 [RESOLVED - not applicable] 320x200 / 40-column mode

Checked: the width bit lives in `$fd12`, which `fm7_v.cpp` documents as the
"Sub mode status register (FM-77AV or later)" and which is only implemented in
`fm77_state`. It does not exist on an FM-7, so no FM-7 title can select it and
there is nothing to model here. Original note below.

### P1-2-orig [read] 320x200 / 40-column mode is not modelled as a mode

MAME has an explicit width bit (`fm7_v.cpp:828`: "bit 6 (R/W) - Video mode
width 0=640 (default) 1=320", used at `:499` and `:1129`). The core has no
equivalent — it always generates a 640-wide raster.

F-BASIC's own 80-column output renders correctly without it, so this is not
urgent, but any title that sets the width bit will be wrong.

### P1-3 [VERIFIED] `$fd37` bit layout — confirmed against two references

`FLAGS.v` splits `m46` into `VPAGE1n/2n/3n` (bits 0-2, CPU access) and
`DPAGE1/2/3` (bits 4-6, display). Confirmed: MAME masks with `0x77`, and CSP
(`display.cpp:444`) does `accessmask = val & 0x07; dispmask = (val & 0x70) >> 4`.
Both agree with the split here, and the bit-to-plane order matches CSP too.
The register itself is only actually writable as of P1-4.

---

## P2 — keyboard

### P2-1 [PARTLY FIXED] Shift works; Ctrl / Graph / Kana still produce nothing

**Shift is done.** Three separate faults had to be cleared:

- The modifier state was assigned `~press_btn`, so it went true when the
  modifier was *released*. The shift branch could never fire while shift was
  held. Modifiers are now tracked in a clocked block with the obvious polarity.
- The branch bodies were empty `// TODO`s. There is now a JIS shift table:
  uppercase A-Z, the `! " # $ % & ' ( )` number row, and
  `= ~ | ` { + * < > ?`.
- `m132` ("a code is waiting") was clocked by `posedge press_btn`, so pressing
  SHIFT latched whatever stale code was still in `kdata`, and the letter that
  followed produced no new edge at all — `press_btn` was already high — so it
  was never delivered. The real MB88401 sends nothing for a modifier alone.
  `m132` is now set from a decoded non-modifier keystroke, with set winning
  over clear so a key landing on the CPU's acknowledge cycle is not dropped.

Verified: `print 12+34` gives ` 46`, `print "HI!"` gives `HI!`.

Also fixed in passing: the main `/` key produced `"` (`9'h04a` → `$22`). On a
JIS layout that key is `/`, and `"` is shift-2, which the new table provides.

**Still TODO: CTRL, GRAPH and KANA.** Those branches remain empty, so no control
codes, no graphics characters and no kana. `refs/common-src-project/src/vm/fm7/
keyboard_tables.h` has complete `ctrl_key`, `ctrl_shift_key`, `graph_key`,
`graph_shift_key`, `kana_key` and `kana_shift_key` tables — use those. MAME's
`fm7_key_list` is *not* a usable reference here; its own comment says the shift,
ctrl, graph and kana columns are unfilled.

### P2-1b [decision needed] Keyboard layout is JIS-positional, not US

`KEYBOARD.v` maps PS/2 *positions* to JIS characters, which is what a real FM-7
keyboard does. On a US keyboard that means the keycaps lie:

| You want | It is on the US key |
|---|---|
| `+` | shift + `;` |
| `*` | shift + `'` |
| `"` | shift + `2` |
| `@` | `[` |
| `[` | `]` |
| `^` | `=` |
| `:` | `'` |

This is faithful, but it is why `+` feels like it is in a weird spot. Three
options, and it is a product decision rather than a bug:

1. **Keep JIS-positional.** Correct for the hardware; users need a JIS layout
   diagram.
2. **Re-map so US keycaps produce the character printed on them.** Friendlier,
   but no longer what the machine's own keyboard does, and any software that
   reads raw key positions will disagree.
3. **Offer both via an OSD bit**, defaulting to whichever you prefer.

Note `vsim`'s `--key` injector is unaffected either way — it maps ASCII to the
right JIS position itself, so `--key "380:print 12+34"` types what it says.

### P2-2 [read] Keyboard IRQ flag and scancode-read clearing

MAME (`fm7.cpp:226`) documents: the keyboard IRQ flag is cleared when the
scancode is read from *either* `$fd01` (main) or `$d401` (sub). `KEYBOARD.v`
clears its `m132` latch on `~(RESETBn & RFD01n & KACKNGn)`, which covers both —
good — but there is no keyboard IRQ *flag* visible in the `$fd03` cause
register (see P3-1).

### P2-3 [read] Break key

`KEYBOARD.v:23` hardcodes `assign BREAKn = 1;` and the `9'h114` (right ctrl →
break) case is commented out at `:169`. MAME exposes break at `$fd04` bit 1
(`fd04_r`). Wire the key through, and expose the flag.

---

## P3 — main I/O ports

### P3-1 [FIXED] Main CPU was stuck in its IRQ handler with `IRQn` held low

The `$fd03` cause register itself was fine (`CLKCTRL.v:85`) and matches MAME's
`IRQ_FLAG_*` bit order. The clear path was not.

On the schematic the timer flag is a 74LS74 clocked by `_2MS` with an
**asynchronous preset** from the `$fd03` read, so the clear cannot be missed.
`CLKCTRL.v` had that version commented out and sampled `IRQCLRn` on `SVIDEOCLK`
(~2 MHz) instead. `IRQCLRn` is an E-domain strobe roughly a quarter of a
microsecond wide — shorter than `SVIDEOCLK`'s period — so clears were dropped;
and when one *did* land on a `_2MS_en` tick, the second assignment in the block
won and threw it away anyway. `IRQn` ended up permanently asserted and the main
CPU re-entered its handler forever.

Now the flip-flop runs on `CLKSYS`, where the strobe is many cycles wide, with
the clear given priority over the tick (which is what the async preset does).
`_2MS_en` is edge-detected into a one-`CLKSYS` tick to cross the domain.

Result: interrupts went from **2 edges in 11.7 s to 10395**, `IRQn` now idles
between them, and **F-BASIC reaches its `Ready` prompt.**

### P0-4 [FIXED] Sub CPU read `$ffff` from the keyboard port, so every key printed "Copyright"

This is **P0-1 again, on the other CPU** — and the reason it took a second pass
is that the bus trace looked healthy. `--trace-mem-sub d400-d401` showed the
right bytes going by:

```
400 smem R $d400 -> $00
400 smem R $d401 -> $61     'a'
```

but disassembling the sub's FIRQ handler showed what it actually latched:

```
400 sub $fdae  fc d4 00  LDD $d400   a=ff b=ff     <- $ffff, not $0061
400 sub $fdb1  2b 0a     BMI $fdbd                 <- bit 15 set => "function key"
400 sub $fe3d  58 58 58 58                         <- b = $ff << 4 = $f0
400 sub $fe41  8e d2 b0  LDX #$d2b0
400 sub $fe44  3a        ABX                       <- x = $d2b0 + $f0 = $d3a0
```

`$d3a0` is the F-key string table, which still held boot-banner text — hence
"Copyright" for every keystroke, whatever you typed.

Cause: `SDECODE.v:44` had

```verilog
wire m57_6 = ~(SRWB & SEB);   // enables m98, the sub I/O read decoder
```

`SEB` is the sub's `E`, so the strobe drops exactly when `mc6809i` latches, and
`core.v`'s `SDATABUS_in` mux falls through to its `8'hff` default. Fixed by
enabling `m98` with `~(SRWB & (SEB | SQB))`, mirroring the main-CPU fix and
matching what `SRDQEn` already does for the sub's ROM/RAM reads. `SRDEn` itself
is left alone — it is exported but unused, so nothing else moves.

Note the earlier suspicion in this slot (that the main CPU had stopped writing
the shared-RAM aperture, pointing at `SRAM.v` arbitration) was **wrong**. The
main CPU does perform the halt/access/release cycle correctly; it was simply
blocked polling `$fd05` because the sub never finished its command. Two lessons
worth keeping: a healthy *bus* trace does not mean a healthy *CPU register* —
compare the two — and `--trace-mem` was silently starved because it shared its
line budget with `--trace-cpu`, which is now fixed.

### P3-1b [read] `$fd02` is a routing register, not MAME's mask register

MAME models `$fd02` as a plain mask byte (`irq_mask_w`). The core instead
decodes it in `KEYBOARD.v` into three signals — `m77[0]` routes the keyboard to
the main CPU (`KEYINn`) or the sub CPU (`KSTROBEn`), `m77[1]` is `LPMASKn`,
`m77[2]` is `TMMASK`. That is closer to the schematic than MAME is, so it is
probably right, but it means MAME cannot be used as a bit-level reference here.
Check `refs/common-src-project/src/vm/fm7/fm7_mainio.cpp` instead.

### P3-2 [read] `$fd04` attention-IRQ flag always reads "no interrupt"

MAME `fd04_r`: bit 0 = attention IRQ from the sub CPU (`$d404`), bit 1 = break,
both active low, and bit 0 self-clears on read.

`TIMER.v:102` returns `{5'b11111, BUSY, BREAKn, m47_q11}` where
`m47_q11 = RESETBn & ~RFD04n` — during the read itself that is always `1`, so
bit 0 always says "no attention IRQ". The attention latch `m45_q8n` exists and
correctly drives `FIRQn`, and its async clear does fire on the read, but its
state is never presented on the data bus. Put `m45_q8n` in bit 0.

### P3-3 [read] Kanji ROM (`$fd20-$fd23`) missing entirely

MAME maps `$fd20-$fd23` (`kanji_r`/`kanji_w`): `$fd20`/`$fd21` write the
address, `$fd22`/`$fd23` read the two bytes of the 16x16 glyph. `MDECODE.v`
does not decode `$fd20-$fd23` at all and `rtl/roms/` contains no kanji ROM.

Needed for any Japanese text. CSP `kanjirom.cpp` is the cleanest model.

### P3-4 [read] `$fd06`/`$fd07` claim to be an 8251 but are a stub

`RS232.v` returns `$ff` for `$fd06`/`$fd07` and has a bare `// intel 8251A`
comment. MAME maps `$fd06-$fd0c` to `unknown_r` (also `$ff`), so the current
behaviour is not *wrong* for software that only probes — and the boot ROM's
extension scan does probe it. But the TXRDY/RXRDY/SYNDET interrupt sources in
P3-1 come from this chip, so it will need to be real eventually.

### P3-5 [read] `$fff0-$ffff` vectors are ROM, not RAM

MAME maps `$ffe0-$ffef` and `$fff0-$ffff` as **RAM**, seeding only the reset
vector (`fm7.cpp:1738`: `m_vectors[0xe]=0xfe; m_vectors[0xf]=0x00;` → `$fe00`).

The core's `m139` table makes `$ffe0-$fffb` RAM but `$fffc-$ffff` boot ROM, and
`ROMS.v:30` carries a hack — `&MADDRBUS[15:4]` — to force the DOS boot ROM for
`$fffx`, commented "a fix to force vectors from DOS ROM".

Consequence: software cannot install an NMI vector (`$fffc/$fffd`). IRQ, FIRQ
and SWI land in the RAM window and are fine. Worth reconciling against MAME's
model rather than keeping the address hack.

---

### P3-6 [FIXED] Only two boot ROMs exist, and `bootrom_sel` picked the wrong one for setting 2

The OSD offers four boot ROMs (`FM-7_MiSTer.sv:212`,
`"O[11:10],BootROM,Basic,1,2,3"`), but `rtl/roms/` contains only two images —
`boot_bas.rom` and `boot_dos_a.rom` — and `ROMS.v:30` chooses between them with

```verilog
wire [7:0] m152_q = SW2[0] || &MADDRBUS[15:4] ? m152_2_q : m152_1_q;
```

Testing `SW2[0]` alone means setting **2** (`SW2 = 2'b10`) selects the *BASIC*
boot ROM, while settings 1 and 3 select the DOS one. Meanwhile
`m120_q = ~|SW2` loads `ff_q` with `0` for any non-zero setting, which
deselects the F-BASIC ROM at `$8000-$fbff`.

So setting 2 runs the BASIC boot ROM with no F-BASIC ROM mapped — reproducing
exactly the `LDX $fbfe` → `JMP ,X` → `$0000` runaway described in P0-2. That is
the `RUNAWAY-INTO-IO` in the sweep table, and it is a real bug rather than a
consequence of the missing FDC.

Decide what the four settings are meant to be (the real FM-7 has a two-position
BASIC/DOS switch), then either reduce the OSD to two entries or add the missing
ROM images and select on the full 2-bit value.

### P3-6b [verified] The four OSD boot-ROM slots are the four banks of M152

`rtl/roms/TL11_11_M152.BIN` is the real 2 KB boot ROM chip -- M152 is exactly
what `ROMS.v` calls its boot ROM instances -- and it holds **four 512-byte
banks**, which is what the OSD's four settings are for. MAME says the same
thing about its own 0x800 `boot` region ("actually 0.5K banks of the same ROM",
`fm7.cpp:2179`).

| bank | maps at `$fe00` | what it is |
|---|---|---|
| 0 | loads boot sector to **`$0100`**, `LDX #$0100` | == `boot_bas.rom` (bar the last 2 bytes). **This is the one that boots disks.** |
| 1 | `JMP $0300` at `$fe4c` | another revision |
| 2 | loads to `$0300`/`$0400`, `JMP $0300` | == `boot_dos_a.rom` |
| 3 | all `$ff` | empty |

`boot_bas.rom` is byte-identical to MAME's (crc32 `c70f0c74`); `boot_dos_a.rom`
matches no MAME FM-7/FM-8 boot ROM (ours `bf441864`, MAME's `boot_dos.rom` is
`198614ff`) and is bank 2 of this chip.

**The practical upshot: boot disks with `--bootrom 0`.** Bank 0 loads the boot
sector at `$0100`, which is what real disks require. Thexder proves it by
itself, independently of any ROM: its boot sector carries an 8-byte disk
parameter block at its own start + 2 and reaches it with `LDX #$0102`, which is
only correct at `$0100`. Loaded at `$0300` by bank 2 that instruction points into
the stack, the loader hands the ROM garbage -- a WRITE of track 0 **sector 0** --
the ROM's error decoder at `$ffad` returns error 11/12, and the boot sector halts
on `BRA $0340`.

So `bootrom 1/2/3` selecting bank 2 is why disks looked unbootable. Nothing is
missing and no ROM needs patching; what needs fixing is `ROMS.v`'s selection so
the OSD's four settings map onto the four banks of `TL11_11_M152.BIN` instead of
onto two loose 512-byte files, one of which is the wrong bank for booting. See
P3-6 above for the selection bug itself.


## P4 — missing peripherals

### P4-1 [WORKING] Floppy disk controller — games boot

**Done: the controller is in, the `.d77` parser is in, images mount, and a real game boots from one.**
`rtl/FDC.v` is no longer a stub and `rtl/wd1793.sv` understands `.d77`.

- `rtl/wd1793.sv` + `rtl/wd1793_dpram.v` vendored from
  `refs/fdc/spectrum-wd1793/` (Slavinsky / Sorgelig, GPLv2+, matches this
  repo's licence). The MB8877 is WD1793-compatible with a normal, non-inverted
  bus -- MAME's own table, `refs/mame/src/devices/machine/wd_fdc.h:31` -- and
  MAME never calls `dden_w()` for the FM-7, so it runs permanently in MFM,
  which is what 2D media needs.
- `rtl/FDC.v` is the glue and handles the four mismatches the survey predicted:
  register split (`$fd18-$fd1b` to the core, `$fd1c-$fd1f` implemented here per
  MAME `fm7.cpp` `fdc_r`/`fdc_w` cases 4-7), edge detection on
  `FD_WEn`/`FD_REn` (level-active over a whole 6809 E half-cycle vs the core's
  single-cycle strobes), DRQ/INTRQ inversion (core is active high, `MFD.v`
  wants active low), and a 1 MHz `ce` matching MAME's `8_MHz_XTAL/8`.
- The block-device chain exists end to end: `FDC.v` -> `core.v` -> both top
  levels, `hps_io` on hardware and `SimBlockDevice` in `vsim`, with
  `--disk <file.d77>` in `sim_main.cpp`. `RWMODE(1)`, so writes go back to the
  image, which is what `refs/fdc/RECOMMENDATION.md` argued for.

#### The `.d77` scanner [DONE]

`wd1793.sv`'s mount-time byte-stream scanner now dispatches on format and has a
`.d77`/`.d88` parser alongside the original EDSK one. It fills the *same*
`edsk[]` / `spt[]` / `edsk_size` / `spt_size` structures, so the whole runtime
path (`STATE_SEARCH_1`, `buff_a <= edsk_offset`) is reused untouched.

Verified against the real thing: `make DEBUG_FDC=1` makes the scanner print one
line per sector it tables, and all **1265 sectors of `Thexder [b].d77` match a
reference decode of the same file exactly** -- physical track/side, the recorded
C/H/R, every data offset, and the CRC flag. `refs/fdc/d77-format.md` documents
the format itself.

Four things that were not obvious, recorded so they are not rediscovered:

- **Format detection had to be restructured, not extended.** EDSK's check was
  `if((scan_addr < 16) & (sig_pos != scan_data)) var_size <= 0;` -- it clears
  `var_size` on the first mismatching byte, and a `.d77` opens with a 17-byte
  disk name, so that killed the scan immediately. Both formats now accumulate a
  verdict and commit once at byte `$1f`: late enough to have the signature *and*
  the `.d77` size field, early enough that neither format's real content has
  started (EDSK's fields begin at 48, `.d77`'s track table at `$20`). `.d77` has
  no magic number; it is identified by its total-size field at `$1c` agreeing
  exactly with `img_size`.
- **`blk_size` was wrong for 128- and 256-byte sectors** and it had to be fixed
  before any `.d77` could read correctly. It hardcoded "one 512-byte block is
  enough", which only holds if the sector data is 512-aligned. `.d77` puts a
  16-byte header immediately before every sector, so with the usual 256-byte
  sectors the stride is 272 and alignment is essentially random: **593 of
  Thexder's 1265 sectors straddle a block boundary**, and every one of them
  would have read its second half out of a stale buffer. Now computed from the
  start offset and the sector size, which reproduces the original values for
  size codes 2 and 3.
- **The track offset table is compacted at parse time.** Absent tracks (offset
  0) are dropped as the table is read, so the second pass walks a zero-free list
  and never has to skip entries mid-stream -- which it could not do anyway,
  since the scan is a single forward pass that cannot look backwards.
- **Physical track/side come from the table index, C/H from the sector header.**
  They disagree on protected disks and both matter: the search matches on
  physical position, `READ ADDRESS` reports what was recorded.

The scan reads the entire image (it must -- headers are interleaved with data),
so `ready` is held low until it finishes. At the MB8877's real 1 MHz that would
be ~2.8 s for a 345 KB image, long enough that a boot ROM already polling the
drive gives up first, so `FDC.v` free-runs `ce` while `prepare` is high. The
command FSM is idle throughout and `ready` is low, so nothing else is affected;
on hardware the SD block reads then set the pace. In `vsim` that takes the scan
from ~170 frames to under 8, with the parse unchanged.

Reproduce the check:

```sh
cd vsim && make DEBUG_FDC=1
./obj_dir/Vemu --headless --stop-at-frame 20 \
    --disk "../software/Fujitsu FM-7/Thexder (Game Arts)/Thexder [b].d77" \
    | grep D77
# D77SCAN done: fmt=2 bytes=344768 tracks=80 sectors=1265 spt_size=80 wp=1
# plus one D77SEC line per sector:
#   D77SEC <track> <side> <C> <H> <R> <N> <data offset> <crc flags>
```

#### Three bugs between the CPU and the controller [FIXED]

The parser was verified long before a disk could actually be read, because
nothing on the host side of the FDC had ever been exercised. Three separate
faults sat in series, and each one hid the next:

1. **`MFD.v` declared `FD_Dout` and never drove it.** The CPU's write data never
   reached the controller, so every command byte arrived as `$00` (RESTORE with
   no flags) and the drive and side latches could never be set. Harmless while
   `FDC.v` was a stub; fatal the moment it was not. One line: `assign FD_Dout =
   EDB;`.
2. **The write strobe could not survive the clock crossing.** `FDC.v` turned
   each access into a single `CLKSYS` pulse and handed it to a module that only
   samples on its 1 MHz `ce` — a 1-in-48 chance per access, in practice never.
   Measured: the boot ROM issued **11 register writes and the controller
   received 0**. Accesses are now latched (address, data, direction) and the
   strobe is held until one `ce` tick has consumed it.
3. **`$fd1f`'s read decode was qualified by `E` alone.** This is P0-1 for the
   third time, and worth internalising: an `E`-qualified read strobe deasserts
   on exactly the edge `mc6809i` latches the bus. `$fd1f` sits outside `FD_CSn`,
   so `core.v`'s read mux fell straight through to `~IOSn ? 8'hff` and the CPU
   latched **`$ff` — DRQ and INTRQ both set, always**. The boot ROM's transfer
   loop (`LDB $fd1f; BPL ...; LDA $fd1b; STA ,Y+`) therefore took a byte on
   every pass and never saw the command end, storing 64008 bytes off the end of
   its buffer. Now `(E|Q)`, which spans the latching edge.

The lesson from the third one is the same one P0-1 and P0-4 taught, so it is
worth stating plainly: **when an I/O read misbehaves, check its strobe
qualifier before anything else.** A bus trace looks perfectly healthy in all
three cases — the wrong value only exists at the instant the CPU samples.

#### Per-sector CRC status [DONE]

`.d77` carries a status byte per sector (`+$08`: `$a0` ID CRC error, `$b0` data
CRC error) that none of the surveyed cores' native formats have. The scanner
keeps it (two extra bits per `edsk[]` entry) and `STATE_SEARCH_1` sets
`s_crcerr` from it on reads. **`Thexder [b].d77` uses this**: track 1 side 1 has
a single sector, with a lying address mark (C/H/R = 200/186/233) and status
`$b0`. That is copy protection, and this core now reproduces it.

#### Verified end to end

With those cleared, the DOS boot ROM drives the controller correctly: it probes
the drives on `$fd1d` (and the readback now agrees, including MAME's "reject any
drive above 1"), issues `RESTORE`, sets track / side / sector on
`$fd19`/`$fd1c`/`$fd1a`, issues `READ SECTOR`, and reads the bytes out of
`$fd1b`.

**The bytes the CPU receives are the bytes in the image.** Both sectors read
during boot arrive intact -- and the second one, at image offset 976, straddles
a 512-byte block boundary, so it is exactly the case the `blk_size` fix was for:

```sh
cd vsim && ./obj_dir/Vemu --headless --bootrom 1 --stop-at-frame 300 \
    --disk "../software/Fujitsu FM-7/Thexder (Game Arts)/Thexder [b].d77" \
    --trace-mem fd1b-fd1b --trace-max 900000
# the $fd1b read stream is image[704:960] followed by image[976:1232], exactly
```

#### Still to do

1. **[DONE] The `boot-basic` regression turned out to be the sub-CPU handshake.**
   Making the FDC work briefly broke `--bootrom 0`: instead of the F-BASIC banner
   it showed `F...Bad / Syntax Error / Ready`. It is fixed, and the cause is
   worth keeping because it was not where it looked.

   It was never an FDC bug. `$fd05` bit 7 reported only `BUSY`, and `FLAGS.v`
   holds that flip-flop asynchronously *cleared* while the sub CPU is halted
   (`s3 = RESETBn & SHALTACn`). So the standard sequence -- request the halt on
   `$fd05`, poll until it takes effect, then touch shared RAM -- could never see
   the halt take effect. Bit 7 is now `BUSY | ~SHALTACn`, matching MAME's
   `sub_busy || sub_halt` (`fm7_v.cpp` `subintf_r`).
 
   Why nothing caught it for so long: F-BASIC's other loop waits for bit 7 to
   *clear* (`LDA <$05 / BMI`), and a permanently-zero bit satisfies that
   instantly. The handshake looked healthy because every path exercised so far
   polled the direction that a broken bit happens to answer correctly. All the
   FDC did was add a ~0.4 s drive-detect delay, which shifted the boot enough to
   take the other path. Thexder's loader took that path deliberately and hung on
   it forever at `$100c`.

   Lesson worth keeping alongside the P0-1 one: **a flag that is stuck can still
   look correct to half the code that reads it.** Check both polarities.

2. **[DONE] Thexder boots.** Kept here because the diagnosis chain is worth
   having. The symptom was the sub CPU running away into zeroed VRAM; the cause
   was that it could not keep up with a transfer that never waits for it.

   Thexder hands its sub-CPU program across the shared window one byte at a
   time. Sub side, a stub it plants in shared RAM:

   ```
   $d39e  BSR $d3b3        ; handshake
   $d3a0  BMI $d3a9        ; $d3fe bit7 set -> done, go run the program
   $d3a2  LDA $d3ff        ; else take the byte
   $d3a5  STA ,U+          ;   append it (U starts at $c000, Console RAM)
   $d3a7  BRA $d39e
   ```

   Main side, per byte: read `$fcfe`, write it back **incremented**, then write
   the data to `$fcff`. **`$fcfe` is a backlog counter, not a flag, and the main
   CPU never waits** — measured distribution of what it read there: 226 x `$00`
   (sub keeping up), then 62 x `$01`, 62 x `$02`, 36 x `$03`, 23 x `$04`, the
   backlog growing as the sub fell behind. Anything not collected in time is
   overwritten. So it was purely a sub-CPU throughput problem, and both P0-6 and
   P0-7 fell out of chasing it:

   | | sub instr/frame | bytes transferred | result |
   |---|---|---|---|
   | originally | 2001 | 224 / 433 | sub runaway in zeroed VRAM |
   | sub clock fixed (P0-6) | 3820 | 422 / 433 | sub back in its ROM idle loop |
   | VRAM wait state (P0-7) | **8538** | **430 / 433** | **title screen** |

   **On comparing a transfer against the disk, two traps.** First, use the
   *logical sector-data stream*, not raw file offsets: the program spans several
   sectors and `.d77` interleaves a 16-byte header before each, which otherwise
   shows up as bogus 16-byte "drops". Second, the loader **relocates** as it
   sends — a run of differing bytes that are all high bytes of 16-bit words with
   a constant delta (here +$1300) is a patched address table, not corruption.
   Both cost time here.

   ```python
   # concatenate every sector's data, skipping headers, then find the program
   logical.find(bytes.fromhex('10ced000ced383'))   # -> offset 207299
   ```

3. **[FIXED — see P4-1j] Ys deadlocked on a swallowed sector-register write.**
   Kept here because the *method* is the reusable part: the bug was invisible to
   every check that asked "did the read work?", because the read always worked.

   The fix is in `FDC.v` (P4-1j). Ys now streams content off the disk — tracks
   37, 38 and beyond, both sides, sequential sectors — instead of wedging on
   track 0, and requests the sectors it actually wants.

   **It still does not boot**, so there is a further bug past the FDC — but the
   loading path itself is now demonstrably correct:

   - Ys drives the ROM/RAM switch exactly as CSP describes (read `$fd0f` → ROM,
     write → RAM, `fm7_mainio.cpp:771`): it reads at frame 128, **writes at
     frame 140** to open the RAM window, and reads back at 265 and 323.
   - With that window open it writes **256 bytes to every page from `$8000`
     through `$dfff`** — a clean contiguous 24 KB program load, no gaps, no
     double-writes. Our `$fd0f` handling in `ROMS.v` matches CSP, and `MRAM.v`
     backs the full 64 K, so this whole path is working.

   **It is not deadlocked — it is waiting for a keypress.** Main sits in

   ```
   $1026  LDA  $11a4      ; Ys's last-key variable
   $1029  CMPA #$20       ; SPACE?
   $102b  BEQ  $1031
   $102d  CMPA #$0d       ; RETURN?
   $102f  BNE  $1026
   ```

   and `--key '820:@SPACE'` moves it on: by frame 1600 main is in a counted
   accumulate loop at `$1471 ADDD ,S / LEAY -1,Y / BNE $1471` instead. Screen
   still blank, so there is more to find, but the "hang" was a prompt.

   **The main/sub machinery is exonerated too**, by measurement rather than
   argument:

   - Ys halts the sub properly: `$fd05 <- $80` and `<- $00` **4987 times each,
     perfectly paired**, polling until bit 7 reads back set.
   - Every main-side write into the aperture happens with `SHALTACn` low —
     `DEBUG_SRAM` counts **526337 accepted, 0 misdirected** for Ys and 156699/0
     for Thexder. (Worth knowing: `wr_n` is gated by `SUBSELn`/`WTQEn` but the
     address/data mux by `SHALTACn`, so a write outside a halt would not be
     dropped, it would land on whatever the sub is addressing. It never happens.)
   - The sub sees what main writes: it reads `$d380 -> $0f`, exactly the `$0f`
     main put in `$fc80`. `$d382` reads `$00` because **the sub itself clears it**
     after consuming a command (`smem W $d382 <- $00 pc=$e038`) — that is the
     handshake working, not a lost byte.

   The sub's `$e13e` loop is therefore correct behaviour: it is idling with no
   command pending. `$e13e` is *sub* address space, not the main CPU falling into
   F-BASIC.

   > **Trap, now fixed in the harness:** `--trace-mem`/`--trace-mem-sub` ignored
   > `--trace-from`, and the line cap truncates from the *start* of the run. A
   > sub-CPU window requested at frame 760 came back full of frame 1-124 data and
   > read exactly like a stuck handshake. `in_trace_window()` in `sim_main.cpp`
   > now applies the window to the memory traces too. **Always check the frame
   > range and whether the line count equals `--trace-max`** before believing a
   > trace — an exact match means it was truncated.

   The chase below is what it took to find the FDC bug.

   `Ys (FM7) (Disk A).d77` mounts and parses perfectly (see below), issues 6
   RESTOREs, a SEEK and 19 READ SECTORs, then both CPUs wedge:

   ```
   main  $01c9  TSTA / BNE $01c9      <- A is never reloaded: a hang, not a wait
   sub   $c03e  LDB -1,U / BEQ $c03e  <- waiting for the next byte
   ```

   **What the FDC actually does, measured (not inferred):**

   - All **19 sector matches are exact** — a `WDMATCH` probe in `STATE_SEARCH_1`
     printing requested vs. matched `(track, side, sector)` shows `want ==
     entry` every single time, including on side 1.
   - The three side-1 reads transfer **1024 bytes each, byte-for-byte identical
     to the image at offset 7136**, and end with **status `$00`** — no CRC error,
     no lost data, no seek error.
   - Ys's inner loop is `LDA <$1f / BPL / LDA <$1b / STA ,U+` with `DP=$fd`, i.e.
     poll `$fd1f` for DRQ then read `$fd1b`. It runs correctly to completion.

   So the drive returns perfect data and the game still fails.

   > **Correction to an earlier entry here:** a previous pass claimed two side-1
   > sectors returned side-0 data. That was wrong — a bug in the *Python trace
   > analyser*, which mis-attributed `(track, side, sector)` to data reads. There
   > was never a side-select defect. The `WDMATCH` probe above is the reliable
   > way to ask this question, because it reports the RTL's own match decision
   > rather than reconstructing it from the bus log.

   **Where it really goes wrong.** The failing code is a directory search:

   ```
   $020e  LDY  $ffee        ; -> $01d0, the 6-byte filename to match
   $0212  LDB  #$06
   $0214  LDX  $fff0        ; walks $1780, $1790 ... $17f0 in $10 steps
   $021d  LDA  ,X+          ; a=00 EVERY iteration
   $021f  CMPA ,Y+          ; never equal
   $0228  DEC  $ffe9        ; entry counter
   $022d  LDA  #$ff / RTS   ; not found -> error code 1 -> hang at $01c9
   ```

   `LDA ,X+` returns `$00` on every entry because **`$1780-$17ff` is never
   written**: a `--trace-mem 1780-17ff` window over frames 130-156 records 8
   reads and **0 writes**. Ys is searching a directory buffer nothing ever
   loaded.

   A write map of `$0800-$17ff` explains the layout — pages `$08`-`$0f` take 512
   writes each and `$10` takes 256, i.e. two overlapping loads:

   | region | source | size |
   |---|---|---|
   | `$0100-$10ff` | boot ROM's 16-sector load of track 0 side 0 | 4096 |
   | `$0800-$0bff` | one 1024-byte side-1 sector read | 1024 |
   | `$0c00-$0fff` | another 1024-byte side-1 sector read (retried) | 1024 |

   **`$1100-$17ff` is untouched**, and the directory is expected at `$1780`.

   **Boot ROM bank is settled: bank 0 is the only one that works.** Banks 1, 2
   and 3 never reach Ys's code at all — 2 sector matches and stuck in ROM at
   `$f20c`, versus bank 0's 19 matches and Ys's own loader running. So this is
   not a `--bootrom` selection problem.

   **The tell, and the actual bug.** The three 1024-byte reads went to three
   *different* destinations (`$6000`, `$0800`, `$0c00`), which is not what a
   retry looks like — a retry rereads into the same buffer. Ys was asking for
   three different sectors and being handed the same one. Cross-checking the bus
   log against `WDMATCH` showed the sector register writes going out and never
   arriving:

   ```
   fd19 = $00   (pc=$02a8)      <- track,  accepted
   fd1a = $01   (pc=$02a8)      <- sector, SWALLOWED
   fd18 = $80   (pc=$02b1)      -> WDMATCH want sec=3, not 1
   ```

   Both writes come from the same instruction — a 16-bit store to `$fd19` — so
   they land in consecutive bus cycles, 814 ns apart, shorter than a `ce`
   period. The ROM's driver at `pc=$ff6d` spaces its writes out, which is why
   the first 16 sectors always read correctly and only Ys's own driver was hurt.

   **The mechanism is subtler than "two writes at once", and getting it wrong
   cost two failed fixes.** The core accepts a write on a rising edge *as it
   samples it*, on `ce` ticks. The strobe does not have to still be high when
   the second write arrives — it only has to have gone low and back high
   *between* two ticks. The core then samples high at tick N, high again at
   N+1, never observes the low, and the second write is not an edge.

   - **Attempt 1** — queue every write, release one per `ce` with a gap tick.
     Fixed Ys, **blanked Thexder**. The FDC was provably fine under it (all bus
     writes delivered in order, no rejected commands, no register writes dropped
     on BUSY); the extra latency on *every* write was enough to break Thexder's
     already-marginal main/sub byte pump.
   - **Attempt 2** — engage the queue only when `acc_wr` is still high at the
     bus edge. Thexder came back, **Ys broke again, and the collision counter
     read zero**: by the time the second write arrives a `ce` tick has usually
     already cleared the strobe, so this test cannot see the failure at all.
   - **What works** — track whether the core has *sampled* the strobe low since
     the last write was handed over (`gap_done`). Isolated writes keep their
     exact original timing; a write is held only when it genuinely would be
     lost. Ys now requests side 1 sectors 3, 1, 2 correctly (25 writes rescued),
     Thexder's title screen renders, and all 8 rows of `run_tests.sh` are
     unchanged — `boot-basic` is identical to baseline at 5189/9380.

   Worth generalising: a strobe crossing into a slower `ce` domain has to be
   held until the consumer has sampled **both** levels, not just the active one.
   Counting collisions at the producer's edge measures the wrong thing.

   **Two dead ends worth not repeating**, both eliminated by direct measurement
   rather than reasoning: the core's `if (!s_busy)` gate on TRACK/SECTOR writes
   (instrumented — it never once fired), and boot-ROM bank selection (banks 1, 2
   and 3 never reach Ys's code at all; bank 0 is correct).

   Ruled out already: the SEEK track-register bug (P4-1i) was found while
   chasing this and is genuinely fixed, but it did not change Ys's behaviour.
   Also ruled out: **no copy protection is involved** — every one of Ys's 411
   sectors has density `$00`, deleted-mark `$00` and status `$00`, so the
   deleted-data and CRC-status paths are not being exercised. (Thexder, by
   contrast, has exactly one sector with `deleted=$10`/`status=$b0`.)

   **Ys is a much better parser test than Thexder** and it passes: 411 sectors
   over 80 tracks, **395 of them `N=3` (1024-byte) mixed with 16 `N=1`**, all 411
   matching a reference decode exactly. Thexder is uniform 256-byte, so this is
   the first real exercise of the multi-block read path and of per-sector size
   codes — a fixed-geometry reader could not touch this disk at all.

4. **Second drive.** `FDC.v` accepts one image. The FM-7 supports two, and
   `$fd1d` already decodes the drive number (MAME rejects anything above 1).
   Needs a second `img_mounted`/`sd_*` set and a second `wd1793`, or one
   controller with two tables.
5. **2DD media.** `edsk[1992]` bounds the sector table. 2D (40x2x16) needs 1280
   and fits; 2DD at 16 sectors/track would need 2560. The scanner stops cleanly
   at the bound rather than wrapping, and says so under `DEBUG_FDC=1`. Widening
   means `edsk_addr`/`edsk_start`/`edsk_size`/`edsk_next` go from 11 to 12 bits.
6. **Multi-disk `.d88`.** `.d88` allows several images concatenated in one file;
   `.d77` in practice never does. The size check at `$1c` would reject such a
   file outright, which is at least a safe failure.

Test material: 2 loose `.d77` under `software/Fujitsu FM-7/Thexder (Game
Arts)/`, and 195 `[FD]` `.7z` archives alongside them.

### P4-2 [DONE] Joysticks

Both sticks work, on the PSG's I/O ports where the FM-7 puts them. Verified end
to end: with stick 1 held `up`+`A`, driving the PSG by hand from F-BASIC

```
poke64781,3:poke64782,15:poke64781,2:poke64782,32:poke64781,3:poke64782,14:poke64781,1:?peek(64782)
```

prints **238** (`$ee`) -- bit 0 (up) and bit 4 (button A) low, everything else
high, exactly as predicted. `$fd0d` = 64781 and `$fd0e` = 64782.

Protocol, from `refs/common-src-project/src/vm/fm7/joystick.cpp`:

  * write PSG **register 15** (port B) to select -- high nibble `$2` picks
    stick 0, `$5` picks stick 1, anything else selects none
  * read PSG **register 14** (port A) to get it, ACTIVE LOW, as
    `{1, 1, ~buttonB, ~buttonA, ~right, ~left, ~down, ~up}`, or `$ff` when
    nothing is selected

Implemented in `rtl/SOUND.v` by snooping the PSG bus rather than inside
`ym2149_audio.v`, which has no I/O ports at all and is machine-translated from
VHDL (`n###_o` signal names) -- adding a register file there would have been far
more invasive. `SOUND.v` tracks the register address from the `{bdir, bc1}`
protocol on `$fd0d` plus the data writes on `$fd0e`.

`FM-7_MiSTer.sv` gained a `J1,Button A,Button B;` line in `CONF_STR`; there was
none, so buttons were not mappable.

**Two traps worth knowing.** F-BASIC 3.0's `STICK()` is useless for testing this
-- it returns 0 and never touches `$fd0d`/`$fd0e` at all, so it does not read the
PSG joystick in this ROM. And Thexder does use the PSG, but only for sound
during the parts traced so far; it had issued no joystick selection by frame 760.
Hence the poke-it-by-hand test above.

In `vsim`:

```
--joystick  <frame>:<buttons>[:<hold>]   up down left right a b fire none, '+'-separated
--joystick2 <frame>:<buttons>[:<hold>]
--joystick-hold <frames>                 default 10
```

State is held between events, so a stick stays where it was put. `make
DEBUG_JOY=1` prints every selection and every read.

CSP `joystick.cpp` also implements the FM-7 mouse on the same port, which can
follow later.

### P4-2-orig [read] No joystick

The FM-7 joysticks hang off the PSG's I/O port B — CSP wires it explicitly in
`refs/common-src-project/src/vm/fm7/fm7.cpp:626`:
`opn[0]->set_context_port_b(joystick, ...)`.

`ym2149_audio.v` exposes no I/O ports at all (no `IOA`/`IOB`), `SOUND.v` does
not connect any, and `core.v` has no joystick input — the core's only input is
`ps2_key`. So this needs the PSG I/O ports added first, then the port wired to
`joystick_0`/`joystick_1` in `FM-7_MiSTer.sv`.

CSP `joystick.cpp` also implements the FM-7 mouse on the same port, which can
follow later.

### P4-3 [DONE, needs an ear] `SOUND.v` had a floating select

`sel_n_i` is now driven. Per the header of `ym2149_audio.v` it divides the PSG
strobe: 0 = undivided, 1 = divide by two. The FM-7's AY-3-8910 runs from a
1.2288 MHz master clock and halves it internally, and `en_clk_psg_i` here is
already 1.2 MHz, so the divided setting is the one that puts the tone counters
at the right rate -- undriven (effectively 0) made every pitch an octave sharp.

That is reasoning, not measurement. **Worth confirming by ear** against a
recording of real hardware before trusting it.

### P4-3-orig [read] `SOUND.v` has a floating select

`SOUND.v:31` declares `wire sel_n_i;` and passes it to `ym2149_audio` without
ever driving it. Drive it explicitly (the YM2149 `SEL` pin picks the clock
divider — it changes the pitch of everything).

### P0-5 [FIXED] Main CPU ran at FM-8 speed (2 MHz), not FM-7 speed (1.2288 MHz)

`core.v:226` tied `CLKCTRL`'s `SW2` to `1'b0`. `CLKCTRL.v:66` uses it as

```verilog
assign MCPUCLK = switch ? CLK4_9 : SCLK1;   // 4.9152 MHz -> E = 1.2288 MHz
                                            // vs SCLK1  -> E = 2 MHz
```

so the machine ran ~60% too fast. The same bit is reported on `$fd00` bit 0, and
`CLKCTRL.v`'s own comment notes the BIOS reads it to choose between two
different cassette routines — so the core was also advertising FM-8 mode to
timing-critical code. Now `1'b1`.

Confirmed by measurement: main-CPU rate dropped from 9107 to 4916 instructions
per frame, and boot / `print 12+34` / `print "HI!"` all still pass.

Note this retimes everything, so `vsim/shots-ref/` needs re-baselining and the
key frame numbers in `run_tests.sh` may want retuning.

### P4-4 [PARTLY FIXED] Tape transport is correct; F-BASIC still never syncs

**Fixed:** `$fd02` now matches MAME (bits 6-4 forced high, printer lines tied
high instead of read from the undriven `CN2`, and bit 7 reads high when the
motor is off). End-of-tape works — a run now stops at `$03a3b4 of $03a3b6`,
exactly the 238518-byte image size, where it used to run on to `$081392`.
`addr` powers up at `$16` instead of `$62`.

**Still broken:** F-BASIC sits on `Searching` forever. Three candidate causes
have now been eliminated by test -- the `$fd02` bits, the end-of-tape overrun,
and the CPU clock rate (P0-5) -- and none of them was it.

#### Resume here

Reproduce the failure (about 4 minutes):

```sh
cd vsim
./obj_dir/Vemu --headless --tape "../software/Space Warp.t77" \
    --key '320:load""' --key '420:@RETURN' --stop-at-frame 4200 \
    --screenshot 4190 --screenshot-name shots/tape.png
```

Expected today: `tape: motor on ~90%`, `sdram addr $03a3b4 of $03a3b6 (100.0%)
END OF TAPE`, and the screen stuck on `Searching`. There are 18 real dumps in
`../software/*.t77`; several are marked `{loadm}` and need `LOADM"` rather than
`LOAD"`, so try a plain one first.

**Already ruled out by test — do not re-chase these:**

- `$fd02` upper bits (fixed, P4-4a).
- Running past end of image (fixed, P4-4b).
- CPU clock rate: the machine was at FM-8 2 MHz, now correctly 1.2288 MHz
  (fixed, P0-5). Did not change the symptom.
- Tick rate / total tape length. Summing the durations in the image gives
  4571863 ticks; at the core's 9.125 us tick (`DIV_9us` = 218 at 48 MHz) that
  is 41.7 s, and the run takes about that. Good to 1.4%.
- Bit-edge count: 119249 edges against 119251 entries in the file, so every
  transition in the image reaches `cin`.

**The measurement that has NOT been taken.** Trace `$fd02` reads against `cin`
transitions while the screen says `Searching`:

```sh
./obj_dir/Vemu --headless --tape "../software/Space Warp.t77" \
    --key '320:load""' --key '420:@RETURN' --stop-at-frame 900 \
    --trace-mem fd02-fd02 --trace-max 5000000 > fd02.log
```

That separates two very different failures: if `$fd02` is barely read, the BIOS
never entered its sampling loop and the problem is upstream (motor/relay/mode
select). If it is read hard and the returned bit 7 does toggle, the routine is
sampling but the pulse widths do not match what it expects.

Remaining suspects, in order:

1. **Sample polarity.** `cin` may be inverted relative to what the BIOS wants.
   Cheap to test: invert `sout` in `t77_decode.v` and re-run.
2. **Motor-on lead-in.** `t77_decode.v:37` waits `init = 16'h4000` CLKSYS cycles
   (~341 us) after motor-on before it starts sending. A real deck has seconds of
   leader; the BIOS may need to see idle tone first.
3. **`LOAD""` vs `LOAD"`.** Confirm which form these dumps expect, and whether
   the `{loadm}` ones need `LOADM`.

Useful reference: 77AVEMU's `src/fm77av/datarecorder/` and `t77lib` are the
cleanest description of how a T77 is meant to be replayed; MAME's
`src/lib/formats/fm7_cas.cpp` handles both `.t77` and `.wav`.



Tested with `../software/Space Warp.t77` (one of 18 real dumps):

```sh
cd vsim
./obj_dir/Vemu --headless --tape "../software/Space Warp.t77" \
    --key '320:load""' --key '420:@RETURN' --stop-at-frame 3200 \
    --screenshot 3190 --screenshot-name shots/tape.png
```

The transport is **healthy**: motor on 86.7% of the run, 119250 cassette-bit
edges against 119251 entries in the file, so the whole image was played. The
timing base checks out too — summing the durations gives 4571863 ticks, which at
the core's 9.125 us tick (`DIV_9us` = 218 at 48 MHz) is 41.7 s of tape, and it
took about that long.

But the screen sits on `Searching` forever: F-BASIC sees transitions and never
locks onto them. Three things to look at:

1. **`$fd02` upper bits are wrong.** MAME's `cassette_printer_r` returns
   `ret |= 0x70` — bits 6, 5 and 4 always set — plus real printer status in
   bits 3..0. `PERIPHERAL.v` returns
   `{ cin, 1'b0, CN2[6], CN2[3], CN2[12], CN2[16], CN2[7], LPBUSY }`, and
   **`CN2` is declared but never driven anywhere in the module**, so bits 6..1
   read as 0. Bit 7 (`cin`) has the same sense as MAME, so the sample polarity
   is probably right, but everything around it is not.
2. **MAME also forces bit 7 high when the motor is off** ("cassette input is
   high when not in use"). The core drives `cin` from `t77_decode` regardless.
3. The 9.125 us tick is 1.4% fast against a nominal 9 us. Probably tolerable,
   but worth ruling out if 1 and 2 do not explain it.

**No end-of-tape handling.** `t77_decode.v` increments `addr` forever; the run
above finished at SDRAM `$081392` (528786) against a 238518-byte image, i.e. it
ran a quarter of a megabyte past the end reading whatever was in SDRAM. It needs
the image size and a stop.

**No progress indicator.** The only tape feedback in the core is
`FM-7_MiSTer.sv:375`, `assign LED_USER = cin;`. A tape takes minutes and a
stalled one looks exactly like a slow one. `hps_io` supports `info_req` +
`info[7:0]`, which `Main_MiSTer/user_io.cpp:2607` (`show_core_info`) resolves
against an `I` line in `CONF_STR` — so a decile popup ("Tape 10%" .. "Tape
100%") is available with no framework changes. Position is
`(sdram_addr - 16) / (size - 16)`.

Note the size register needed for the progress readout is the *same* one needed
to stop at end of tape, so do both together.

Still true, and unchanged: playback only, no save, no `.wav`. And
`t77_decode.v:19` initialises `addr` to `25'h62` while the rewind path uses
`25'd16` (past the 16-byte "XM7 TAPE IMAGE 0" header, which these dumps do
carry) — the `$62` looks like a leftover.

### P4-5 [read] Printer port

`PERIPHERAL.v` has `LPBUSY`/`LPINTn`/`LPMASKn` plumbing and the `CN2` connector
bits, but nothing is connected to a printer. MAME has the same stubs. Low
priority, but it is one of the eight interrupt sources in P3-1.

---

## P5 — out of scope today, listed so it is not forgotten

The FM-77 and FM77AV add: MMR memory mapping, the MB61VH010 drawing ALU,
analog palette, 4096-colour mode, YM2203 (OPN) in place of the AY, and the
bubble casette. `refs/` covers all of them (CSP `mainmem_mmr.cpp`,
`mb61vh010.cpp`, `fm_bubblecasette.cpp`; 77AV is an FM77AV emulator throughout).
None of it matters until the FM-7 boots to a usable prompt.

---

## Suggested order

1. **P0-4** — the shared-RAM aperture / sub-halt handshake. This is the live
   blocker: fix it and typed characters should echo, which makes the machine
   actually drivable.
2. **P2-1** — keyboard tables from CSP, so more than the unshifted set works.
   (`print 1+1` needs shift for `+`; today only unshifted keys exist.)
3. **P0-2** — decide the reset story so the FPGA build does not depend on a
   power-up flip-flop state.
4. **P1-2 / P1-3** — the video mode register and `$fd37` bit layout, now that
   `$fd37` actually receives real data.
5. **P3-2** — the `$fd04` attention flag.
6. **P4-1** — the FDC, which is what the three `boot-dos*` rows need.
7. Everything else, driven by what specific software needs.

## How to check your work

`vsim/` is built for exactly this loop:

```sh
cd vsim
make && ./run_tests.sh && cp -r shots shots-ref   # baseline before changing rtl/
# ...edit rtl/...
make && ./run_tests.sh                            # compare shots/ to shots-ref/
```

The run stats answer "did it get further" without needing to read a screenshot:
`fetched from: … I/O n` flags a runaway CPU, `sub handshake` shows the BUSY flag
and `$d40a` traffic, `keyboard: n strobes` proves input arrived. When something
is wrong, `--trace-cpu` / `--trace-sub-cpu` disassemble what each CPU is
actually executing, and `--trace-mem` shows the memory-map chip selects for a
bus cycle. See `vsim/README.md`.
