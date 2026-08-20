# FM77AV hardware notes

Research reference only — the first machine-family plumbing slice is now in the
core, but the AV hardware backend is still partial. The OSD and Verilator
expose a machine-family bit; the initiator/F-BASIC overlays and an `AVMEM.v`
main-memory front end are wired. The front end includes reset-seeded writable
boot RAM, MMR/TWR registers, and the 256 KB physical map. Changing family
forces a full reset, and selecting FM77AV releases the AV CPUs through their
normal reset-vector path. The AV
`$FD13` sub-monitor selector and its sub-CPU reset-on-write behavior are wired
to the secondary CPU's A/B/C ROM window. The main CPU's MMR aperture into the
three shared VRAM planes is wired, including `$D430` bit 5 selecting the
second VRAM bank. The sub-system `$D800-$DFFF` font window selects the checked-in
`subsyscg.rom` banks through `$D430`; its display and active page bits are
latched and select the raster/sub-CPU VRAM page. `$FD12` bit 6 and the
mode-dependent main-CPU VRAM transform are wired, including the `$1fff`
low-address mask and scroll offset in 320×200 mode. The raster timing and
analog 12-bit pixel compositor remain unfinished.
This file preserves the hardware research from a longer planning document
(deleted; see git history for `FM77AV_PLAN.md`).
Claims are cited file:line against the reference emulators in `refs/`; anything marked
**unverified** was not checked against a reference and may be inference. See
`docs/REFERENCE.md` for the reference emulators and `docs/IO_MAP.md` for the FM-7 I/O map.

## Machine summary

| | FM-7 | FM77AV |
|---|---|---|
| Main CPU | 68B09, E = 1.2288 MHz | 68B09. References disagree on E: MAME 2.016 MHz (`fm7.cpp:1883`, 16.128 MHz/2 into MC6809); CSP 1.798 MHz, dropping to 1.565 MHz while MMR/TWR enabled (`fm7_common.h:79-82`); 77AVEMU 1.8 MHz — "catalog says 2 MHz but measurement implies 1.8" (`mc6809.h:22`, `fm77avio.cpp`) |
| Sub CPU | 68B09, 2 MHz | unchanged (`fm7_common.h:84`) |
| Main RAM | 64 KB | 3 × 64 KB pages modelled by all three references; real base AV shipped 128 KB (**unverified**) |
| VRAM | 48 KB, 3 planes × 16 KB | 96 KB, 2 pages × 3 planes × 16 KB (CSP `fm7_display.h:22` = `0x2000*12`; 77AVEMU `fm77avdef.h:25`) |
| Video | 8-colour digital palette | adds 4096-colour analog palette and 320×200 mode |
| Sound | separate AY-3-8910 | single YM2203; its SSG half replaces the AY (§Sound) |
| Boot | 4-bank boot ROM at `$FE00` | boot **RAM** seeded from `initiate.rom` (§Boot) |
| Keyboard | cannot sense key release | encoder with make/break scan mode (§Keyboard) |

MMR is off at reset, so the AV's power-on memory map **is** the FM-7 map (physical
`$30000-$3FFFF`, identity-mapped). `$FC00-$FFFF` is never translated by MMR.

## MMR / TWR memory management

Registers (main CPU side):

| Addr | R/W | Function |
|---|---|---|
| `$FD80-$FD8F` | R/W | 16 bank registers of the selected segment; 6 bits used on base AV (physical A17:A12, 256 KB space). CSP `fm7_mainio.cpp:1528-1537` (write), `:1217` (read) |
| `$FD90` | W | segment select, `& 3` on base AV, `& 7` only on AV20/AV40 variants (`fm7_mainio.cpp:1804-1811`). 77AVEMU: "Oh!FM May 1989 pp.45 implies 8 segments... if so F-BASIC 3.3 does not boot" (`fm77avmemory.cpp:1227-1228`) — base AV has 4 |
| `$FD92` | W | TWR window offset, 256-byte units (`fm7_mainio.cpp:1814-1816`) |
| `$FD93` | R/W | b7 = MMR enable, b6 = TWR enable, b0 = boot RAM `0`=RO `1`=R/W, b5:1 unused, all reset to 0 (`fm7_mainio.cpp:1817-1826`, read `:1448`; the bit map is also tabulated for the AV series in haserin09 `difference.html`, the `FD93` mode-select row). **The read returns `$3F | mmr<<7 | twr<<6` with bit 0 then set from the latch** — 77AVEMU clears it when the boot area is ROM (`fm77avio.cpp:959-971` over `fm77avmemory.cpp:1304-1310`) |
| `$FD94` | W | AV40-family only: b7 = extended MMR (`fm7_mainio.cpp:1828-1830`) |
| `$FD10` | W | b1 = 1 disables the initiator ROM overlay (`fm7_mainio.cpp:1603-1605`; 77AVEMU `fm77avmemory.cpp:325` `state.avBootROM=(0==(data&2))`). On at reset for AV-family machines only. While it is on, writes to `$6000-$7FFF` are discarded (`fm77avmemory.cpp:917`) and the reset vector reads `$6000`; with it off, `$6000-$7FFF` is ordinary RAM and the vector comes from boot RAM |

Translation (77AVEMU `fm77avmemory.h:337-351`; CSP `mainmem_readseq.cpp:32-70`):

- TWR, checked first: CPU `$7C00-$7FFF` → `(TWR_offset*256 + addr[9:0]) & $FFFF` in RAM page 0.
- MMR: for `addr < $FC00` only, `phys = {bank[seg][addr[15:12]], addr[11:0]}`.
- `$FC00-$FFFF` is **never** translated — 77AVEMU cites the FM77AV40 Hardware Manual
  p.146 (`fm77avmemory.h:339`). All FM-7 `$FCxx`/`$FDxx` I/O decode is unchanged.

Physical 256 KB map (77AVEMU `fm77avmemory.h:61-119`; banks = MMR register values):

| Physical | Banks | Contents |
|---|---|---|
| `$00000-$0FFFF` | `$00-$0F` | RAM page 0 |
| `$10000-$1FFFF` | `$10-$1F` | the whole sub system: VRAM `$10000-$1BFFF`, sub RAM `$1C000`, shared RAM `$1D380`, sub I/O `$1D400`, font ROM `$1D800`, monitor ROM `$1E000-$1FFFF` — main CPU can reach VRAM/sub I/O through MMR |
| `$20000-$2FFFF` | `$20-$2F` | RAM page 1 |
| `$30000-$3FFFF` | `$30-$3F` | the FM-7 machine: RAM, initiator ROM `$36000`, F-BASIC `$38000`, shared/I-O/boot `$3FC80-$3FFFF` |

Quirks:

- Reading the MMR register area *through* bank `$3F` returns `$FF` — CSP
  `read_segment_3f`, `mainmem_mmr.cpp:119-127` (blocks `$xD80-$xD97`).
- CSP gates main-CPU access to the `$1xxxx` sub aperture on the sub CPU being halted;
  otherwise reads return `$FF` (`mainmem_readseq.cpp`, `read_direct_access`). 77AVEMU
  is the same rule stated the other way round: a main-CPU access to `$10000-$1FFFF`
  is discarded while the sub CPU is *running* — reads return `$FF`
  (`fm77avmemory.cpp:737-742`), stores are dropped (`:805-810`). **The rule covers the
  whole `$1xxxx` range**, not just the I/O page: VRAM, sub RAM, shared RAM, font and
  monitor ROM alike. This core gates the I/O page and the VRAM aperture; sub RAM and
  the monitor ROM are still reachable through MMR with the sub running (see `TODO.md`).
- Titles observe this gate scrupulously, so it blocks almost nothing in practice.
  Shounen Mike's sub CPU is halted for **0.1%** of cycles and every one of its 4608
  main-CPU VRAM writes falls inside that 0.1%; Valis Disk 1's 27874 writes and 34020
  reads are likewise all inside its halts. Measured with `DEBUG_AVDRAW=1`, which prints
  rejected accesses next to accepted ones — necessary because a gate that blocks nothing
  and a gate absent from the build look identical (REFERENCE.md trap 3).
- **The sub I/O page at `$1D400-$1D4FF` is not decoration.** The 2019 AV demo halts
  the sub CPU and then drives `$D430` and `$D410` from the main CPU: at the point it
  fills the second bit-plane pair it writes `$1D430 = $64` (display page 1, access
  page 1) and later `$1D410 = $80` to arm the drawing ALU. A core that maps only the
  `$10000-$1BFFF` VRAM part of the aperture loses the page select, so every gradient
  byte lands on the page-0 planes and the screen is vertical colour bars instead of
  a 4096-colour ramp. Five such writes in the whole demo, all with the sub halted.
- `$FD90`/`$FD92` have no read handler (write-only); reads fall through.

## Boot / initiator ROM

- At reset the 8 KB initiator ROM overlays `$6000-$7FFF`, and the reset vector
  `$FFFE-$FFFF` reads `initiate.rom[$1FFE-$1FFF]` (CSP `mainmem_readseq.cpp:127-139`).
  Writing `$FD10` b1 = 1 removes the overlay, leaving RAM.
- `$FE00-$FFDF` is **RAM**, seeded with 480 bytes from inside `initiate.rom`:
  offset `$1800` for BASIC mode, `$1A00` for DOS mode, then the reset vector in that
  RAM is forced to `$FE00` (CSP `mainmem_utils.cpp:293-300`). The AV has no separate
  boot ROM images — MAME's `ROM_START( fm77av )` has no boot region. These internal
  offsets are modelled only by CSP; confirm by disassembling `initiate.rom` before use.
- `$FD93` b0 is a **write enable** on that boot RAM, not a ROM/RAM selector. CaptainYS,
  verified on real hardware: bytes changed in `$FE00-$FFE0` persist after switching back;
  the original loader does not reappear (77AVEMU `fm77avmemory.h:178-183`).
- `$FD0B` read, b0: 0 = BASIC, 1 = DOS boot mode (CSP `fm7_mainio.cpp:1263-1264`;
  MAME `fm7.cpp:784-797` agrees).
- **The initiator's `$6000` entry is a re-runnable cold start, and titles call it.**
  It programs the YM2203 (`$6009` onward), fills the analog palette with the reset ramp,
  sets MMR banks `$30-$3F`, re-seeds `$FE00-$FFDF` from `initiate.rom[$1800/$1A00]`,
  copies `initiate.rom[$1C00]` to `$5000-$527F`, then runs a stub in `$FC00-$FC79` that
  clears `$FD93`, writes `$FD10 = $02` and jumps to `$5000`. Ys reaches it through
  `JSR [$024b]` after loading its next stage — so a core that never lets `$FD10` take the
  overlay away runs the ROM instead of the loaded code and silently reboots itself.
  Nothing in this path resets the sub CPU.

## Display

### Pages and `$D430` (sub CPU side)

| bit | write | read (CSP `display.cpp:812-847`) |
|---|---|---|
| 7 | NMI mask (1 = masked) | 1 during active display (`!hblank`) — 77AVEMU has the opposite sense; CSP+MAME outvote it (**unverified** against software) |

| 6 | display page | 1 |
| 5 | CPU access page | 1 |
| 4 | — | 1 = ALU idle |
| 2 | fine-offset enable | VSYNC |
| 1:0 | CG font bank (§Sub-system) | b0 = power-on-reset flag |

**Bit 7 is load-bearing, and the reason is on the sub side.** The sub monitor's 20 ms
NMI handler at `$FEBF` opens with `LDA <$0a` — a read of `$D40A`, which CLEARS the
sub-busy flag. Any title that hands the sub a block-transfer stub therefore masks the NMI
first, because an NMI landing mid-transfer tells the main CPU "sub idle" while the sub is
still copying. Ys (FM77AV) does exactly this: its shared-RAM downloader sets `$D430 = $85`
before its first byte, and with the mask ignored the main CPU ran an extra mailbox
iteration each time an NMI landed, overwriting three of its 294 8-byte blocks. 77AVEMU
additionally suppresses the NMI while the sub CPU is halted, with the note "Greater than
40ms halt will double-fire the NMI, which is not good" (`fm77av.h:340`); this core does
not, and no title in hand needs it.

Scroll: one offset register pair per page, selected by the access page; the display page
picks which one the raster uses. `$D430` b2 = 0 masks the offset to `$FFE0` (32-byte
steps, the FM-7 behaviour), = 1 to byte granularity (77AVEMU `fm77avcrtc.cpp:277-281`).

### Analog palette (main CPU side)

| Addr | Function (CSP `display.cpp:873-940`) |
|---|---|
| `$FD30` | index b11:8 (`data & $0F`) |
| `$FD31` | index b7:0 |
| `$FD32` | Blue, 4 bits |
| `$FD33` | Red, 4 bits |
| `$FD34` | Green, 4 bits |

4096 entries × 12 bits. The 12-bit pixel code is `{G[3:0], R[3:0], B[3:0]}` — CSP's
reset ramp sets `r[i] = i & $0F0`, `g[i] = (i & $F00) >> 4`, `b[i] = (i & $00F) << 4`
(`display.cpp:226-228`), i.e. reset default is an identity ramp, not black (77AVEMU
zeroes it instead; CSP is primary). Reads of `$FD30-$FD34` are unimplemented in all
three references. CSP display's non-zero components OR in `$0F` when expanding 4→8 bits.

### 320×200 4096-colour mode

`$FD12` b6 (main side): 0 = 640×200 8-colour, 1 = 320×200 4096-colour (CSP
`fm7_mainio.cpp:1607-1611`; readback returns the latched register, reset value `$BC`,
`fm7_mainio.cpp:189`). This reorganises VRAM into **12 sub-planes of 8 KB**, six per
page — the two pages stop being double buffers and become the low bits of each gun
(CSP `vram.cpp:759-771`):

```
page 0 base: B @ +$0000,+$2000   R @ +$4000,+$6000   G @ +$8000,+$A000
page 1 base: B @ +$0000,+$2000   R @ +$4000,+$6000   G @ +$8000,+$A000  (low bit pair)
```

Plane addressing changes with it: `page_mask = $1FFF`, `pagemod_mask = $E000` in
320-mode vs `$3FFF`/`$C000` in 640-mode (CSP `display.cpp:378-384`). 400-line and
260k-colour modes are AV40-family only.

## MB61VH010 drawing ALU

A read-modify-write engine on the VRAM path operating on all three planes at
one byte offset simultaneously. While `$D410` b7 is set, **any** VRAM access triggers
it and the CPU's data byte is discarded (CSP `display.cpp:3174-3181`).

Reads and writes both trigger, and **the read is the primary form**. 77AVEMU takes the
hardware-draw path on every read of `MEMTYPE_SUBSYS_VRAM` (`fm77avmemory.cpp:746-750` →
`FM77AVCRTC::VRAMDummyRead`), and treats the write form as the exception: "Hardware
drawing is supposed to be dummy-READ a VRAM byte. However, Pro Baseball Fan (Telenet)
is dummy-writing to a VRAM byte to use hardware drawing. So, apparently reading and
writing both work" (`fm77avmemory.cpp:822-828`).

This applies to **either CPU**, on whichever path reaches VRAM — the reference keys the
trigger on the address, not on who is accessing. A title that halts the sub CPU and
blits from the main side through the MMR aperture needs the trigger there too. Measured
on Woody Poco: 53311 aperture reads and **zero** aperture writes over 300 frames, so a
core wired for the write form alone performs no drawing at all for it and leaves VRAM
at 8 non-zero bytes.

| Addr | R/W | Function (CSP `mb61vh010.h:65-79`) |
|---|---|---|
| `$D410` | R/W | command: b7 enable, b6 compare enable, b5 compare sense, b2:0 op |
| `$D411` | R/W | logical colour, 3 bits (b0=B, b1=R, b2=G) |
| `$D412` | R/W | write mask; 1 = preserve that pixel |
| `$D413` | R | compare result, one bit per pixel, MSB = leftmost |
| `$D413-$D41A` | W | compare colours 0-7; b2:0 = colour, b7 = slot disabled |
| `$D41B` | R/W | plane disable, 3 bits (1 = disabled) |
| `$D41C/D/E` | W | tile pattern B / R / G |
| `$D41F` | W | tile "L", 4th plane — no reference implements it |
| `$D420/$D421` | W | line address offset hi/lo |
| `$D422/$D423` | W | line stipple pattern, 16 bits (rotates during the draw) |
| `$D424-$D42B` | W | X0/Y0/X1/Y1 hi/lo; **writing `$D42B` triggers the line draw** |

Ops 0-7 (dispatch CSP `mb61vh010.cpp:349-373`): PSET, BLANK, OR, AND, XOR, NOT,
TILEPAINT, COMPARE. 77AVEMU treats op 1 as NOT rather than BLANK — "FM77AV Demo uses 1.
My guess is it is for erasing a line" (`fm77avcrtc.cpp:442-444`); CSP has a distinct
BLANK (`src & mask`). Compare (b6) builds a per-pixel hit mask against the 8 slots which
then gates the write; b5 inverts the sense. The `$FD37` multi-page access mask also
masks the ALU (77AVEMU verified this on real hardware, `fm77avcrtc.cpp:410`).

Timing: no reference has measured it. CSP models busy only for LINE, at 16 bytes/µs
(`mb61vh010.cpp:632-638`); software polls `$D430` b4 for completion.

The two triggers are not equally important. The 2019 AV demo writes `$D42B` **zero**
times in its whole run — it uses only the access-intercept path, 622 register writes
of which 287 are `$D410` toggling between `$80` (enable, PSET) and `$00`. So a core
that implements the Bresenham line drawer but not the byte read-modify-write has
implemented the half no software in hand exercises. The two paths also differ in the
mask: the access path writes the eight pixels selected by `~$D412`, while the line
path (`PutDot`) ignores `$D412` entirely and writes the single pixel it is on, gated
by the rotating `$D422/$D423` stipple.

## Sub-system changes

- Sub monitor bank, **`$FD13` main side** (write `fm7_mainio.cpp:1612-1615`; bank table
  CSP `display.cpp:2648-2672`): `$FD13[1:0]` = 0 → `subsys_c` (its first `$800` is the
  font at `$D800`, rest is the monitor), 1 → `subsys_a`, 2 → `subsys_b`, 3 → `subsyscg`.
- **Writing `$FD13` resets the sub CPU, even if the value is unchanged** — "Confirmed
  on actual FM77AV... POKE &HFD13,0 from F-BASIC will reset sub-CPU" (77AVEMU
  `fm77avio.cpp:193-201`). **The reset also SETS the sub-system BUSY flag**
  (`state.subSysBusy=true; // Busy on reset`, `fm77avio.cpp:201`), and so does a
  machine reset (`fm77av.cpp:624`). CSP does not model the `$FD13` reset at all, so
  77AVEMU is the sole authority here. Software depends on it: the original Fujitsu
  FM77AV demo disk writes `$FD13` and then polls `$FD05` for the restart to finish,
  and a core that leaves BUSY clear reports "already idle", halts and releases a sub
  CPU still in reset, and hangs on `$FD05` forever.
- `subsyscg.rom` is four 2 KB font banks, not a monitor: bank = `$D430[1:0]`
  (0 katakana, 1 hiragana, 2 ROM1, 3 ROM2 — 77AVEMU `fm77avmemory.h:22,41`,
  `fm77avmemory.cpp:49,1047-1060`).
- `$D500-$D7FF` becomes 768 bytes of hidden RAM (CSP `fm7_display.h:264`,
  `display.cpp:2628,3169`); on the FM-7 it is part of the MMIO region. This core
  no longer decodes it as I/O, but **does not yet implement the RAM** — see
  `TODO.md`.
- Sub I/O aliases every **64** bytes on base AV (`& $3F`) vs 16 on the FM-7 (`& $0F`)
  — CSP `display.cpp:2753-2759`. The ALU block needs address bits 5:4 decoded, and
  `$D500-$D7FF` must not decode as I/O at all. **Both are side-effect decodes, not
  just read multiplexing**: every Y-output of `SDECODE`'s `m87`/`m98` does something
  when merely addressed — `SCRTSWn` (the CRT on/off latch at `$D408`: read = on,
  write = off), `ATTENTn` (raises the main CPU's attention FIRQ), `KDATAn`,
  `KACKNGn`, `SIRQCLRn`, `BUZZERn`, `SBUSYSETn`. With bits 9:8 and 5:4 undecoded,
  an ALU write to `$D428` switched the display off and a read of hidden RAM at
  `$D7F4` raised a spurious FIRQ. Fixed in `c2fc867`; the two faults had been
  partially cancelling, so fixing either alone looks like it made things worse.
- Sub-side kanji ports `$D406/$D407`: CSP gates them to AV40/AV20/FM-77 variants —
  **not** base AV (`display.cpp:2772-2784`). The main-side window `$FD20-$FD23` is
  unchanged from the FM-7.

## Sound

Implemented as one `jt03` (jotego/jt12) serving both machines: `rtl/SOUND.v` presents the
`$FD0D`/`$FD0E` window with the command masked to two bits and, on the AV only, the
`$FD15`/`$FD16` window with the full four. `make sound-test` covers both, including the
status read Ys spins on. The joysticks moved onto the chip's real I/O ports; the bus-snoop
that stood in for them is gone. **jt12/jt49 are GPLv3-or-later, so the combined work now
ships as GPLv3** — see `rtl/jt12/LICENSE-jt12`.

Two things about it are **unverified and need an ear, not another derivation**: the FM
clock, and whether the SSG lands on the right octave. jt03's `cen` is fed the same 1.2 MHz
enable the retired AY had, so the FM-7's pitch is bit-identical to what shipped before —
but the AV's initiator selects registers `$2D` and `$2E`, which halves the YM2203's SSG
prescaler, so on the AV the SSG runs an octave above the FM-7. That cannot be right for
both machines, and the two references do not settle it: CSP (`fm7.cpp:831-837`) and MAME
(`fm7.cpp:1893, 1996`) both give the FM-7's AY and the AV's YM2203 the *same* 4.9152/4 =
1.2288 MHz, which the prescaler difference contradicts.

The AV has **one YM2203 and no separate AY**: `$FD0D/$FD0E` drive the SSG half of the
same chip that `$FD15/$FD16` drive as FM (CSP `sound.cpp:46-50` sets `opn_psg_77av`;
routing `sound.cpp:107-133`; 77AVEMU: "FM77AV and later writes to the PSG-part of
YM2203C", `fm77avsound.cpp:398`). `$FD0D` commands are masked to 2 bits — the
AY-compatible subset (`sound.cpp:126`) — while `$FD15` takes the 4-bit set: 0 inactive,
1 read data, 2 write data, 3 latch address, 4 read status, 9 read joystick port
(`sound.cpp:283-291,324-346`). `$FD17` b3 = OPN IRQ flag. Clock per MAME:
4.9152 MHz / 4 = 1.2288 MHz (`fm7.cpp:1996`) — unusually low for a YM2203; real
hardware value **unverified**. Joysticks hang off SSG port B as on the FM-7; writes to
SSG register 7 are forced to `(data & $3F) | $80` because the top bits control joystick
reading — observed on real FM77AV (77AVEMU `fm77avsound.cpp:272-280`).

## Keyboard encoder (`$D431/$D432`, sub side)

The AV adds a command-FIFO keyboard encoder (CSP `keyboard.cpp`, ~660 lines inside
`_FM77AV_VARIANTS` guards; read handler at `keyboard.cpp:674`). Commands: `$00`/`$01`
set/get scancode mode, `$02`/`$03` LEDs, `$04`/`$05` repeat, `$80` RTC, `$81-$84`
stubs. `$D432` b7 = latch ready, b0 = ACK. The mode that matters for software is scan
mode with make/break codes — the FM-7 cannot sense key release at all (77AVEMU
`readme.md`). Reset default is FM-7 mode (MAME `fm7.cpp:1829`), so software must opt in.

## ROM set

`refs/fm77av.zip` matches MAME's `ROM_START( fm77av )` (`refs/mame/src/mame/fujitsu/fm7.cpp:2211-2233`) exactly; there is no `NO_DUMP`:

| file | bytes | CRC32 | notes |
|---|---|---|---|
| `initiate.rom` | 8192 | `785cb06c` | contains the two 480-byte boot loaders at `$1800`/`$1A00` |
| `fbasic30.rom` | 31744 | `a96d19b6` | BAD_DUMP ("last 1K inaccessible"); F-BASIC V3.0. Not the FM-7's `fbasic300.rom` (`87c98494`) |
| `subsys_c.rom` | 10240 | `24cec93f` | BAD_DUMP; same image the FM-7 already uses (font + monitor) |
| `subsys_a.rom` | 8192 | `e8014fbb` | |
| `subsys_b.rom` | 8192 | `9be69fac` | |
| `subsyscg.rom` | 8192 | `e9f16c42` | four 2 KB font banks |
| `kanji.rom` | 131072 | `62402ac9` | identical to the FM-7's kanji ROM |

AV40SX extras in `refs/fm7740sx.zip` (verified against `fm7.cpp:2253-2258`):
`kanji2.rom` 131072/`38644251`, `dicrom.rom` 262144/`b142acbc`, `extsub.rom`
49152/`0f7fcce3`. Note neither MAME nor 77AVEMU actually implements the second kanji
bank's I/O; only CSP does (`kanjirom.cpp`).

## Reference sources

- **CSP (primary authority)**: `refs/common-src-project/src/vm/fm7/`. AV paths live
  inside `#if defined(_FM77AV_VARIANTS)` guards — that macro is defined in `fm7.h`
  (lines 119-183) for every AV-family machine, with `_FM77AV40`, `_FM77AV40EX/SX`,
  `_FM77AV20*` and `HAS_MMR` gating later-machine features. **Code inside those guards
  is not the plain FM-7 path.** Key files: `mainmem_readseq.cpp`/`mainmem_mmr.cpp`
  (MMR/TWR), `mainmem_utils.cpp` (boot RAM), `display.cpp`/`vram.cpp` (video, `$D4xx`),
  `mb61vh010.cpp/.h` (ALU), `sound.cpp` (YM2203), `keyboard.cpp`, `fm7_mainio.cpp`
  (`$FDxx`), `fm7_common.h` (clocks).
- **77AVEMU / Mutsu (tiebreaker)**: `refs/77AVEMU/src/` — `memory/fm77avmemory.cpp/.h`,
  `fm77av/crtc/fm77avcrtc.cpp/.h`, `fm77av/fm77avio.cpp`, `fm77av/sound/fm77avsound.cpp`,
  `fm77av/fm77avdef.h`. Carries several real-hardware observations quoted above.
- **MAME (I/O map only)**: `refs/mame/src/mame/fujitsu/fm7.cpp`, `fm7_v.cpp`. Known
  deviations: no line-stipple in the ALU, no sub-CPU reset on unchanged `$FD13`.
- **Retro PC Gallery (はせりん)**: `refs/haserin09/`, a mirror of
  <https://haserin09.la.coocan.jp/>. Documentation rather than code, and the only
  source here that is *per-model*: `difference.html` (番外編7) tabulates the FM-8 /
  FM-7 / FM-77 / FM77AV differences register by register, `fm7rom.html` is a ROM
  inventory, `os9_mmu.html` compares the 6809 MMUs, `shohyo.html` is an errata list for
  the Fujitsu manuals. Pages are Shift_JIS; grep `refs/haserin09/utf8/*.txt`.
- **sedoc (Curt Sampson)**: `refs/sedoc/8bit/fm7/`. English notes citing the Fujitsu
  system manuals by page — `ml.md` gives `$FD04` as b0 ATTENTION / b1 BREAK / **b7:2
  unused** (SS:1-8), `sub.md` the main↔sub halt handshake. It cites haserin09 as its
  own main source, so the two agree by construction where they overlap.

## Compatibility notes

- "Practically more than 99.9% of FM-7 series software runs on FM77AV" — CaptainYS,
  `refs/77AVEMU/readme.md:24`. The reverse is not true: AV software needs MMR, the
  boot RAM, and often the ALU, analog palette and 320-mode.
- AV titles written around make/break scancodes require the AV keyboard encoder; the
  FM-7 keyboard path cannot express key release.
- The bubble cassette is an **FM-8** peripheral, not an AV one: CSP builds
  `fm_bubblecasette.cpp` only alongside `fm8_mainio.cpp` (`CMakeLists.txt:26`), and its
  register block sits at `$FD10-$FD17` (**unverified**) — addresses the AV assigns to
  the initiator-ROM control and the YM2203.
