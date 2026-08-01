# FM77AV support — implementation plan

Written by reading `rtl/` against the three emulators in `refs/`, the MAME ROM
sets now in `refs/*.zip`, and `TODO.md`. It expands `TODO.md` P5 into something
executable.

Same conventions as `TODO.md`:

- **[verified]** — I ran it or read the exact bytes.
- **[read]** — found by comparing sources; not exercised.
- **[unverified]** — I am guessing and saying so.

Reference precedence, unchanged from `TODO.md` "Working practices": **CSP is the
primary authority, 77AVEMU is the tiebreaker, MAME is an I/O map and nothing
more.** That rule earns its keep immediately — see §6.3, where MAME swaps red and
green in the analog palette index in exactly the same way it swaps the VRAM
planes in P1-5.

---

## 0. Executive summary — what I concluded

**Not ROM-blocked. [verified]** `refs/fm77av.zip` contains every image MAME's
`ROM_START( fm77av )` asks for, and all seven CRC32s match MAME byte for byte
(§2). There is no `NO_DUMP` anywhere in the FM77AV set. This is a materially
better position than P3-3 was in (which was blocked on the kanji ROM, and is now
also unblocked — `refs/fm7.zip` carries `kanji.rom` crc `62402ac9`, which is
what the uncommitted `rtl/roms/kanji.rom` on this branch already is).

**Three findings make this cheaper than `TODO.md` P5 implies:**

1. **The FM-7 memory map *is* the FM77AV's MMR-disabled default.** All three
   references model a 256 KB physical space in which `0x30000-0x3FFFF` is the
   FM-7 machine, and translation is `phys = MMR[seg][addr[15:12]] << 12 |
   addr[11:0]` only for `addr < $FC00` (77AVEMU `fm77avmemory.h:337-346`, CSP
   `mainmem_readseq.cpp:53-68`, MAME `fm7.cpp:960-1011`). `$FC00-$FFFF` is
   *never* translated. So `rtl/m139.v`, `rtl/ROMS.v`'s `FCXXn` decode, `SRAM.v`
   and the whole `$fdxx` I/O decode survive untouched, and MMR is a prefix
   generator bolted in front of `MADDRBUS`, not a rewrite of the decode.

2. **The sub-system side is nearly unchanged.** 77AVEMU's physical sub map
   (`fm77avmemory.h:66-86`) is byte-for-byte the FM-7 sub map this core already
   implements in `SDECODE.v`: VRAM `$0000-$BFFF`, RAM `$C000-$CFFF`, shared RAM
   `$D380-$D3FF`, I/O `$D400-$D4FF`, font ROM `$D800-$DFFF`, monitor ROM
   `$E000-$FFFF`. `SMEM.v`'s existing split — `m153` 2 KB at `$D800` +  `m154`
   8 KB at `$E000` — is *exactly* the AV's font/monitor split, so sub-ROM
   banking (§8) is a mux on two existing ROM instances.

3. **The FM77AV has no separate AY-3-8910**, and a drop-in replacement exists.
   `$FD0D`/`$FD0E` are the SSG half of the on-board YM2203 and `$FD15`/`$FD16`
   are the FM half — CSP `sound.cpp:46-52, 107-133` (`opn_psg_77av`), 77AVEMU
   `fm77avsound.cpp:396-406` ("FM77AV and later writes to the PSG-part of
   YM2203C"). Both agree. So the sound work is "swap one module for a superset".
   `jotego/jt12`'s `jt03` **is** that superset — a YM2203 with a `jt49` SSG
   inside and `IOA`/`IOB` brought out [verified by reading the source], which
   also retires `rtl/SOUND.v`'s joystick bus-snooping hack (P4-2) and the
   unresolved prescaler question (P4-3). See §9.2 for the one real trap.

**Three things are genuinely a rewrite, not a delta:**

1. **320x200 4096-colour mode is a different VRAM organisation, not a width
   change.** `TODO.md` P1-2 resolved the width bit as "`$fd12`, FM-77AV only" and
   filed it. That is right about the address and understates the consequence: on
   the AV, `$FD12` bit 6 switches VRAM from 3 planes × 16 KB to **12 planes ×
   8 KB spread across both 48 KB pages**, and switches the video output from the
   8-entry digital palette to a 4096-entry analog one (CSP `display.cpp:375-390`
   + `vram.cpp:753-767`; 77AVEMU `fm77avrender.cpp:178-263`). `PAL.v`,
   `CRTRAM.v`, `SUBCRTADDR.v` and the `grb[2:0]` output of `core.v` all change.

2. **The MB61VH010 ALU is a real read-modify-write engine on the VRAM bus**, and
   it sits exactly where `core.v`'s `sub_vram_wait` already stalls the sub CPU
   (P0-7). See §7 — this is the largest single RTL item.

3. **The main CPU can reach VRAM and sub I/O through MMR** (physical
   `0x10000-0x1FFFF`). That makes VRAM a three-master resource. `CRTRAM.v` is
   three single-port RAMs with a raster/CPU address mux today. See §5.4 and §12.1.

**Recommended scope: base FM77AV only.** Not AV20, AV40, AV40EX or AV40SX.
CaptainYS, who wrote the most complete AV emulator, says it himself
(`refs/77AVEMU/readme.md:24`): *"practically more than 99.9% of FM-7 series
software runs on FM77AV. Minimum goal is to support FM77AV."* The AV40SX ROM
set exists in `refs/fm7740sx.zip` and is complete, but 400-line mode, the
dictionary ROM and `kanji2` would add ~430 KB of block RAM to a budget that is
already tight (§12.1), and MAME does not model AV40 at all (there is no
`ROM_START( fm77av40 )` in the tree — only `fm77av` and `fm7740sx`, and
`fm7740sx` is a `MACHINE_NOT_WORKING` clone driven by the plain `fm77av`
machine config, `fm7.cpp:2301`).

---

## 1. Scope: what is a delta, what is a rewrite

| Subsystem | AV change | Size |
|---|---|---|
| Main CPU | 6809 at ~2 MHz instead of 1.2288 MHz; `CLKCTRL.v` already has the divider | **delta** |
| Sub CPU | unchanged (2.016 MHz both machines) | **none** |
| `m139` / `FCXXn` decode | unchanged — MMR never touches `$FC00-$FFFF` | **none** |
| Shared RAM `$FC80`/`$D380` | unchanged | **none** |
| FDC, tape, printer, timer, `$fd00-$fd0f` | unchanged | **none** |
| Kanji `$fd20-$fd23` | unchanged (`KANJI.v` on this branch already does it) | **none** |
| Boot ROM | `$FE00-$FFDF` becomes **RAM seeded from `initiate.rom`**; `ROMS.v`'s M152 four-bank chip is not used in AV mode | **rewrite of `ROMS.v`'s AV path** |
| Initiate ROM `$6000-$7FFF` | new 8 KB overlay + `$FD10` | **new, small** |
| MMR/TWR `$FD80-$FD94` | new address translator + 192 KB more RAM | **new, large** |
| Sub monitor ROM `$FD13` | mux on `SMEM.v`'s existing two ROMs + 3 new images | **delta** |
| Sub map | `$D500-$D7FF` becomes hidden RAM; I/O aliases every 64 B not 16 B | **small `SDECODE.v` change** |
| VRAM | 48 KB → 96 KB, two pages, page-select + display-page | **delta** |
| Scroll `$D40E/$D40F` | two independent offsets (one per page) + fine mode | **delta to `MB60H010.v`** |
| Digital palette `$fd38-$fd3f` | unchanged | **none** |
| Analog palette `$FD30-$FD34` | new 4096 × 12-bit LUT, and the whole video output widens to RGB444 | **rewrite of `PAL.v` + both tops** |
| 4096-colour mode `$FD12` b6 | new 12-plane VRAM organisation and pixel assembly | **rewrite** |
| MB61VH010 ALU `$D410-$D42B` | new | **new, largest** |
| Sound | AY-3-8910 → YM2203 (OPN), same `$fd0d/$fd0e` protocol plus `$fd15/$fd16` | **module swap + FM core** |
| Keyboard encoder `$D431/$D432` | new command FIFO, make/break scancode mode | **new, medium** |
| Bubble casette | **skip.** See §10.5 | **none** |

---

## 2. ROM availability [verified]

I unzipped both sets and computed CRC32 of every member, then grepped
`refs/mame/src/mame/fujitsu/fm7.cpp` for each value. Every one matches.

### `refs/fm77av.zip` — complete, matches `ROM_START( fm77av )` (`fm7.cpp:2211-2232`)

| file | bytes | crc32 | MAME | notes |
|---|---|---|---|---|
| `initiate.rom` | 8192 | `785cb06c` | `fm7.cpp:2213` | good dump |
| `fbasic30.rom` | 31744 | `a96d19b6` | `fm7.cpp:2216` | **BAD_DUMP** — "last 1K is inaccessible". Byte-identical to `fbasic302.rom` in `fmnew7`, and **not** the same as this repo's `fbasic300.rom` (`87c98494`) |
| `subsys_a.rom` | 8192 | `e8014fbb` | `fm7.cpp:2222` | good dump |
| `subsys_b.rom` | 8192 | `9be69fac` | `fm7.cpp:2224` | good dump |
| `subsys_c.rom` | 10240 | `24cec93f` | `fm7.cpp:2220` | **BAD_DUMP** — but it is the same image this core already ships as `subsys_m153`+`subsys_m154`, so nothing changes |
| `subsyscg.rom` | 8192 | `e9f16c42` | `fm7.cpp:2226` | good dump. **Four 2 KB font banks**, not an 8 KB monitor — see §8 |
| `kanji.rom` | 131072 | `62402ac9` | `fm7.cpp:2229` | good dump; identical to the one already on this branch |

### `refs/fm7740sx.zip` — also complete, for a machine I recommend not targeting

Adds `kanji2.rom` (131072, `38644251`), `dicrom.rom` (262144, `b142acbc`),
`extsub.rom` (49152, `0f7fcce3`). All three match MAME. Caveats worth recording
so nobody mistakes MAME's layout for hardware documentation:

- MAME loads `kanji2.rom` at offset 0 of the *same* 0x20000 `kanji1` region as
  `kanji.rom`, so the second load overwrites the first (`fm7.cpp:2252-2253`).
  That is a driver bug.
- The `"additional"` region holding `dicrom`/`extsub` is never referenced by any
  MAME code, and the source comment says so: *"These should be loaded at
  2e000-2ffff of maincpu, but I'm not sure if it is correct"* (`fm7.cpp:2255`).
- 77AVEMU declares `ROM_KANJI2[0x20000]` and loads it as mandatory for AV40, but
  `$FD2C`/`$FD2D`/`$FD2F` have **no handler anywhere** — the symbols appear only
  in `fm77avdef.h:140-143`. So neither MAME nor 77AVEMU can tell you how the
  second kanji bank works. CSP can (`kanjirom.cpp`, `fm7_mainio.cpp:1734-1752`),
  but note CSP puts the L2 *write* at `$FD2E` where the dictionary bank register
  also lives.

### Boot ROM images: the AV does not need them separately [read]

77AVEMU lists `BOOT_BAS.ROM` and `BOOT_DOS.ROM` as *mandatory* for FM77AV
(`refs/77AVEMU/src/memory/fm77avmemory.cpp:40-55`), which reads like a missing
dependency because `fm77av.zip` has neither. **CSP shows it is not.** On the AV,
`$FE00-$FFDF` is RAM, and `mainmem_utils.cpp:290-299` seeds it from inside
`initiate.rom`:

```c
	if((config.boot_mode & 0x03) == 0) {
		memcpy(fm7_bootram, &fm7_mainmem_initrom[0x1800], 0x1e0);   // BASIC
	} else {
		memcpy(fm7_bootram, &fm7_mainmem_initrom[0x1a00], 0x1e0);   // DOS
	}
	fm7_bootram[0x1fe] = 0xfe; fm7_bootram[0x1ff] = 0x00;          // reset vector
```

So the AV's two boot loaders live at `initiate.rom` offsets `$1800` and `$1A00`,
480 bytes each. MAME agrees that the AV has no boot ROM region — `ROM_START(
fm77av )` has none, and `machine_reset` explicitly gates the boot-ROM switch to
`SYS_FM7` with the comment *"set boot mode (FM-7 only, AV and later has boot RAM
instead)"* (`fm7.cpp:1813`). **Verify the `$1800`/`$1A00` offsets by disassembling
`initiate.rom` before writing RTL** — I have not done that, and it is the one
place where a wrong constant will silently produce a machine that boots nothing.

### `.mem` convention and repo size [verified]

`rtl/roms/` holds each ROM as both a `.rom` binary and a `$readmemh` `.mem` text
file at **3 bytes per ROM byte** (two hex digits + `\n`; confirmed against
`boot_bas.rom.mem`). `refs/` and `software/` are gitignored, `rtl/roms/*.mem` is
not. New AV `.mem` files:

| image | `.mem` size |
|---|---|
| `initiate.rom` | 24 KB |
| `subsys_a.rom` | 24 KB |
| `subsys_b.rom` | 24 KB |
| `subsyscg.rom` | 24 KB |
| `fbasic30.rom` | 93 KB |
| **total** | **~189 KB** — trivial |

For contrast, an AV40SX target would add `kanji2` (384 KB), `dicrom` (768 KB)
and `extsub` (144 KB) = ~1.3 MB of `.mem`. Not fatal, but another reason to scope
to base AV.

---

## 3. Phasing

Every phase leaves the FM-7 booting. The invariant is enforced mechanically:
**`vsim/run_tests.sh`'s eight FM-7 rows must produce identical numbers before and
after each phase**, and the FM-7 half of the P4-14 sweep must not regress.

The AV path is gated on a machine-select input that is `0` in every existing
test, so a phase that only adds AV-mode logic cannot regress the FM-7 by
construction — *provided* the AV logic is genuinely gated and not, say, a wider
`MRAM` address bus that changes FM-7 addressing too.

| Phase | What | Leaves FM-7 booting? | Rough size |
|---|---|---|---|
| **P5-0** | Machine-select plumbing through both tops + `vsim`. No behaviour. | trivially yes | 0.5 d |
| **P5-1** | ROM ingest: `.rom` + `.mem` for `initiate`, `subsys_a/b`, `subsyscg`, `fbasic30`; `files.qip`; `vsim/Makefile` | yes — nothing instantiated yet | 0.5 d |
| **P5-2** | MMR + TWR address translation, 192 KB physical RAM. Sub-system aperture (`$1xxxx`) deferred. | yes — AV-gated, and MMR defaults off | 3-4 d |
| **P5-3** | AV boot: initiate ROM at `$6000`, reset vector, boot RAM at `$FE00`, `$FD10`, `$FD93` b0, `$FD0B`, 2 MHz clock | yes | 2-3 d |
| **P5-4** | Sub monitor ROM banking `$FD13`, CG font bank `$D430[1:0]`, sub map `$D500-$D7FF` | yes | 1-1.5 d |
| **P5-5** | VRAM second page, `$D430` display/access page, two scroll offsets, fine-offset mode | yes | 2 d |
| **P5-6** | MMR sub-system aperture (`$1xxxx`) — main CPU reaches VRAM/sub I/O | yes | 2 d |
| **P5-7** | Analog palette + RGB444 output path through both tops | yes, if FM-7 output stays bit-identical (§6.4) | 2-3 d |
| **P5-8** | 320x200 4096-colour mode | yes | 3-4 d |
| **P5-9** | MB61VH010 ALU: byte ops first, LINE second | yes | 5-8 d |
| **P5-10** | YM2203 (`jt03`). Split: `jt49_bus` for the FM-7 first, then `jt03` for the AV | yes, but the first half deliberately changes the FM-7 sound path — see §9.2 | 2-3 d |
| **P5-11** | AV keyboard encoder `$D431/$D432` | yes | 2-3 d |

**Do not reorder P5-2 and P5-3 casually.** MMR is off at reset on every
reference, so P5-3 in isolation would boot into the identity map — but F-BASIC
V3.0 programmes MMR very early, so P5-3's acceptance test without P5-2 is
"reaches the initiate ROM and starts writing `$FD8x`", not "reaches a prompt".
Doing P5-2 first means P5-3's milestone can be the real one: **an F-BASIC V3.0
prompt in AV mode.**

---

## 4. The OSD option (P5-0)

### 4.1 Which bits

The bit map is documented at `FM-7_MiSTer.sv:207-223` (commit `1235b64`):

```
  0         Reset / Reset+close OSD
  8         Tape Rewind (trigger)
  9         Tape Audio
  11:10     Boot ROM        -> bootrom_sel -> ROMS.v M152 bank
  122:121   Aspect ratio
```

with bits 1..7 and 12..120 free. **Use `status[13:12]`** — adjacent to
`bootrom_sel`, two bits so FM-77 and FM77AV40 have somewhere to go later:

```verilog
  "O[13:12],Machine,FM-7,FM77AV;",
```

Encoding `0 = FM-7`, `1 = FM77AV`, `2`/`3` reserved. Add the two rows to the bit
map comment in the same commit — the comment is the only place the allocation is
recorded, and letting it drift is how it got two wrong entries before.

The `Boot ROM` option (`status[11:10]`) is meaningless in AV mode: the AV has no
M152 chip and picks BASIC-vs-DOS from `$FD0B`. Two options:

- Reuse it. `$FD0B` bit 0 reads `0` for DOS and `1` for BASIC (MAME
  `av_boot_mode_r`, `fm7.cpp:784-796`; CSP `fm7_mainio.cpp:1263-1270` returns
  `0xfe` for BASIC mode and `0xff` otherwise). So `bootrom_sel != 0` → DOS is a
  natural mapping and costs nothing.
- Hide it with the MiSTer conditional-item syntax (`H`/`h` + a status bit) and
  add a separate `Boot mode` item.

I would reuse it for P5-3 and revisit. Fewer moving parts, and the OSD label
`0 disk / 1 alt / 2 dos-a / 3 empty` is already FM-7-specific enough to want
rewording eventually.

### 4.2 Reset-time only — yes, and here is why

The machine select **must** latch at reset and never change while running.
Three independent reasons, all concrete:

1. **`ROMS.v` loads its power-on default only while reset is asserted.** The
   comment at `rtl/ROMS.v` (the `ff_q` block) records that this was P0-2: the
   `$fd0f` ROM/RAM flip-flop takes `m120_q` on `~RESETBn`. Any machine-dependent
   power-on state has to arrive through the same door.
2. **The address map changes underneath the running CPU.** Switching mid-run
   moves `$6000-$7FFF` between RAM and initiate ROM, moves `$FE00-$FFDF` between
   ROM and RAM, changes the main clock, and changes VRAM from 48 KB to 96 KB.
   The 6809 would be executing an instruction whose next fetch lands somewhere
   else entirely.
3. **The core's reset is already a long latched pulse** — `reset_count` is 2^20
   CLKSYS cycles ≈ 21.8 ms (`FM-7_MiSTer.sv:343-352`) precisely so every divided
   clock domain sees it. A machine switch needs exactly that treatment.

Implementation: make the machine bits a reset source and latch them under reset.

```verilog
reg [1:0] machine = 2'd0;
wire      machine_changed = (machine != status[13:12]);
wire      reset_req = RESET | status[0] | buttons[1] | machine_changed;

always @(posedge clk_sys)
  if (reset) machine <= status[13:12];   // held for the whole 21.8 ms
```

Note the deliberate asymmetry with `img_mounted`, which `FM-7_MiSTer.sv:337-341`
explicitly refuses to make a reset source (mid-game disk swaps). A machine change
is the opposite case: it *must* reset.

### 4.3 Both tops, and the simulator

`vsim/sim.v:38-42` mirrors the OSD bits by name:

```verilog
	input   [1:0] bootrom_sel,      // status[11:10] "BootROM" Basic/1/2/3
	input         tape_rewind,      // status[8]     "Tape Rewind"
	input         tape_audio,       // status[9]     "Tape Audio"
```

Add `input [1:0] machine, // status[13:12] "Machine" FM-7/FM77AV` and pass it to
`core u_core` (`vsim/sim.v:186-217`, `FM-7_MiSTer.sv:403-434`). Then in
`vsim/sim_main.cpp`:

- `static int opt_machine = 0;` next to `opt_bootrom` (`sim_main.cpp:99`)
- `--machine <0|1>` in `print_usage` (`sim_main.cpp:556`) and the arg loop
  (`sim_main.cpp:641`)
- `top->machine = opt_machine;` next to `top->bootrom_sel` (`sim_main.cpp:971`)
- an ImGui slider next to the boot-ROM one (`sim_main.cpp:1251`)

**Trap:** the sim's reset prologue at `sim_main.cpp:986` manufactures a reset
*edge* (holds reset low for 64 cycles, then asserts). That is what hid P0-2 from
`vsim` for so long. A machine latch clocked on `posedge clk_sys` under
`if (reset)` is level-based and immune, but do not be tempted to latch on an
edge of anything.

---

## 5. Memory: MMR paging (P5-2) — the biggest single item

### 5.1 The model, and all three references agree on it

**Registers, all main side:**

| Addr | R/W | Function |
|---|---|---|
| `$FD80-$FD8F` | R/W | 16 bank registers of the currently selected set. Each holds physical A19:A12. |
| `$FD90` | W only | Set (segment) select. `& 3` on base AV, `& 7` with ExMMR (AV40). |
| `$FD92` | W only | TWR window offset, 256-byte units. |
| `$FD93` | R/W | b7 = MMR enable, b6 = TWR enable, b0 = `$FE00` boot-RAM write enable. |
| `$FD94` | W | AV40 only: b7 = ExMMR. Not needed for base AV. |
| `$FD10` | W | b1 = 1 disables the initiate ROM. Not MMR, but lives in the same phase. |

Sources: 77AVEMU `fm77avdef.h:173-193` + `fm77avmemory.cpp:1204-1280`; CSP
`fm7_mainio.cpp:1523-1537` (`$FD8x`), `:1804-1813` (`$FD90`), `:1814-1816`
(`$FD92`), `:1817-1826` (`$FD93`); MAME `fm7.cpp:944-1042`.

**The translation:**

```
if (TWR_enabled && addr[15:10] == 6'b011111)          // $7C00-$7FFF
    phys = ((TWR_offset << 8) + $7C00 + addr[9:0]) & $FFFF;   // page 0 only
else if (MMR_enabled && addr < $FC00)
    phys = { MMR[seg][addr[15:12]][5:0], addr[11:0] };        // 6-bit bank
else
    phys = $30000 + addr;
```

- 77AVEMU: `fm77avmemory.h:337-351`, dispatch order at `fm77avmemory.cpp:1325-1339`.
- CSP: `mainmem_readseq.cpp:32-68` (TWR checked *before* MMR and short-circuits
  it), `window_convert()` at `mainmem_mmr.cpp:12-30`.
- MAME: `fm7_mmr_refresh()` at `fm7.cpp:960-1011`; MMR off ⇒ `set_bank(0x30 + x)`.

**`addr >= $FC00` is never translated.** 77AVEMU cites the FM77AV40 Hardware
Manual p.146 for this (`fm77avmemory.h:339`). CSP does the same
(`mainmem_readseq.cpp:53-58`, `raddr = 0x30000 | (addr & 0xffff)`). MAME achieves
it structurally — the 16 banked windows are installed first and then `$FC00-$FFFF`
is overwritten with direct entries, and later entries win (`fm7.cpp:1462-1501`).

This is the load-bearing fact for the FPGA. `rtl/MDECODE.v`, `rtl/m139.v`,
`rtl/SRAM.v`, `rtl/MFD.v`, `rtl/TIMER.v`, `rtl/PERIPHERAL.v`, `rtl/KANJI.v` and
`ROMS.v`'s `FCXXn`-gated outputs all key off `MADDRBUS` in `$FC00-$FFFF` and
**need no change at all**.

### 5.2 Physical space and what lives where

| Physical | MMR bank values | Contents | Where in the FPGA |
|---|---|---|---|
| `$00000-$0FFFF` | `$00-$0F` | RAM page 0 (64 KB) | new block RAM |
| `$10000-$1FFFF` | `$10-$1F` | the whole sub system: VRAM `$10000-$1BFFF`, sub RAM `$1C000`, shared RAM `$1D380`, sub I/O `$1D400`, font ROM `$1D800`, monitor ROM `$1E000` | existing `CRTRAM`/`SMEM`/`SRAM`, newly reachable from the main bus — **defer to P5-6** |
| `$20000-$2FFFF` | `$20-$2F` | RAM page 2 (64 KB) | new block RAM |
| `$30000-$3FFFF` | `$30-$3F` | the FM-7 machine: RAM `$0000-$5FFF`, initiate ROM `$6000-$7FFF`, F-BASIC ROM / shadow RAM `$8000-$FBFF`, then `$FC00-$FFFF` | existing `MRAM` + `ROMS` + the new initiate ROM |

77AVEMU `fm77avmemory.h:61-119`; CSP `mainmem_utils.cpp:418-486`; MAME
`fm7_banked_mem` at `fm7.cpp:1527-1563`. All three lay it out identically.

**RAM total.** Pages 0, 2 and the `$3xxxx` image are three distinct 64 KB
regions in all three references (MAME names them `extended_ram`,
`main_ram_20000`, `main_ram_30000`+`init_bank_ram`+`fbasic_bank_ram`), so a
faithful implementation is **192 KB of main RAM**, up from the 64 KB `MRAM.v`
has today. The real FM77AV shipped with 128 KB and the AV20/AV40 with 192 KB, so
this may be over-provisioning by one page on the base machine — **[unverified]**,
and I would build 192 KB anyway because it costs one more block-RAM bank and
avoids guessing which page the base AV actually populates.

**Two MMR quirks worth copying:**

- CSP blocks `$FD80-$FD97` from being reached *through* bank `$3F`
  (`read_segment_3f`, `mainmem_mmr.cpp:119-129`) — reading them that way returns
  `$FF`. Cheap to reproduce, and it stops MMR reprogramming itself by accident.
- 77AVEMU masks `$FD8F` to 6 bits even with ExMMR, citing the AV40EX/20EX
  hardware manual (`fm77avmemory.cpp:1268-1272`). Irrelevant for base AV.

**A disagreement to note:** MAME masks `$FD90` with `& 0x07` unconditionally
(`fm7.cpp:1026`), giving 8 sets on every machine. CSP and 77AVEMU both mask
`& 3` on base AV, and 77AVEMU carries an experimental note
(`fm77avmemory.cpp:1227-1228`): *"Oh!FM May 1989 issue pp.45 implies that there
are 8 MMR segments in total. However, if so F-BASIC 3.3 does not boot. It messes
up the MMR."* **Follow CSP/77AVEMU: 4 sets on base AV.** That is a 4×16×6-bit
register file, 384 bits — LUT RAM, not block RAM.

### 5.3 Where it goes in the RTL

A new `MMR.v` sitting between `MCPU` and everything else:

```
MCPU.MADDRBUS[15:0] ──┬──────────────────────────────────► FCXXn/m139/MDECODE (unchanged)
                      │
                      └──► MMR.v ──► MPHYS[19:0] ──► MRAM/ROMS/CRTRAM/... read mux
```

`MMR.v` inputs: `MADDRBUS`, the write strobes for `$FD80-$FD94`, `MDATABUS_out`,
`RESETBn`, `machine_is_av`. Output: `MPHYS[19:0]`, plus a readback byte for the
`MDATABUS_in` mux (`$FD80-$FD8F` and `$FD93` are readable; `$FD90` and `$FD92`
are write-only on both CSP and 77AVEMU and should return `$FF` through the
existing `~IOSn ? 8'hff` default in `core.v:236`).

In FM-7 mode, tie `MPHYS = {4'h3, MADDRBUS}` and nothing downstream can tell the
difference.

New strobes needed in `MDECODE.v`: `$FD80-$FD8F` (write + read), `$FD90`,
`$FD92`, `$FD93` (write + read), `$FD10` (write). None of these collide with the
existing decode — `m55_q8` is the `$fdxx` term and `m54_q8` (`FD0Xn`) is
`$fd00-$fd0f`, so `$fd8x` currently falls through to the `$ff` default.

**Follow the house rule on strobe qualification.** `MDECODE.v`'s comment block
and `core.v:313-324` say it twice: writes qualify with `WTQEn`, reads with
`RDQEn` (*not* `RDEn`). Getting that wrong is P0-1 and has already cost this
project three bugs. And latch registers on the **leading** edge of the write
strobe, not the trailing edge — that is P0-3 / P1-4 / the `KANJI.v` comment.

### 5.4 Deferring the sub-system aperture (P5-6)

MMR banks `$10-$1F` alias VRAM, sub RAM, sub I/O and sub ROM into the main CPU's
space. That turns VRAM into a three-master resource (raster, sub CPU, main CPU)
and `CRTRAM.v` is three *single-port* RAMs today with `SVRADRS` muxed between the
raster and the sub CPU by `SCASSEL`.

Stage it: in P5-2, decode banks `$10-$1F` and return `$FF` (which is what CSP
does when the sub CPU is not halted anyway — `read_direct_access` at
`mainmem_readseq.cpp:152-155`: `if(!sub_halted) return 0xff;`). Then P5-6 either

- **(a)** honours CSP's gate — main-side access only while the sub is halted,
  which means the raster and one CPU at most, so the existing `SCASSEL` mux
  extends with a third input; or
- **(b)** converts `CRTRAM.v` to true dual-port block RAM (port A = raster read,
  port B = CPU/ALU read-write). Cyclone V M10K supports simple dual-port
  natively and `rtl/wd1793.sv:882` already uses a `dpram` wrapper in this repo.

**(b) is the better answer and it also retires P0-7.** With a dedicated raster
port, `core.v:459-461`'s `sub_vram_wait` — which currently stalls `SCPUCLK`
whenever the sub touches VRAM during active display — becomes unnecessary.
77AVEMU says the AV does not halt the sub for VRAM at all (`fm77av.cpp:656-664`:
`CRTCHaltsSubCPU` is true only in FM-8/FM-7 speed modes), so on the AV the wait
state is a pure FPGA artifact that makes the sub slower than the real machine.
**But (b) changes FM-7 timing too**, and P0-7's own note records that changing the
sub's cycle budget moved Thexder from 3976 to 8538 instructions/frame. Do it as
its own commit with its own `run_tests.sh` diff, not buried in an AV phase.

### 5.5 Verification

- **Unit:** a `$display`-instrumented `MMR.v` plus a hand-written 6809 stub that
  programmes `$FD80-$FD8F`, sets `$FD93 = $80`, and walks `$0000-$FBFF`
  confirming each 4 KB window lands where the table says.
- **Integration:** `--trace-mem` already prints the memory-map chip selects for a
  bus cycle (`vsim/README.md`). Add `MPHYS` to it.
- **Regression:** all eight `run_tests.sh` rows unchanged.
- **What could break:** the `MDATABUS_in` priority mux in `core.v:222-241` is a
  chain of `?:` with `~IOSn ? 8'hff` as the I/O catch-all. New `$fd8x` readback
  must be inserted *above* that line or it will read `$ff` forever — which is
  exactly the shape of P0-1 and will look like "MMR readback isn't implemented".

---

## 6. Video (P5-5, P5-7, P5-8)

### 6.1 VRAM: 96 KB in two pages [verified across all three]

| | FM-7 | FM77AV |
|---|---|---|
| VRAM | 48 KB | **96 KB** |
| organisation, 8-colour | 3 planes × 16 KB | 2 pages × (3 planes × 16 KB) |
| plane bits | `addr[15:14]` | `addr[15:14]`, page selected separately |

CSP `fm7_display.h:17-25` (`__FM7_GVRAM_PAG_SIZE 0x2000*12` = 96 KB for
`_FM77AV_VARIANTS`), 77AVEMU `fm77avdef.h:25` (`FM77AV_VRAM_BANK_SIZE=0xC000`)
with banks 1-2 in a 96 KB `extVRAM` array, MAME `fm7.cpp:1725` (`m_video_ram`
`0x18000`). All three agree.

RTL: `CRTRAM.v`'s three `ram #(14,8)` become `ram #(15,8)` with the page bit
prepended, and `MB60H010.v`'s `SVRADRS` widens from `[13:0]` to `[14:0]`. In FM-7
mode the page bit is tied to 0, so the FM-7 uses the low half and behaves
identically.

**Page control is `$D430`, sub side**, and all three references agree on the bits:

| bit | write | read |
|---|---|---|
| 7 | NMI mask (1 = masked) | display active (see disagreement below) |
| 6 | **display** page | 1 |
| 5 | **access** (CPU) page | 1 |
| 4 | — | **ALU not busy** (1 = idle) |
| 2 | fine-offset enable | VSYNC |
| 1:0 | CG font bank (§8) | b0 = power-on-reset flag |

CSP `display.cpp:823-847` (write) / `810-821` (read); 77AVEMU
`fm77avcrtc.cpp:271-303` + `fm77avmemory.cpp:416-427`; MAME `fm7_v.cpp:780-823`.

> **Disagreement, bit 7 read.** CSP: `if(!hblank) ret |= 0x80` — 1 during active
> display. MAME: *"b7 = 0 if in VBlank"* — also 1 during active display.
> 77AVEMU: `if(true!=InBlank(...)) data &= 0x7F` — 1 during *blank*, the
> opposite. Two against one; follow CSP. **I have not verified this against
> software.**

### 6.2 Scroll: two offsets, and a fine mode

The FM-7 has one VRAM offset pair at `$D40E`/`$D40F`, already implemented in
`MB60H010.v` as `SRH`/`SRL` → `VOFFSET = {SRH, SRL[7:5], 5'd0}` (note the
`[7:5]`, i.e. the 32-byte granularity). The AV has **one offset register per
page** and a fine mode:

- `offset_77av` (`$D430` bit 2) = 0 → mask `0x7FE0` (32-byte, the FM-7 behaviour
  `MB60H010.v` already implements); = 1 → mask `0x7FFF` (byte granularity).
  CSP `display.cpp:2884-2926`; 77AVEMU `fm77avcrtc.cpp:271-284`
  (`VRAMOffsetMask = (data&4) ? 0xffff : 0xffe0`).
- Two registers: `offset_point` and `offset_point_bank1`, selected by the
  *access* page. The *display* page picks which one the raster uses.

CSP additionally models `$D40E`/`$D40F` as a two-write toggle that only commits
on the second write (`display.cpp:2888-2896`). 77AVEMU does not. **[unverified]
which is right**; the FM-7 core's current behaviour (latch each byte
independently on `negedge SREGLn`/`SREGHn`) matches 77AVEMU and works, so leave
it and only revisit if a title scrolls wrong.

### 6.3 Analog palette (P5-7)

| Addr | Function |
|---|---|
| `$FD30` | index bits 11:8 (`data & 0x0F`) |
| `$FD31` | index bits 7:0 |
| `$FD32` | **Blue**, 4 bits |
| `$FD33` | **Red**, 4 bits |
| `$FD34` | **Green**, 4 bits |

**4096 entries × 12 bits = 6 KB of palette RAM.** CSP `display.cpp:873-940`
(`analog_palette_r/g/b[4096]`, `fm7_display.h:215-217`); 77AVEMU
`fm77avcrtc.h:19-20` + `fm77avcrtc.cpp:305-330`; MAME `fm7_v.cpp:742-777` with
`set_entries(4096)` at `fm7.cpp:2016`.

Reset default is the **identity ramp**, not black: CSP `display.cpp:288-295`
sets `analog_palette_r[i] = i & 0x0f0`, `g = (i & 0xf00) >> 4`,
`b = (i & 0x00f) << 4`. 77AVEMU zeroes it instead (`fm77avcrtc.cpp:12-18`). CSP
is primary and the identity ramp is what makes an un-programmed 4096-colour
screen show something rather than black — **follow CSP.**

> **The index bit order is a MAME trap, and it is P1-5 all over again.**
> CSP's identity ramp (`display.cpp:288-295`) and its display mask
> (`vram.cpp:334-336`: `B = 0x00f`, `R = 0x0f0`, `G = 0xf00`) both say the index
> is **`{G[3:0], R[3:0], B[3:0]}`**. 77AVEMU's renderer builds the same order
> (`fm77avrender.cpp:229-244`, code = `G3..G0,R3..R0,B3..B0`). MAME packs
> `B | G<<4 | R<<8` (`fm7_v.cpp:1129-1166`) — **red and green swapped**, exactly
> the way `fm7_v.cpp:1173-1178` swaps them for the digital planes in P1-5.
> **Follow CSP/77AVEMU.**

4-bit → 8-bit expansion: 77AVEMU replicates (`data|(data<<4)`, max `$FF`), MAME
shifts (`data << 4`, max `$F0`), CSP ORs in `0x0f` when non-zero. Replication is
right; it is also what keeps FM-7 output bit-identical (§6.4).

Reads of `$FD30-$FD34` are unimplemented in all three references. Let them fall
through `core.v`'s `~IOSn ? 8'hff`.

### 6.4 The video output path — the part that can break the FM-7

`core.v:11` outputs `grb[2:0]`, and both tops expand it:

```verilog
assign VGA_R = {8{grb[1]}};    // FM-7_MiSTer.sv:360-362 and vsim/sim.v
assign VGA_G = {8{grb[2]}};
assign VGA_B = {8{grb[0]}};
```

Change `core.v` to output `[11:0] rgb444` as `{r[3:0], g[3:0], b[3:0]}`, and in
**both** tops:

```verilog
assign VGA_R = {rgb444[11:8], rgb444[11:8]};   // replicate 4 -> 8
assign VGA_G = {rgb444[7:4],  rgb444[7:4]};
assign VGA_B = {rgb444[3:0],  rgb444[3:0]};
```

In FM-7 mode `PAL.v` emits `$F` or `$0` per component, replication gives `$FF`
or `$00`, and every existing screenshot is **byte-identical**. That matters more
than it sounds: `vsim/shots-ref/` is a tracked visual baseline, `triage.py`
hashes PNGs to cluster identical screens, and its "F-BASIC banner" detector is a
*size band* (5050-5350 bytes, `triage.py`). A one-LSB change in the colour output
would recompress every PNG and silently invalidate the whole P4-14 dataset.

`vsim/sim.v` deliberately replicates the bit today where `FM-7_MiSTer.sv` drives
only bit 7 (see the note at `vsim/sim.v:24-26`). That difference disappears with
this change, which is a small bonus.

Bit replication is also the framework's own convention, so this is not an
invention: `sys/video_mixer.sv:62` declares `DWIDTH = HALF_DEPTH ? 3 : 7` and
line 93 widens with `{R,R}`. This core does **not** instantiate `video_mixer` or
`gamma_corr` today (`FM-7_MiSTer.sv:358-362` assigns `VGA_R/G/B` directly), so
the minimal change above is enough. Adopting `video_mixer #(.HALF_DEPTH(1))`
would additionally buy scanlines, the scandoubler and gamma — worth considering
as a separate commit, but it is not on the AV critical path and it would change
FM-7 output.

Worth knowing for expectations: `sys/sys_top.v:72` declares `output [5:0] VGA_R`
— the DE10-Nano's analog DAC is 6 bits per gun. RGB444 survives intact over
HDMI and is truncated to RGB444-in-6-bits on analog VGA, which is lossless for
4-bit source data.

### 6.5 320x200 4096-colour mode (P5-8)

`$FD12` bit 6, main side. `0` = 640x200 8-colour, `1` = 320x200 4096-colour.
CSP `fm7_mainio.cpp:1607-1611` → `display.cpp:2098-2147`; 77AVEMU
`fm77avcrtc.cpp:221-237`; MAME `fm7_v.cpp:825-861`.

**This is not a width change.** In 4096-colour mode the VRAM is reorganised into
**12 sub-planes of 8 KB**, six per page:

```
page 0:  B3 @+$0000   B2 @+$2000   R3 @+$4000   R2 @+$6000   G3 @+$8000   G2 @+$A000
page 1:  B1 @+$0000   B0 @+$2000   R1 @+$4000   R0 @+$6000   G1 @+$8000   G0 @+$A000
```

CSP `vram.cpp:753-767` and 77AVEMU `fm77avrender.cpp:189-228` give exactly this,
independently. 40 bytes/line × 200 lines = 8000 bytes per sub-plane, which fits
`$2000`. The 12-bit pixel code `{G3..G0, R3..R0, B3..B0}` indexes the analog
palette. **In this mode the two pages are not double buffers — they are the low
two bits of every colour gun.** CSP `display.cpp:375-390` sets
`page_mask = 0x1fff`, `pagemod_mask = 0xe000`, i.e. the plane selector moves from
`addr[15:14]` to `addr[15:13]`.

**Pixel clock: double, do not re-time.** `MB60H010.v` generates a 1024×262
raster with `SFTCLK` at 16.128 MHz (`clk_en #(CORE_CLK_16)`). For 320-wide,
output each pixel twice at the same 16 MHz rather than halving the clock. That
keeps `HSync`/`VSync`/`HBLANK`/`VBLANK`/`ce_pix` and the MiSTer scaler
configuration completely unchanged, and keeps every `vsim` screenshot at 640×200
so the sweep tooling needs no changes. MAME reconfigures the screen to 512×262
instead (`fm7_v.cpp:838-848`) — do not copy that; it is an emulator convenience.

`$FD12` readback (CSP `fm7_mainio.cpp:1176-1180`, reset `$BC`): b6 = mode320,
b1 = display active, b0 = VSYNC. 77AVEMU agrees (`fm77avcrtc.cpp:238-257`, base
`0xBF`). The two disagree on the idle bits; use CSP's `$BC`.

**400-line and 260k-colour modes are AV40 only** (CSP gates all of it behind
`HAS_400LINE_AV`, `fm7.h:152`; 77AVEMU's `SCRNMODE_320X200_260KCOL` has no
renderer at all). Out of scope.

---

## 7. The MB61VH010 drawing ALU (P5-9)

### 7.1 What it is

A read-modify-write engine that sits on the sub CPU's VRAM path and operates on
**all three planes at the same byte offset simultaneously**. It is *not*
command-triggered: it fires on any VRAM access while `$D410` bit 7 is set, and
**the CPU's data byte is discarded** — the written value comes from the ALU's own
colour/tile/mask registers.

CSP `display.cpp:3174-3182`:

```c
void DISPLAY::write_cpu_vram_data8(uint32_t addr, uint8_t data)
{
	if(use_alu) { call_read_data8(alu, addr); return; }   // data thrown away
```

and a **read** fires it too (`display.cpp:2538-2547`). 77AVEMU says the same and
explains why both work (`fm77avmemory.cpp:820-828`): *"Hardware drawing is
supposed to be dummy-READ a VRAM byte. However, Pro Baseball Fan (Telenet) is
dummy-writing to a VRAM byte to use hardware drawing. So, apparently reading and
writing both work."* MAME agrees, with its own bemused comment
(`fm7_v.cpp:586-589`): *"ALU active, writes to VRAM even when reading it (go
figure)."*

### 7.2 Registers

| Addr | R/W | Function |
|---|---|---|
| `$D410` | R/W | command: b7 enable, b6 compare enable, b5 compare sense, b2:0 op |
| `$D411` | R/W | logical colour, 3 bits (b0=B, b1=R, b2=G) |
| `$D412` | R/W | write mask, 8 bits — **1 = preserve that pixel** |
| `$D413` | **R** | compare result, 8 bits, one per pixel, MSB = leftmost |
| `$D413-$D41A` | **W** | compare colours 0-7; b2:0 = GRB, **b7 = slot disabled** |
| `$D41B` | R/W | plane disable, 3 bits (1 = plane disabled); reset `$F8` |
| `$D41C/D/E` | W | tile pattern Blue / Red / Green |
| `$D41F` | W | tile "L" — 4th plane, **not implemented anywhere**, skip |
| `$D420/$D421` | W | line address offset hi/lo |
| `$D422/$D423` | W | line stipple pattern, 16 bits |
| `$D424-$D42B` | W | X0 / Y0 / X1 / Y1, hi/lo each. **Writing `$D42B` triggers the line draw.** |
| `$D430` b4 | R | 1 = ALU idle |

CSP `mb61vh010.h:63-79` + `display.cpp:2928-2951, 3060-3065`; 77AVEMU
`fm77avdef.h:232-259` + `fm77avcrtc.cpp:452-657`; MAME `fm7_v.cpp:914-1073`.
The three agree on every address.

### 7.3 The byte operation, as RTL

```
for plane in 0..2:
    if plane_disabled[plane] or multipage_access_masked[plane]: continue
    src  = vram[plane][addr]
    bm   = f(op, colour[plane], src, tile[plane])
    new  = (src & mask) | (bm & ~mask)
    vram[plane][addr] = new
```

with

| op | `$D410[2:0]` | `bm` |
|---|---|---|
| PSET | 0 | `colour[plane] ? ~mask : 0`, merged as `(src & mask) \| bm` |
| BLANK | 1 | — (result is `src & mask`) |
| OR | 2 | `colour[plane] ? $FF : src` |
| AND | 3 | `colour[plane] ? src : $00` |
| XOR | 4 | `(colour[plane] ? $FF : $00) ^ src` |
| NOT | 5 | `~src` |
| TILEPAINT | 6 | `tile[plane]` |
| COMPARE | 7 | compare only, no write |

CSP `mb61vh010.cpp:15-331`; 77AVEMU `fm77avcrtc.cpp:411-449`.

> **77AVEMU treats op 1 as NOT, not BLANK** (`fm77avcrtc.cpp:442-445`, comment:
> *"FM77AV Demo uses 1. My guess is it is for erasing a line."*). CSP has a
> distinct `do_blank()` (`mb61vh010.cpp:52-68`) that writes `src & mask`. MAME
> calls it invalid but notes *"still does something though (used by Laydock)"*
> (`fm7_v.cpp:386`). CSP is primary — implement `src & mask` — but this is worth
> a note in the RTL because `FM77AV demo` is in the test corpus (§11.1) and is
> exactly the title 77AVEMU cites.

**Compare stage** (`$D410` b6): builds a 3-bit GRB colour per pixel from the
three planes, compares against up to 8 enabled compare slots, and produces an
8-bit hit mask readable at `$D413`. That mask then gates the write:

```
if (cmp_enable) {
    if (cmp_invert) new = (src & cmp_result) | (new & ~cmp_result);
    else            new = (src & ~cmp_result) | (new &  cmp_result);
}
```

CSP `mb61vh010.h:250-281` and `mb61vh010.cpp:287-331`; MAME `alu_mask_write` at
`fm7_v.cpp:106-133` is the same expression. The compare colour is masked by the
*plane-disable* register before comparison, and slots with bit 7 set never match.

**`$FD37`'s CPU-access mask also masks the ALU.** CSP forwards it
(`display.cpp:452`, `SIG_ALU_MULTIPAGE`); 77AVEMU ORs it into the bank mask with
a note that this was verified on real hardware on 2022/08/05
(`fm77avcrtc.cpp:410`). `FLAGS.v` already produces `VPAGE1n/2n/3n` from `$fd37`
bits 2:0, so this is a wire, not new logic.

### 7.4 LINE

Bresenham from (X0,Y0) to (X1,Y1), X 10-bit, Y 9-bit, triggered by the write to
`$D42B`. Address per pixel is `(y * bytes_per_line) + (x >> 3)` plus the
`$D420/$D421` offset, masked to the plane size.

Two things make it more than a plain Bresenham:

1. **The stipple register rotates.** `line_style` is a 16-bit shift register;
   bit 15 decides whether the pixel is drawn, by clearing that pixel's bit in
   `mask_reg`. CSP `mb61vh010.h:144-189` (`put_dot`).
2. **Pixels accumulate into one byte-wide ALU op.** `put_dot` builds up
   `mask_reg` while consecutive pixels share a byte address and only issues the
   ALU operation when the address changes. `put_dot8` handles a full aligned
   byte in one go. CSP `mb61vh010.cpp:451-624`.

MAME implements the address arithmetic but **stores `line_style` and never reads
it** (`fm7_v.cpp:521-569`) — line patterning is unimplemented there. Another
reason not to use MAME as the model.

### 7.5 Busy, and the interaction with `sub_vram_wait`

There is no good timing reference:

- CSP models busy **only for LINE**, as `total_bytes / 16.0` µs — i.e. 16 VRAM
  bytes per microsecond (`mb61vh010.cpp:628-638`). The per-byte busy
  registration is commented out at `mb61vh010.cpp:377-378`.
- 77AVEMU also models only LINE, at `HD_LINE_TIME_PER_PIXEL = 500` ns, with the
  comment *"I should measure in the actual hardware. But, for the time being,
  let's make a wild guess."* (`fm77avcrtc.h:33-36`).
- MAME's `m_alu.busy` is **never assigned 1 anywhere** — grep confirms `fm7_v.cpp`
  only clears it — so `$D430` bit 4 always reads "idle".

Neither reference stalls the sub CPU for a per-byte ALU op; software polls
`$D430` bit 4 after a LINE.

**The FPGA does have to stall**, because a byte op is at minimum a read cycle
followed by a write cycle on the same VRAM, and the sub CPU issued it as a single
bus cycle. `core.v:459-461` already has exactly the right mechanism:

```verilog
wire sub_vram_sel  = ~(SDRAMBn & SDRAMGn & SDRAMRn);
wire sub_vram_wait = sub_vram_sel & ~SCASSEL;
wire SCPUCLK_w     = SCPUCLK & ~sub_vram_wait;
```

Extend `sub_vram_wait` with `| alu_busy`. The comment above it (P0-7) explains
why this and not `nHALT`/`nDMABREQ`: mc6809i samples both at
`CPUSTATE_FETCH_I1`, i.e. at instruction boundaries, so neither can express a
wait state.

Because `CRTRAM.v` is three parallel RAMs sharing one address, all three planes
read in the same cycle and write in the same cycle — **an ALU byte op is 2 VRAM
cycles, not 6.** That is the single thing that makes this tractable.

For LINE, run a state machine issuing one `put_dot`-equivalent per cycle and hold
`$D430` bit 4 low for the duration. At 48 MHz that is far faster than the real
chip's ~16 bytes/µs, which is safe — software polls for *not busy*.

### 7.6 What could break

- If `alu_busy` is folded into `sub_vram_wait` incorrectly, the sub CPU stalls
  forever and every AV title reports a low sub instruction rate. `sub == 8721`
  (the sub sitting in its ROM idle loop, P4-14) is the tell for "never given
  work"; a *lower* number is the tell for "stalled".
- The ALU writes VRAM through the same port `CRTRAM.v` gives the sub CPU. If it
  is wired to the raster port instead, the display tears in a way that looks like
  a plane-order bug. P1-5 is the cautionary tale here.

---

## 8. Boot / initiate ROM (P5-3) and sub-system ROM (P5-4)

### 8.1 The AV boot sequence

1. At reset the initiate ROM is enabled (`avBootROM = true`, 77AVEMU
   `fm77avmemory.cpp:468-472`; `initiator_enabled = true`, CSP
   `fm7_mainmem.cpp:53-57`) and MMR is off.
2. `$6000-$7FFF` reads the whole 8 KB `initiate.rom` (CSP
   `mainmem_readseq.cpp:126-140`; MAME maps it at physical `0x36000`,
   `fm7.cpp:1558`).
3. The **reset vector comes from the initiate ROM**, so the CPU starts at `$6000`.
   The three references model this differently:
   - CSP: `$FFFE-$FFFF` only, from `initrom[$1FFE-$1FFF]` (`mainmem_readseq.cpp:133-138`).
   - MAME: all of `$FFF0-$FFFF`, from `initrom[$1FF0-$1FFF]` (`vector_r`, `fm7.cpp:289-301`).
   - 77AVEMU: synthesises `$6000` directly at the reset vector
     (`fm77avmemory.cpp:653-669`) rather than reading the ROM.

   **Follow CSP** (`$FFFE-$FFFF` only). It is the primary authority, it is the
   narrowest claim, and it is consistent with `m139`'s existing decode which
   already routes `$FFE0-$FFFB` to RAM and only `$FFFC-$FFFF` to the boot ROM
   (I extracted the `m139.v` table: `$fc00-$fc7f` RAM, `$fc80-$fcff` shared,
   `$fd00-$fdff` I/O, `$fe00-$ffdf` boot ROM, `$ffe0-$fffb` RAM, `$fffc-$ffff`
   boot ROM). That table is *already* the AV's map.
4. `$FE00-$FFDF` is **RAM, seeded from `initiate.rom`** at `$1800` (BASIC) or
   `$1A00` (DOS) per `$FD0B`'s boot mode, with the reset vector in that RAM
   forced to `$FE00` (CSP `mainmem_utils.cpp:290-299`).
5. The initiate ROM sets up the machine and writes `$FD10` bit 1 to unmap itself,
   after which `$6000-$7FFF` is plain RAM.

**The `$FD93` bit 0 quirk, verified on real hardware by CaptainYS**
(`fm77avmemory.h:178-183`):

> *"This flag ($FD93 bit0) does not work like Shadow RAM and F-BASIC ROM, which
> if I disable Shadow RAM, F-BASIC ROM will re-appear. Once I set to RAM mode,
> change bytes in FE00 to FFE0, change back to ROM mode, the changed bytes stays.
> Original DOS or BASIC BOOT ROM won't re-appear."*

So `$FD93` bit 0 is a **write-enable on the boot RAM**, not a ROM/RAM selector.
MAME implements exactly that (`av_bootram_w`, `fm7.cpp:889-894`: `if(!(m_mmr.mode
& 0x01)) return;`). This is easy to get wrong and would look like "the AV
randomly corrupts its vectors".

### 8.2 What happens to `ROMS.v`

`ROMS.v` is **CRLF** — check with `file` after any scripted edit.

In AV mode:
- `m152` (the 2 KB four-bank boot chip) is not instantiated in the read path.
  `bootrom_sel` becomes the BASIC/DOS selector for the boot-RAM seed instead.
- `m151` (F-BASIC) loads `fbasic30.rom.mem` instead of `fbasic300.rom.mem`. Two
  `rom` instances with a mux, or one instance addressed by
  `{machine_is_av, MADDRBUS[14:0]}` over a 64 KB `.mem` built by concatenating
  the two images. The latter is one block-RAM instance instead of two and is
  what I would do.
- A new 8 KB `initiate` `rom` instance, selected when
  `initiate_enabled && MADDRBUS[15:13] == 3'b011`.
- A new 480-byte boot RAM at `$FE00-$FFDF`, initialised at reset from the
  initiate ROM image. **Initialising block RAM from another block RAM at reset
  needs a small copy state machine**, or — simpler — a second `rom` instance over
  `initiate.rom` addressed at `$1800`/`$1A00` feeding a `ram` write port during
  the 21.8 ms reset window. 480 bytes at 48 MHz is 10 µs; there is room.

`ff_q` (the `$fd0f` F-BASIC ROM/RAM flip-flop) stays as-is: `$FD0F` behaves
identically on both machines (CSP `fm7_mainio.cpp:1599-1602` has no variant
gate; 77AVEMU `fm77avio.cpp:186-188` likewise). Note that CSP has `$FD0B` aliasing
`$FD0F` on the **FM-7 only**, because *"RFD0F and WFD0F are unaware of AB2"*
(77AVEMU `fm77avio.cpp:152-164`) — on the AV, `$FD0B` is the boot-mode readback
instead. This core does not implement the `$FD0B` alias today, so nothing to
undo.

### 8.3 Sub-system ROM: it is `$FD13`, not `$D42E`

**Correcting the brief:** the sub-ROM bank register is at **`$FD13` on the main
CPU**, not `$D42E`. All three references agree, and MAME has no `$D42E` handler
at all:

- CSP `fm7_mainio.cpp:1612-1616` → `DISPLAY::set_monitor_bank`, `display.cpp:849-870`.
- 77AVEMU `PhysicalMemory::WriteFD13`, `fm77avmemory.cpp:349-386`.
- MAME `av_sub_bank_w`, `fm7_v.cpp:863-912`, mapped at `fm7.cpp:1483`.

`$D42E` is the **AV40 sub-RAM bank register** (77AVEMU `fm77avmemory.cpp:397-402`:
RAM-A bank in bits 4:3, RAM-B bank in bits 2:0, kanji level in bit 7; CSP
`display.cpp:2953-2958` agrees). Out of scope for base AV.

| `$FD13[1:0]` | `$E000-$FFFF` (8 KB monitor) | `$D800-$DFFF` (2 KB font) |
|---|---|---|
| 0 | `subsys_c.rom` + `$0800` | `subsys_c.rom` + `$0000` |
| 1 | `subsys_a.rom` | `subsyscg.rom` bank `$D430[1:0]` |
| 2 | `subsys_b.rom` | `subsyscg.rom` bank `$D430[1:0]` |
| 3 | `subsyscg.rom` | `subsyscg.rom` bank `$D430[1:0]` |

CSP `read_subsys_monitor`, `display.cpp:2648-2672`. Note MAME **does not** map
`subsys_c`'s first `$800` bytes anywhere (the `membank("bank20")` calls in
`av_sub_bank_w` are commented out) — a modelling deviation; do not copy it.

`subsyscg.rom` is **four 2 KB font banks**, not an 8 KB monitor: 77AVEMU loads it
as `ROM_ASCII_FONT[4*ASCII_FONT_ROM_SIZE]` (`fm77avmemory.cpp:49`), and the bank
is `$D430[1:0]` (0 = katakana, 1 = hiragana, 2 = ROM1, 3 = ROM2 —
`fm77avmemory.cpp:1047-1064`).

**This maps directly onto `SMEM.v` as it stands.** `SDECODE.v`'s `m86` decodes
`$D800-$DFFF` → `SROMDn` → `m153` (`rom #(..., 11, 8)`, 2 KB) and
`SROMSELn` → `m154` (`rom #(..., 13, 8)`, 8 KB). The AV change is:

- `m153`'s image becomes `{2 bits of source select, 11 address bits}` over a
  10 KB blob of `subsys_c[0:$7FF]` + `subsyscg`'s four banks;
- `m154`'s image becomes `{2 bits, 13 address bits}` over `subsys_c[$800:$27FF]`,
  `subsys_a`, `subsys_b`, `subsyscg`.

**Writing `$FD13` resets the sub CPU** — on all three references, and even when
the value does not change. CSP `display.cpp:854-861` (deferred if the sub is
halted); 77AVEMU `fm77avio.cpp:193-203`: *"Confirmed on actual FM77AV. Sub-CPU
resets even if the monitor type doesn't change. POKE &HFD13,0 from F-BASIC will
reset sub-CPU."* MAME sets busy and pulses reset (`fm7_v.cpp:905-909`) but skips
it when the value is unchanged — MAME is wrong here; follow CSP/77AVEMU.

### 8.4 Sub map changes

Two small `SDECODE.v` changes, both AV-gated:

1. **`$D500-$D7FF` becomes hidden RAM** (768 bytes) on the AV; on the FM-7 it is
   part of the MMIO region. CSP `display.cpp:2554-2596` (`submem_hidden[0x300]`).
   Today `m64_11 = m86_y6 | SADDRBUS[10]` makes `SSMEMn` cover `$D000-$D3FF` and
   `m64_8` makes the I/O decoders cover `$D400-$D7FF`.
2. **Sub I/O aliases every 64 bytes, not 16.** CSP `display.cpp:2753-2759`:
   `addr = (addr - 0xd400) & 0x003f` on base AV versus `& 0x000f` on the FM-7.
   The ALU at `$D410-$D42B` needs bits 5:4 decoded, which the current `x74138`
   trio (`SADDRBUS[3:0]` only) does not do.

### 8.5 Clock

`CLKCTRL.v` is **CRLF**. It already has the mux:

```verilog
assign MCPUCLK = switch ? CLK4_9 : SCLK1;   // 4.9152 MHz -> E=1.2288, or 8 MHz -> E=2
```

`SCLK1` gives E = 2.000 MHz, which is what the AV wants. But `switch` also drives
`$FD00` bit 0 (via `KEYBOARD.v`), and MAME hardcodes that bit to `1` on the AV
(`keyboard_r`, `fm7.cpp:490-505`). **Decouple them**: add a separate
`machine_is_av` input so the clock select and the `$FD00` bit 0 report can differ.

> **Three references, three clock speeds.** MAME: 2.016 MHz (`16.128 MHz / 8`,
> `fm7.cpp:1986`). CSP: 1.798 MHz, dropping to **1.565 MHz whenever MMR or TWR is
> enabled** (`fm7_common.h:79-85`, `fm7_mainmem.cpp:102-157`). 77AVEMU: 1.8 MHz,
> with a note that *"the catalog says 2 MHz but measurement implies 1.8 MHz"*
> (`mc6809.h:22`, `fm77avio.cpp:806-809`). 2 of 3 measured ~1.8 MHz. But
> 48 MHz / 1.8 MHz is not an integer, and `clk_en` takes an integer divisor, so
> 2.000 MHz via the existing `SCLK1` is the only cheap option. **Start there and
> note it.** If AV titles run visibly fast, the MMR slowdown is the first thing
> to model.

---

## 9. Sound (P5-10)

### 9.1 What the AV actually has

**One YM2203, not an AY plus a YM2203.** CSP `sound.cpp:46-52`:

```c
 #if defined(_FM77AV_VARIANTS)
	opn_psg_77av = true;
```

and `sound.cpp:107-133` routes `$FD0D`/`$FD0E` to OPN #0 when that flag is set.
CSP does not even construct a PSG object for AV variants (`fm7.cpp:148-167`).
77AVEMU says the same in a comment (`fm77avsound.cpp:396-406`): *"FM77AV and
later writes to the PSG-part of YM2203C. Pre-FM77AV models had separate PSG."*

| Port | Function |
|---|---|
| `$FD0D` | control, masked to **2 bits** — the AY-compatible subset |
| `$FD0E` | data |
| `$FD15` | control, **4 bits** — adds status read (4) and joystick (9) |
| `$FD16` | data |
| `$FD17` | b3 = OPN IRQ, active low |

Command encoding (CSP `sound.cpp:308-348`, MAME `fm7_update_psg`,
`fm7.cpp:827-858`): `0` = inactive, `1` = read data, `2` = write data,
`3` = latch address, `4` = read status, `9` = joystick port.

Clock: **4.9152 MHz / 4 = 1.2288 MHz** — CSP `fm7.cpp:833-835`, MAME
`fm7.cpp:1996`. That is the same rate `SOUND.v` already feeds the AY
(`clk_en #(CORE_CLK_1_2)`), so no new divider.

**Joystick.** The sticks hang off the SSG's port B, exactly as on the FM-7.
`SOUND.v` currently snoops the bus for this because `ym2149_audio.v` has no I/O
ports at all (the P4-2 comment in `SOUND.v`). 77AVEMU notes one AV-specific
detail (`fm77avsound.cpp:272-280`): writes to SSG register 7 are forced
`data = (data & 0x3F) | 0x80` — *"Observed on real FM77AV"* — because the top two
bits control joystick direction.

### 9.2 The `ym2149_audio.v` problem, and what to replace it with

`rtl/ym2149_audio.v` is 2143 lines of machine-translated VHDL (`n###_o` signal
names throughout), has **no I/O ports**, and is PSG-only. It cannot become a
YM2203: the FM half is four operators × three channels with envelope generators
and timers, and there is no realistic path from a translated PSG to that. Source
an existing core.

**`jt03` from `jotego/jt12` is the right answer, and it is a superset of what
the FM-7 needs too.** [verified — source read, not recalled]

```verilog
module jt03(
    input rst, input clk, input cen,          // cen = YM2203 master-clock rate
    input [7:0] din, input addr,              // addr = A0, one bit
    input cs_n, input wr_n,
    output [7:0] dout, output irq_n,
    // I/O pins used by YM2203 embedded YM2149 chip
    input  [7:0] IOA_in,  input  [7:0] IOB_in,
    output [7:0] IOA_out, output [7:0] IOB_out,
    output IOA_oe, output IOB_oe,
    output [7:0] psg_A, psg_B, psg_C,
    output signed [15:0] fm_snd, output [9:0] psg_snd,
    output signed [15:0] snd, output snd_sample, ... );
```

- It is a thin wrapper over `jt12_top` with `use_ssg(1), num_ch(3), use_lfo(0),
  use_pcm(0), use_adpcm(0)` — i.e. a real YM2203, SSG included.
- **It exposes `IOA`/`IOB`.** That is the joystick path, and adopting it deletes
  the whole bus-snooping block in `rtl/SOUND.v:40-100` that exists only because
  `ym2149_audio.v` has no I/O ports (the P4-2 comment).
- `cen` is the chip's φM master clock; `jt12_div.v` implements the real
  prescaler internally (reset default FM ÷6 / SSG ÷4, switchable by writes to
  registers `$2D`/`$2E`/`$2F` — which is exactly the prescaler special-case CSP
  documents at `sound.cpp:158-175`). So there is nothing to divide by hand.
- Licence: **GPL-3.0-or-later**. Not a blocker — `FM-7_MiSTer.sv:3-6` grants
  GPL "version 2 … or (at your option) any later version", as do `rtl/wd1793.sv`,
  `rtl/sdram.sv` and all of `sys/`. The combined work simply becomes GPLv3 and
  can no longer be downgraded to bare v2. Worth a line in the commit message.
- File list is ~35 `jt12_*.v` files **plus the separate `jotego/jt49` repo**,
  which `jt12` pulls in as a git submodule. Both go in `files.qip` and
  `vsim/Makefile`. `MiSTer-devel/PC88_MiSTer`'s `rtl/sound/jt03.qip` is a
  ready-made list to copy.

**There is no alternative.** IKAOPN (`ika-musume/IKAOPN`, BSD-2) has **no HDL at
all** — the repo is a licence, a README and some schematic PDFs, with YM2203
listed under "Initial Goals". `sauraen/YM2612` is a 2015 architecture study, not
a core. `gh search` finds no other YM2203 in HDL anywhere.

**Closest working reference for this core's bus shape:**
`MiSTer-devel/ZX-Spectrum_MISTer/rtl/turbosound.sv` drives `jt03` from an
AY-style BDIR/BC1 bus, which is exactly `$FD0D`/`$FD0E`. `PC88_MiSTer`
(`rtl/PC88MiSTer.vhd:2376`) drives it as a real YM2203 with joysticks on
`IOA_in <= "1111" & pJoy(3 downto 0)`.

> **Three incompatible `jt03` forks are in the wild.** Upstream `jotego/jt12`
> has `psg_A/B/C [7:0]` and `psg_snd [9:0]`; `PC88_MiSTer`'s copy widens them to
> `[9:0]`/`[11:0]`; `ZX-Spectrum_MISTer`'s copy **drops `IOA`/`IOB` entirely**.
> Vendor deliberately from upstream and record the commit.

**A real risk in the "one chip for both machines" plan:** `jt12_top` hardwires
its internal `jt49` to `.sel(1'b1)` and `JT49_DIV=2`, whereas a standalone
`jt49` defaults to `CLKDIV=3` and an AY-3-8910 wants `sel=0` (÷16). So FM-7-mode
PSG pitch through `jt03` will **not** automatically match a standalone `jt49`.
This is the same question as P4-3 in `TODO.md` (`sel_n_i = 1'b1`, "needs a human
ear"). Two ways out:

- Use `jt49_bus` (from `jotego/jt49`) for the FM-7 and `jt03` for the AV.
  `jt49_bus` is the BDIR/BC1 wrapper and is a direct drop-in for `SOUND.v`'s
  existing `{bdir, bci}` decode: `MiSTer-devel/MSX1_MiSTer/rtl/msx1.v:325` is
  the pattern, with `.sel(0)` and the joystick on `IOA_in`. Two audio cores in
  the build, but each is right for its machine.
- Use `jt03` for both and accept whatever `sel=1` gives on the FM-7 — but that
  changes FM-7 sound, which is a regression, not a refactor.

I would take the first. It also closes P4-3 properly instead of moving it.

**Staging inside the phase:**

1. **Replace `ym2149_audio.v` with `jt49_bus` for the FM-7 first, as its own
   commit.** This is not AV work — it fixes P4-2's joystick hack and P4-3's
   prescaler question, and it is testable with `run_tests.sh` plus an ear.
2. Add `jt03` for AV mode, `$FD15`/`$FD16` wired to `addr`/`din` as A0=0/A0=1,
   `$FD0D`/`$FD0E` continuing to drive the SSG half through the same chip.
3. If step 2 stalls, a legitimate stopping point is: keep the SSG working and
   stub `$FD15`/`$FD16` to `$FF`. AV titles that use the SSG sound as they do on
   the FM-7; FM music is silent. Strictly better than today, and it unblocks
   everything else.

> **Clock rate is unconfirmed.** MAME (`fm7.cpp:1996`, `YM2203(config, m_ym,
> 4.9152_MHz_XTAL / 4)`) and CSP (`fm7.cpp:833-835`) both say **1.2288 MHz** —
> the same rate `SOUND.v` already generates with `clk_en #(CORE_CLK_1_2)`. That
> is unusually low for a YM2203 (PC-88 runs its at 3.9936 MHz), so it is worth
> checking against an FM77AV service manual before trusting the FM pitch. Two
> references agreeing does not make it right when both may have copied the same
> mistake.

---

## 10. Other AV subsystems

### 10.1 Keyboard encoder `$D431`/`$D432` (P5-11)

**Do not underestimate this.** CSP's `keyboard.cpp` is 1340 lines and **661 of
them are inside `_FM77AV_VARIANTS` guards** — the AV adds an 8-bit command FIFO
with an RTC, LED control, repeat rate/delay, and three scancode modes
(`KEYMODE_STANDARD`, `KEYMODE_16BETA`, `KEYMODE_SCAN`).

The one that matters for games is **`KEYMODE_SCAN`: the AV can sense key
release.** CaptainYS makes the point in `refs/77AVEMU/readme.md:129`: *"FM-7
series until FM77AV could not sense key-release."* An AV title written around
make/break codes will not work with the FM-7 keyboard path at all.

Commands (CSP `keyboard.cpp:986-1108`, MAME `fm7.cpp:575-682` — they agree):
`$00` set mode, `$01` get mode, `$02` set LED, `$03` get LED, `$04` set repeat
type, `$05` set repeat time, `$80` RTC (up to 9 bytes), `$81`-`$84` stubs.
`$D432` b7 = LATCH (0 = ready), b0 = ACK; ACK is delayed 5 µs.

Minimum viable: implement `$00`/`$01` (mode) and `KEYMODE_SCAN`, ACK everything
else. `KEYBOARD.v` already carries the FM-7 tables and `vsim/sweep/check_kbd.py`
diffs them against CSP's header — extend that script rather than hand-checking.

The AV default at reset is `KEY_MODE_FM7` (MAME `fm7.cpp:1805`), so a title that
does not ask for scan mode is unaffected. That is why this phase can be last.

### 10.2 Sub-side kanji `$D406`/`$D407`

**The references disagree on whether base AV has it.** 77AVEMU implements it for
FM77AV (`fm77avmemory.cpp:429-449`) with the quirk that the same two addresses
are the address register on write and the data register on read. CSP gates it to
**AV20/AV40 and FM-77 only, not base AV** (`display.cpp:2774-2785`). MAME has
nothing at `$D405-$D407`.

CSP is primary → **skip it for a base-AV target.** The main-side kanji window at
`$fd20-$fd23` is unchanged and `KANJI.v` (on this branch) already implements it.

### 10.3 `$FD04` on the AV

CSP `fm7_mainio.cpp:684-686` returns `val |= 0x6c; val |= 0x10;` on base AV —
the FM-77 mode bits read back as fixed. Worth cross-referencing against
`TODO.md` P3-2's open note that *"`$fd04` bit 2 carries BUSY here; no reference
puts it there"*: on AV40 bit 2 is the sub-RAM-B write protect
(77AVEMU `fm77avmemory.cpp:315-322`), and on base AV it reads as a fixed 1. So
P3-2's note stands and the AV work gives no reason to change `TIMER.v`.

### 10.4 FDC

Unchanged for base AV, except `$FD1E` (drive mode, b6 = 320k/640k) which is
FM77AV+ only and a logerror stub even in MAME (`fm7.cpp:393-479`). Ignore it.
`refs/fm77av.zip` needs no FDC ROM. `MFD.v` and `FDC.v` are untouched.

### 10.5 Bubble casette — skip, and `TODO.md` P5 is misleading here

`TODO.md:2554-2557` lists the bubble casette as something "the FM-77 and FM77AV
add". **It is an FM-8 peripheral.** CSP builds `fm_bubblecasette.cpp` only for
`BUILD_FM8` (`CMakeLists.txt:25-26`) and dispatches it only from
`fm8_mainio.cpp:375-417`. 77AVEMU has no bubble emulation at all — only four
BIOS-call name strings. MAME has zero references anywhere in the driver.

Worse, its registers are `$FD10-$FD17` (`bubblecasette.h:21-30`), which on the AV
is initiate-ROM enable, subsystem status, sub-ROM bank and the OPN. **They
directly collide.** Do not implement it, and fix the P5 line in `TODO.md` when
this plan is adopted.

---

## 11. Testing (all phases)

### 11.1 The acceptance metric is the AV column of the P4-14 sweep

`TODO.md` P4-14 already ran all 350 disk images and split them. The FM77AV column
is the baseline to beat:

| | FM-7 (221) | **FM77AV (129)** |
|---|---|---|
| renders a rich screen | 33 | **1** |
| healthy rate, some content | 48 | **30** |
| healthy rate, drawing nothing | 108 | **82** |
| low rate with content (idling) | 1 | **2** |
| low rate, blank (crash) | 15 | **6** |
| did not boot, fell back to cassette F-BASIC | 16 | **8** |

`vsim/sweep/triage.py` already separates them: `is_av()` matches `"FM77AV"` in
the title, and the docstring already names MMR, the ALU, the analog palette,
4096-colour mode and YM2203 as the reason. Nothing in the harness needs to change
except passing `--machine`.

**[verified]** the Neo Kobe zip contains **54 archives** with `FM77AV` in the
name (unpacking to the 129 images), including two that are near-ideal early
targets:

- `FM77AV demo [FD]` and `FM77AV demo [FD] [b]` — Fujitsu's own demo disk. This
  will exercise the analog palette and the ALU harder than any game, and it is
  the title 77AVEMU singles out for the undocumented ALU op 1 (§7.3).
- `FM77AV40SX Nyuumon Disk [FD]` — an AV40SX intro disk, useful as a negative
  control: it *should* fail on a base-AV core.

Other well-known AV titles present: `Mugen Senshi Valis`, `Psy-O-Blade`,
`Might and Magic`, `Laydock`, `Daiva Story 2`, `Digital Devil Story - Megami
Tensei`, `Jesus`, `Kohakuiro no Yuigon`, `Dragon Buster`, `Argo`, `Death Force`,
`Nobunaga no Yabou`.

### 11.2 Per-phase acceptance

| Phase | Acceptance |
|---|---|
| P5-0 | `run_tests.sh` 8 rows identical. `--machine 1` changes nothing yet. |
| P5-1 | `grep -L` finds no `readmem file not found` in any log. |
| P5-2 | Hand-written MMR walk test passes; FM-7 rows identical. |
| P5-3 | **F-BASIC V3.0 prompt on screen in AV mode.** This is the milestone. |
| P5-4 | `POKE &HFD13,1` from AV F-BASIC changes the sub monitor and resets the sub CPU. |
| P5-5 | A title that double-buffers shows no tearing; `$D430` writes visible in `--trace-io`. |
| P5-6 | Main CPU can `PEEK` VRAM through an MMR window. |
| P5-7 | Digital-palette FM-7 screenshots **byte-identical**; AV analog palette writes visible. |
| P5-8 | `FM77AV demo` shows 4096-colour artwork. |
| P5-9 | AV sweep "renders a rich screen" count moves off 1. |
| P5-10 | FM music audible; FM-7 sweep unchanged. |
| P5-11 | An AV title that needs key-release responds. |

### 11.3 `run_tests.sh` must not change for FM-7 rows

The eight fixed tests (`boot-basic`, `boot-dos1/2/3`, `basic-print`,
`basic-keys`, `basic-shift`, plus one row per loose `.d77`) must keep their exact
command lines. Add AV rows as *additional* entries:

```sh
  "av-boot-basic|--machine 1 --bootrom 0"
  "av-boot-dos|--machine 1 --bootrom 2"
```

`vsim/sweep/sweep_one.sh` hardcodes `--bootrom 0`; parameterise it with an
environment variable so the FM-7 sweep is byte-for-byte the same invocation as
the one that produced the P4-14 numbers. If the FM-7 command line changes, the
comparison against P4-14 is worthless and you will not notice.

### 11.4 Traps that apply to this work specifically

All of `TODO.md`'s "Measurement traps" still apply. Four are especially live here:

- **Trap 9 — `vsim` must be run from `vsim/`.** Every new AV ROM is another
  `$readmemh("./roms/...")` on a relative path. From elsewhere Verilator emits a
  *warning*, the ROMs come up empty, and the run still completes with plausible
  numbers. `sweep_one.sh` already `cd`s and flags `NOROM`; anything new must too.
- **Trap 3 — `+define+` args are baked in at Verilator time.** A new
  `DEBUG_MMR=1` or `DEBUG_ALU=1` after a plain `make` relinks the old model.
  `touch ../rtl/MMR.v` first and `grep -l MMRTRACE obj_dir/*.cpp` to confirm.
- **Trap 7 — triage by `main/frame`, not by screenshot.** Healthy is 4400-5800.
  At 2 MHz instead of 1.2288 MHz the AV's healthy band will be roughly
  **1.63× higher, ~7200-9400**. Update `triage.py`'s `LOW_RATE`/`HEALTHY_LO`
  thresholds for AV rows or every working AV title will be misfiled as healthy
  when it is actually 40% slow.
- **Trap 5 — a low VRAM write count proves nothing.** With the ALU enabled the
  sub CPU writes VRAM by *reading* it. Any instrumentation that counts VRAM
  writes will under-report AV titles by design.

### 11.5 Files that must stay CRLF

From `TODO.md` "Working practices": `rtl/FLAGS.v`, `rtl/MFD.v`, `rtl/SRAM.v`,
`rtl/ROMS.v`, `rtl/CLKCTRL.v`, `files.qip`, `FM-7_MiSTer.qsf`. **This plan touches
`ROMS.v` (P5-3), `CLKCTRL.v` (P5-3), `FLAGS.v` (P5-9, the `$fd37` mask into the
ALU) and `files.qip` (P5-1).** Run `file rtl/*.v files.qip` after any scripted
edit.

And `files.qip` is **canonical over the `.qsf`** — the qsf sources it, and the
Quartus GUI re-injects a duplicate list whenever the project is opened. Delete
that when it reappears (P4-6). Every new module goes in `files.qip` *and* in
`vsim/Makefile`'s `V_SRC` list, which are two separate lists that drift silently:
P4-6 was exactly this, an FDC that could not have compiled in Quartus while
`vsim` built it happily.

---

## 12. Risks and effort

### 12.1 Block RAM — the largest hardware risk [unverified]

Current usage, from the declared array sizes (I have **not** run a Quartus fit):

| Consumer | Size |
|---|---|
| `MRAM` main RAM | 64 KB |
| `CRTRAM` VRAM (3 × 16 KB) | 48 KB |
| `ROMS` F-BASIC | 32 KB |
| `KANJI` kanji ROM | **128 KB** |
| `SMEM` sub RAM + ROMs | 14 KB |
| `FDC` (`edsk_ram` 2048×56b + sbuf) | 16 KB |
| `SRAM` shared window | 1 KB |
| `pcm` relay samples | 4 KB |
| `ROMS` M152 | 2 KB |
| **total** | **~309 KB** |

The DE10-Nano's 5CSEBA6 has 553 M10K blocks ≈ **691 KB**. Additions:

| Addition | Size |
|---|---|
| main RAM 64 KB → 192 KB | +128 KB |
| VRAM 48 KB → 96 KB | +48 KB |
| `initiate.rom` | +8 KB |
| `subsys_a` + `subsys_b` + `subsyscg` | +24 KB |
| `fbasic30` (second F-BASIC image) | +32 KB, or 0 if merged into one 64 KB instance |
| analog palette 4096 × 12b | +6 KB |
| **total** | **+214 KB → ~523 KB, ~76%** |

Tight but plausible. Mitigations, in order of preference:

1. Merge `fbasic300` + `fbasic30` into one 64 KB instance (saves 32 KB).
2. Build 128 KB of main RAM instead of 192 KB if the base AV really only has
   two pages (saves 64 KB) — needs the §5.2 question answered first.
3. Move the 128 KB kanji ROM to SDRAM. `rtl/sdram.sv` is already instantiated for
   the tape path in both tops, and the kanji interface is a latched address plus
   a byte read, which tolerates latency perfectly. Saves 128 KB and is the
   single biggest lever. **Caveat:** it would make an SDRAM module mandatory for
   Japanese text, which it is not today.

**AV40SX is off the table on block RAM**: `kanji2` (128 KB) + `dicrom` (256 KB) +
`extsub` (48 KB) + 48 KB more VRAM = +480 KB, which does not fit at all.

### 12.2 Biggest unknowns

1. **Whether F-BASIC V3.0 boots at all once MMR and the initiate ROM are in.**
   Everything else is downstream of that. If P5-3's milestone slips, the whole
   plan slips.
2. **The `initiate.rom` internal offsets** (`$1800` BASIC / `$1A00` DOS /
   `$1FFE` reset vector). CSP is the only reference that states them. Disassemble
   before writing RTL.
3. **VRAM arbitration with three masters** (§5.4). The dual-port conversion is
   the right answer but it perturbs FM-7 timing and must be its own commit.
4. **ALU timing.** No reference has measured it. Running it "as fast as
   possible" and relying on software polling `$D430` bit 4 is almost certainly
   safe, but a title that assumes a *minimum* draw time would break in a way
   that is very hard to diagnose.
5. **The main CPU clock** — 1.8 vs 2.016 MHz (§8.5) — and the **YM2203 master
   clock** (§9.2, MAME and CSP both say 1.2288 MHz, which is suspiciously low).
   Clock errors only matter for titles with timing loops, but those are exactly
   the ones that fail mysteriously.
6. **Whether `jt12`/`jt49` are Verilator-lint-clean for the `vsim` flow.** They
   carry `` `ifdef SIMULATION `` blocks, `jt12_mmr_sim.vh`, `/* synthesis
   direct_enable */` attributes and `/* verilator coverage_off */` pragmas — so
   Verilator is clearly used upstream — but nobody has built them here. The
   `vsim` Makefile already runs with `-Wno-fatal`, which helps.

**There is no prior art to lean on.** A GitHub search across repos, code and
topics finds exactly two FPGA FM-7 projects — `pcornier/FM-7_MiSTer` (this
core's upstream) and `JasonA-dev/FM-7_MiSTer` — and nothing at all for MiST,
SiDi, Analogue Pocket or standalone. `MB61VH010` appears in HDL **nowhere**;
every hit is CSP's C++ or a fork of it. MMR paging and the ALU are new RTL that
has to be written from the C++ in `refs/`.

### 12.3 What can be deferred and still ship something useful

The dependency chain is **P5-0 → P5-1 → P5-2 → P5-3**. Everything after P5-3 is
independently deferrable.

- **Minimum useful deliverable: P5-0 through P5-4.** An FM77AV that boots
  F-BASIC V3.0, runs 640x200 8-colour software, and has the correct sub monitor.
  A large fraction of the 129 AV images are 8-colour titles that only need the AV
  memory map — 30 of them already show *some* content on a machine with none of
  this. This alone should move the AV sweep substantially.
- **P5-9 (ALU) can be deferred longest** despite being the biggest. A title that
  uses the ALU will draw wrong, not hang — with `$D410` bit 7 ignored, VRAM
  writes just go through normally, which is the FM-7 behaviour those titles fall
  back to on an FM-7.
- **P5-10 (sound) is orthogonal.** Silence is not a boot failure.
- **P5-8 (4096-colour) can be deferred** if `$FD12` bit 6 is honoured as a
  no-op — the title renders in 8 colours at the wrong width rather than showing
  garbage. Ugly, but not a crash.
- **P5-11 (keyboard encoder) is last** because the AV's reset default is FM-7 key
  mode.

### 12.4 What I did not check

- I did not build or run anything. Every number here is read from source or
  computed from file sizes.
- I did not disassemble `initiate.rom`.
- I did not build `jt03`/`jt49`, or confirm the FM77AV's real YM2203 master
  clock against a hardware document (§9.2).
- I did not run a Quartus fit, so §12.1 is arithmetic, not a resource report.
- I did not check whether the base FM77AV populates two or three 64 KB RAM pages
  (§5.2).
- I did not verify the `$D430` bit 7 read sense (§6.1) or the `$D40E`/`$D40F`
  two-write toggle (§6.2) against any software.
