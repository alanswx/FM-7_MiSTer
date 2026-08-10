# FM-7 Verilator simulation

Runs the core on the host, headless or windowed, so you can boot it, type at it,
screenshot the result and **disassemble what either 6809 is actually executing**
— without a DE10-Nano and without a Quartus build.

Modelled on the RX-78 `vsim/` setup, sharing its `sim/` framework (imgui + SDL2 +
`sim_bus`/`sim_video`/`sim_input`).

> There is an older, untracked `verilog/` directory in this repo from the same
> lineage. It is superseded by this one: its `sim.v` leaves `sdram_data` and
> `sdram_ready` undriven (so the tape path could never work), it has no
> disassembler, no debug taps, no reset prologue, and no regression script.
> Nothing here depends on it.

## Build

```sh
cd vsim
make            # -> ./obj_dir/Vemu
make run        # build + launch the windowed sim
make test       # build + headless regression sweep
make distest    # disassembler self-check (standalone, ~1s)
```

Needs Verilator 5.x and SDL2 (`brew install verilator sdl2`). Both CPUs are
`mc6809i` (Verilog), so there is no VHDL and no ghdl step.

`roms` and `audio` here are symlinks to `../rtl/roms` and `../audio`, because
`rtl/rom.v` and `rtl/pcm.v` do literal `$readmemh("./roms/…")` /
`$readmemb("./audio/…")` relative to the working directory. **Run the binary from
this directory.**

Speed is around 6 simulated frames per second, so a 400-frame run takes about a
minute. The cost is dominated by clocking the whole design at 48 MHz `clk_sys`;
faking that would change the phase relationship between the two CPUs and the
video chain, which is exactly what the core depends on.

## Headless use

```sh
# boot F-BASIC and grab a frame
./obj_dir/Vemu --headless --screenshot 300 --stop-at-frame 320

# type at it
./obj_dir/Vemu --headless --key 300:print 1+1 --key 380:@RETURN \
    --screenshot 450 --stop-at-frame 470

# mount a tape and ask F-BASIC to load it
./obj_dir/Vemu --headless --tape ../../77AVEMU/diskimage/2018_FM7DEMO_CaptainYS_V1.T77 \
    --key 400:load\"\" --key 500:@RETURN --stop-at-frame 3000
```

`--help` lists everything. The options that matter:

| Option | Notes |
|---|---|
| `--tape <file.t77>` | Loaded through the real `ioctl` path at index 1, exactly as `hps_io` does for `F1,t77`, into the behavioural SDRAM and played by `rtl/t77_decode.v`. |
| `--tape-audio` / `--rewind-at-frame <n>` | The `Tape Audio` and `Tape Rewind` OSD bits. |
| `--bootrom <0-3>` | The `BootROM` OSD bits: 0 = F-BASIC, 1-3 = the DOS boot ROMs. |
| `--machine <fm7\|fm77av>` | Machine-family selector matching the OSD. `fm77av` is a bring-up gate and currently holds the core in reset until the AV backend is implemented. |
| `--key <frame>:<text>` | Types text, or `@NAME` for `SPACE RETURN TAB BS ESC CAPS UP DOWN LEFT RIGHT HOME INS DEL CTRL SHIFT GRAPH KANA BREAK F1`..`F10`. |
| `--key-hold <frames>` | Frames to hold each key, default 6. |
| `--screenshot <n,...>` / `--screenshot-name <path>` | PNG per listed frame / exact path, for scripting. |
| `--stop-at-frame <n>` | Required for headless runs; otherwise it stops at 100000 frames. |
| `--trace-cpu [file]` | Disassemble every main-CPU instruction as it retires. See below. |
| `--trace-io [file]` | Every `$fdxx` read/write with the port, the data and the PC. |
| `--trace-mem <lo>-<hi>` | Every main-CPU bus cycle in a hex address range, with the memory-map chip selects. |
| `--dump-shadow <file>` | The 64K of bytes the CPU has actually seen on its bus. |

**There is no joystick option** because the core has no joystick input —
`core.v` takes `ps2_key` and nothing else. Keyboard only.

Everything schedulable is in **frames**, not cycles, because frames stay
meaningful across clock changes; a cycle-based schedule has to be rewritten
every time a divider in `rtl/clocks.svh` moves.

## Disassembly and tracing

This is the part worth reading. The FM-7 has two 6809s that talk to each other
through shared RAM, so "the screen is black" has a large number of possible
causes and a screenshot distinguishes none of them.

```sh
# what is the main CPU doing, for one frame
./obj_dir/Vemu --headless --stop-at-frame 1 --trace-cpu boot.log --trace-until 0

# both CPUs, only around the point of interest
./obj_dir/Vemu --headless --stop-at-frame 400 --trace-cpu t.log --trace-sub-cpu t.log \
    --trace-from 380 --trace-until 385
```

```
      0 main  $fe0f  10 ce fc 7f     LDS   #$fc7f  a=fd b=00 x=0000 y=0000 u=0000 s=fc7f dp=fd cc=eFhINzvc
      0 main  $fe13  d6 04           LDB   <$04    a=fd b=ff x=0000 y=0000 u=0000 s=fc7f dp=fd cc=eFhINzvc
```

Registers are the state **after** that instruction retired.

Two things make this work without touching `rtl/`:

- **Instruction boundaries come from the state machine, not from `LIC`.**
  `mc6809i.v` asserts `LIC` on the last cycle of an instruction, at which point
  `pc` has advanced past the operands but not yet through a taken branch — so a
  `LIC`-sampled `pc` is neither the current nor the next instruction's address,
  and the disassembly walks off by one byte at a time. `sim.v` taps
  `CpuState == CPUSTATE_FETCH_I1` instead; `assign ADDR = addr_nxt` with
  `addr_nxt = pc` in that state puts the instruction's own address on the bus.

- **The operand bytes come from a bus shadow.** Every byte either CPU puts on
  its data bus is recorded, so the disassembler has memory to read with no extra
  RTL and no `--public-flat-rw`. An address the CPU has never touched prints as
  `??` rather than as a plausible-looking `$00`.

  The shadow is sampled from the values captured *one `clk_sys` cycle before* E
  falls. A bus cycle ends on E's falling edge, which is also the edge
  `mc6809i.v` advances its state on (`always @(negedge E)`), while the address
  bus is combinational on the *new* state. Sample after that and you pair each
  address with the next cycle's data — which still disassembles, just into
  convincing nonsense. `--dump-shadow` exists so this stays checkable:

  ```sh
  ./obj_dir/Vemu --headless --stop-at-frame 1 --dump-shadow shadow.bin
  # shadow.bin is 64K; shadow.bin.known flags which addresses were really seen.
  # Over the addresses it has seen, shadow.bin[$fe00..$ffff] == rtl/roms/boot_bas.rom.
  ```

Every headless run also ends with the **last 16 instructions of each CPU**
(`--trace-tail n`, 0 disables), which is almost always enough on its own.

`make distest` runs `dis6809_test.cpp` against every addressing mode, both
prefix pages, the register-list and register-pair postbytes, and an undefined
opcode. A disassembler that is subtly wrong is worse than none, because it
produces confident output you will act on.

## Run stats

```
--- run stats ---------------------------------------------
frames            : 201  (3.37 s of machine time)
vblank edges      : 201
main 6809         : 1836622 instructions  (9137 per frame)
     pc range     : $00de .. $ffdf   pc now $f89d
     fetched from : RAM 2  ROM 1836620  I/O 0
     interrupts   : IRQ 2  FIRQ 1  NMI 0   (lines now: IRQ )
sub 6809          : 798341 instructions  (3972 per frame)
     pc range     : $d097 .. $ff69   pc now $e141
     interrupts   : IRQ 0  FIRQ 0  NMI 169
     halted        : 54.6% of cycles
I/O cycles ($fdxx): 770232
keyboard          : 0 strobes, codes seen $00
video             : palette 0 1 2 3 4 5 6 7   $fd37 = $00   scroll $0000   display on
```

How to read it:

- **`fetched from: … I/O n`** is the loudest signal in the whole harness. The
  main CPU's `$fd00-$fdff` window returns `$ff` for anything undecoded, and `$ff`
  is a legal opcode, so a CPU that jumps into it never traps — it just runs
  through all 256 ports and out the other side. Any non-zero count here is a
  runaway, and the run is flagged `RUNAWAY`.
- **`halted: 54.6%`** is *normal* for the sub CPU, not a fault. `MB60H010`
  asserts `SVDHALT` to stall it during active video. A figure near 100% means it
  never got the bus at all.
- **`keyboard: n strobes`** counts `KSTROBEn` falling edges — keystrokes that
  reached the machine. Zero after a `--key` means the injection is broken; a
  non-zero count with nothing on screen means the machine isn't reading it.
- **`palette`** should be `0 1 2 3 4 5 6 7` right after reset — `PAL.v` fills it
  with the identity while `RESETBn` is low.

## Regression sweep

```sh
./run_tests.sh              # all tests
./run_tests.sh basic        # substring filter
FRAMES=1200 ./run_tests.sh  # run longer
TAPEDIR=../tapes ./run_tests.sh
```

Boots each of the four BootROM selections, does two keyboard round trips, and
adds one load test per `.t77` found in `$TAPEDIR` (default `../tapes`, absent by
default). Writes one PNG per test to `shots/` and prints the liveness table. To
set a baseline before changing the core:

```sh
./run_tests.sh && cp -r shots shots-ref
# ...make a change, rebuild, re-run...
for f in shots/*.png; do compare -metric AE "$f" "shots-ref/$(basename $f)" null: 2>&1; echo " $f"; done
```

## Deliberate differences from FM-7_MiSTer.sv

All of them are commented at the point they occur in `sim.v`:

- `clk_sys` is driven by `sim_main` instead of the PLL. The PLL's `outclk_0` is
  48.000 MHz, so this is exact, not an approximation.
- `rtl/sdram.sv` (the real controller, with `SDRAM_*` pins) is replaced by the
  behavioural model in `vsim/rtl/sdram.sv`. Same client interface, same
  edge-detected requests and read latency.
- The tape download writes bytes (`wtbt=00`, 8-bit `ioctl_dout`); the FPGA build
  uses `hps_io #(.WIDE(1))` and 16-bit writes. The bytes land at the same
  addresses either way — `SimBus` only speaks 8-bit.
- `VGA_R/G/B` replicate the core's single colour bit across all 8 bits.
  `FM-7_MiSTer.sv` assigns only `VGA_x[7]`, which would make every screenshot
  half-brightness.
- `VGA_VB` clears 384 pixel clocks early, inside the last blanked line.
  `SimVideo` starts a new line when HBLANK falls and a new frame when VBLANK
  falls, and resets the line counter *after* the line increment — and in this
  core `MB60H010` wraps `xx` and `yy` on the same clock, so the frame reset would
  eat the line increment and shift the picture up by one line. HBLANK is high for
  that whole window, so no visible pixel is affected.

### The reset prologue

`sim_main` runs 64 cycles with reset **low** before asserting it. This is not
cosmetic. `ROMS.v` latches the boot ROM select with

```verilog
wire ck = ~RESETBn;
always @(posedge pre, posedge clr, posedge ck)
  ...
  else ff_q <= m120_q;
```

— a flip-flop *clocked by reset being asserted*, not by reset being released.
Start the sim with reset already high and `~RESETBn` never has a rising edge, so
`ff_q` keeps its power-on `0`, `RAM1HB2n` stays high, the F-BASIC ROM is never
chip-selected, and every read of `$8000-$fbff` returns `$00`. The boot ROM then
does `LDX $fbfe` (getting `$0000`) and `JMP ,X`, and the machine executes zeroed
RAM forever.

This is worth knowing beyond the sim: the core's cold-boot behaviour depends on
that edge existing, which makes it sensitive to how `RESET` is sequenced.

## Edits made to `rtl/`

Building this harness needed exactly one change to the RTL: the per-pixel-clock
`$display` in `MB60H010.v` is now behind `` `ifdef DEBUG_MB60H010 ``
(`make DEBUG_VIDEO=1` restores it). It is 16 million lines per simulated second,
so it cannot be left unconditional.

Everything the harness *observes* — every register, both program counters, the
palette, the keyboard latch, the memory-map chip selects — is read out of the
core with hierarchical references in `sim.v`. Nothing in `sim.v` drives the
core, and there is no `--public-flat-rw`.

Separately, *using* the harness turned up four real core bugs, which are now
fixed in `rtl/` and written up in `../TODO.md`: the `$fdxx` read strobe timing
(`core.v`), three modules latching the read bus on writes (`core.v`), the
character-cell shift-register load phase (`MB60H010.v`), and the boot ROM
select (`ROMS.v`).

Note that `rtl/MRAM.v`'s `` `ifdef VERILATOR `` branch (generic `ram` instead of
the Quartus `altsyncram` wrapper) and the trailing-comma fix in `ROMS.v` were
already in the working tree; the sim needs both.

## Current state of the core

The core boots to a usable prompt:

```
FUJITSU F-BASIC Version 3.0
Copyright (C) 1981 By FUJITSU/MICROSOFT
30530 Bytes Free

Ready
```

Typed keys reach the machine correctly (the sub CPU takes a FIRQ per key and
reads the right ASCII from `$d401`) but do not echo — the main CPU stops writing
the shared-RAM aperture after boot, so the sub redraws a stale buffer and every
keystroke prints "Copyright". See `../TODO.md`, P0-4.

Getting this far took five `rtl/` fixes and one fix in this harness, all written
up in `../TODO.md`. The harness one is worth knowing if you touch `sim.v`:
`ce_pix` is `SFTCLK`, which `clk_en` drives as a real 16 MHz clock (high for two
of every three `clk_sys` cycles), **not** a one-cycle enable. Passing it straight
through as `CE_PIXEL` makes `sim_main` sample every pixel twice and doubles the
picture horizontally.

`shots-ref/` is the booting baseline. Re-baseline with
`./run_tests.sh && cp -r shots shots-ref` whenever you intend a visual change.
