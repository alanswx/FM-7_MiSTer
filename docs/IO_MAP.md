# FM-7 `$fdxx` I/O register map

Factual reference for the main-CPU I/O page as established by this project,
verified against reference emulators and, where noted, by direct measurement in
`vsim` or from F-BASIC. References:

- **CSP** — Common Source Project, `refs/common-src-project/src/vm/fm7/`.
  The project's primary authority for FM-7 behaviour.
- **MAME** — `fm7.cpp` / `fm7_v.cpp` / `fm7.h`. Useful, but its FM-7 driver is
  unreliable; two registers below are cases where following MAME was a bug.
- **77AVEMU** — `refs/77AVEMU/`, third opinion where the first two disagree.

Conventions: interrupt-flag bits are **active low** (0 = pending) unless said
otherwise. Any `$fdxx` address with no read decode falls through to `core.v`'s
`~IOSn ? 8'hff` default and reads `$ff`, which matches MAME mapping unhandled
ports to `unknown_r`.

| Address | Function |
|---|---|
| [`$fd00`](#fd00) | R: keyboard bit 8 + FM-8 switch. W: tape/printer control |
| [`$fd01`](#fd01) | R: keyboard scancode (low 8). W: printer data |
| [`$fd02`](#fd02) | R: cassette input / printer busy. W: IRQ enable/routing |
| [`$fd03`](#fd03) | R: IRQ cause (read-acknowledges). W: beeper |
| [`$fd04`](#fd04) | R: FIRQ cause — attention, break |
| [`$fd05`](#fd05) | R/W: sub-CPU interface (halt / cancel / BUSY) |
| [`$fd06-$fd07`](#fd06-fd07) | RS-232C (8251) — stub, reads `$ff` |
| [`$fd0d-$fd0e`](#fd0d-fd0e) | PSG (AY-3-8910/YM2149) control and data; joysticks |
| [`$fd0f`](#fd0f) | ROM/RAM switch for `$8000-$fbff` |
| [`$fd18-$fd1b`](#fd18-fd1b) | FDC — MB8877 (WD1793-compatible) core registers |
| [`$fd1c-$fd1f`](#fd1c-fd1f) | FDC — side, drive/motor, mode, DRQ/INTRQ |
| [`$fd20-$fd23`](#fd20-fd23) | Kanji ROM window |
| [`$fd37`](#fd37) | Multi-page register (VRAM access / display masks) |
| [`$fd38-$fd3f`](#fd38-fd3f) | Digital palette |
| [`$ffe0-$ffff`](#ffe0-ffff) | Memory top: RAM, boot ROM, reset vector |

## $fd00

**Read** (`KEYBOARD.v`): scancode bit 8 and the FM-8 compatibility switch.

| bit | meaning |
|---|---|
| 7 | keyboard scancode bit 8 (9th bit) |
| 6-1 | **read 1** (`{P0, 6'b111111, fm8_switch}`) — superseded claim: "read 0 in this core", which was never true of the RTL |
| 0 | FM-8 compatibility switch — the boot ROM checks it to pick the FM-8 or FM-7 tape routine (`CLKCTRL.v`) |

The sub-CPU counterpart `$d400` is the same register and must read the same
way. It did not: it returned `{P0, 7'd0}`, following MAME
(`fujitsu/fm7.cpp:509`, `(m_current_scancode >> 1) & 0x80`) where CSP — the
primary authority for the FM-7 — returns `0xff`/`0x7f`
(`fm7/display.cpp:2168`), i.e. every other bit set. The two halves of one
register disagreed inside this core, and the sub half was the wrong one.

**Why the padding bits are load-bearing.** The FM-7 aliases the sub I/O page
every 16 bytes (CSP `(addr - 0xd400) & 0x000f`; the AV narrows it to 64,
`& 0x003f` — `SDECODE.v`'s `subio_alias_block`). So `$D430` reads `$D400` on an
FM-7, and an FM77AV-aware title that polls the ALU-busy bit with
`LDA $D430 / ANDA #$10 / BEQ` falls straight through on real hardware because
the aliased read returns ones. With zeros it spins for ever — which is exactly
how Death Force hung: the sub never reached `TST $d40a`, BUSY stayed set, and
the main CPU polled `$FD05` 1,094,760 times against the reference's 131,773.

**Write** (`PERIPHERAL.v`, latch `m10`): bit 0 = tape output, bit 1 = tape
motor relay, bit 6 = printer strobe (sets the busy latch read back on `$fd02`
bit 0). Other bits unverified.

## $fd01

**Read**: keyboard scancode, low 8 bits. Reading clears the keyboard IRQ flag;
so does the sub CPU reading `$d401` — either read acknowledges (MAME
`fm7.cpp:226`, matched by `KEYBOARD.v`'s `m132` clear term).

**Write**: printer data latch (`PERIPHERAL.v` `m2`) — latched but not wired
onward; the printer output path is a stub.

## $fd02

**Write** — interrupt enable/routing, bits 2:0 latched in `KEYBOARD.v` (`m77`).
A **set bit enables** the source. MAME names its variable `irq_mask` but treats
set-as-enable (`fm7.cpp:1098` `if(m_irq_mask & IRQ_FLAG_TIMER)
main_irq_set_flag(...)`); CSP agrees (`fm7_mainio.cpp:482` `if((val & 0x04) !=
0) irqmask_timer = false;`).

| bit | source | semantics |
|---|---|---|
| 0 | keyboard | **routing**, not a plain mask: set = keyboard IRQ to the main CPU (`KEYINn`), clear = keyboard FIRQ to the sub CPU (`KSTROBEn`). The two are mutually exclusive (CSP `display.cpp:2134`) |
| 1 | printer | set = enabled |
| 2 | timer | set = enabled |
| 6 | 8251 RXRDY | observed written (`$40`) by several titles; RS-232C is a stub, so it has no effect here |

Reset state: `$00`, everything masked, keyboard routed to the sub — matches CSP
resetting every `irqmask_*` to true. Note this core decodes the register as a
routing register per the schematic where MAME models a plain mask byte, so MAME
is not a bit-level reference for bit 0; use CSP.

**Read** (`PERIPHERAL.v`): bit 7 = cassette input, **forced high while the tape
motor is off** (MAME: "cassette input is high when the motor is off" — the read
head sits behind the relay); bit 0 = printer busy. Bits 6-1 read 1 here (MAME
forces bits 6-4 high, `ret |= 0x70`).

## $fd03

**Read** — main-CPU IRQ cause register, all bits **active low** (0 = pending).
Bit map per MAME `fm7.h:69` (`IRQ_FLAG_KEY 0x01, PRINTER 0x02, TIMER 0x04,
OTHER 0x08`); CSP agrees, clearing a bit when its source pends
(`fm7_mainio.cpp:1141` `irqstat_reg0 &= ~0x08`).

| bit | source |
|---|---|
| 0 | keyboard (cleared by the scancode read, not by reading `$fd03`) |
| 1 | printer |
| 2 | timer (the 2 ms tick) |
| 3 | external |
| 7-4 | read 1 |

Reading **acknowledges** the timer and printer flags (CSP `irqstat_reg0 |=
0x06`) — but the value must be captured first and cleared after (CSP
`fm7_mainio.cpp`: `val = irqstat_reg0 | 0xf0;` then clear). In this core one
6809 read produces **two** decode strobes (a Q-phase and an E-phase pulse; the
CPU latches at the end of the E-phase one), so the acknowledge fires only at
the close of the E-phase strobe (`CLKCTRL.v`).

**Write** — beeper command (`TIMER.v`): bit 7 = continuous beep, bit 6 =
single beep (auto-stops after ~380 ms), bit 0 = speaker gate. Continuous has
priority.

## $fd04

**Read** — main-CPU FIRQ cause, active low. No write decode.

| bit | source |
|---|---|
| 0 | sub-CPU **attention**: set pending when the sub *reads* `$d404`; cleared when the main reads `$fd04` (MAME `fm7_v.cpp:77` `attn_irq_r`; CSP `fm7_mainio.cpp:661` `get_fd04`; 77AVEMU `MAIN_FIRQ_SOURCE_ATTENTION=0x01`) |
| 1 | **break key**, live key state — reading `$fd04` deliberately does *not* clear it (77AVEMU `fm77avio.cpp:668` "Probably break-key FIRQ not"; MAME `fm7.cpp:1183-1189`). Break delivers no scancode |
| 2 | sub BUSY — **this core only; the references disagree**: MAME leaves bit 2 set, CSP ORs in `0x7c` and reports sub-busy at bit 7, 77AVEMU reads bits 2-7 all 1. Two of three also contradict CSP's bit 7. This core keeps its schematic-derived value; nothing measured reads the bit |
| 7-3 | read 1 (bit 2 excepted, above) |

The attention clear, like `$fd03`'s, must land on the close of the E-phase
strobe of the read (`TIMER.v`), and a set arriving on the acknowledge cycle
wins over the clear.

## $fd05

The sub-CPU halt / BUSY handshake.

**Write** (`PERIPHERAL.v` `m9`): bit 7 = sub halt request, bit 6 = cancel
(attention IRQ to the sub — its release asserts `SUBIRQn`), bit 0 = Z80 card
select (`Z80W`/`GHn`). CSP `fm7_mainio.cpp:744`: `sub_halt = val & 0x80`,
`sub_cancel = val & 0x40`.

**Read**: bit 7 = sub system **unavailable** = `BUSY | halted` — both halves,
not BUSY alone (MAME `fm7_v.cpp` `subintf_r`: `if(sub_busy != 0 || sub_halt !=
0) ret |= 0x80;`). Bits 6-1 read 1. Bit 0 = external-card detect (`EXTDETn`,
tied 0 in `core.v` — semantics unverified).

**BUSY protocol**, per MAME `subintf_w`/`sub_busyflag_r` and CSP
`display.cpp:1879` (`SIG_FM7_SUB_HALT: if(flag) sub_busy = true;`):
**requesting a halt also sets BUSY**, and BUSY stays set after the halt is
released; it clears only when the sub returns to its ROM idle loop and reads
`$d40a` (the sub sets it back by writing `$d40a`). The main's loop is:
poll bit 7 clear → write `$80` → write the command block to `$fc80+` → write
`$00` → sub wakes, consumes, reads `$d40a` → bit 7 clears.

## $fd06-$fd07

RS-232C, nominally an Intel 8251A. **Stub**: `RS232.v` returns `$ff` for both.
MAME maps `$fd06-$fd0c` to `unknown_r` (also `$ff`), so this is correct for
software that only probes. The TXRDY/RXRDY/SYNDET interrupt sources would come
from this chip; unimplemented.

## $fd0d-$fd0e

PSG (YM2149/AY-3-8910). **`$fd0d` write**: bits 1:0 = `{BDIR, BC1}` bus
control (`SOUND.v`). `$fd0d` has no read decode (reads `$ff`). **`$fd0e`**:
PSG data bus, write and read.

**Joysticks** live on the PSG I/O ports (CSP `fm7.cpp:626`
`set_context_port_b(joystick, ...)`; protocol from CSP `joystick.cpp`):

- write PSG **register 15** (port B) to select — high nibble `$2` = stick 0,
  `$5` = stick 1, anything else none;
- read PSG **register 14** (port A), **active low**:
  `{1, 1, ~buttonB, ~buttonA, ~right, ~left, ~down, ~up}`, `$ff` when nothing
  is selected.

**Write order: the byte goes to `$fd0e` first, and the following `$fd0d`
command consumes it.** `$fd0e` is a latch; `$fd0d` is what acts. CSP models
exactly this — `set_psg()` stores the byte, `set_opn_cmd()` (`sound.cpp:308-348`)
runs on the `$FD0D` write and uses the stored `opn_data`. Thexder's own bus
traffic is the same, 1024 times over:

```
$fd0e <- 08     put 8 on the data latch
$fd0d <- 03     command 3: latch it as the register address (channel A amplitude)
$fd0d <- 00
$fd0e <- 1f     data
$fd0d <- 02     command 2: write $1f to register 8
```

(Superseded claim: this section used to give the poke sequence in the opposite
order, `poke64781,3:poke64782,15:...`, described as verified from F-BASIC against
a real stick. `SOUND.v` was backwards in the same way at the time, so the check
only ever proved the two agreed with each other. The corrected sequence, stick 1
held up+A, `$fd0d` = 64781 and `$fd0e` = 64782:)

```
poke64782,15:poke64781,3:poke64781,0:poke64782,32:poke64781,2:poke64781,0:poke64782,14:poke64781,3:poke64781,1:?peek(64782)
 238
```

`238` = `$ee`: bit 0 (up) and bit 4 (button A) low. Note F-BASIC 3.0's
`STICK()` never touches these ports and always returns 0 — it cannot be used
to test them.

## $fd0f

ROM/RAM switch for `$8000-$fbff`: **read → F-BASIC ROM mapped, write → RAM
mapped** (CSP `fm7_mainio.cpp:771` `write_fd0f`; `ROMS.v`). The data written
is irrelevant; the access itself is the switch. Writes to `$8000-$fbff` land
in RAM in both modes (the underlying RAM is a full 64 K).

## $fd18-$fd1b

FDC core registers of the MB8877, which is WD1793-compatible with a normal,
non-inverted bus (MAME `refs/mame/src/devices/machine/wd_fdc.h:31`), running
permanently in MFM (MAME never calls `dden_w()` for the FM-7).

| addr | read | write |
|---|---|---|
| `$fd18` | status | command |
| `$fd19` | track | track |
| `$fd1a` | sector | sector |
| `$fd1b` | data | data |

A real WD179x's SEEK steps until head position and track register agree
(MAME `wd_fdc.cpp:412`, stepping at `:439`), so after any seek the track
register matches the head.

## $fd1c-$fd1f

FM-7 board registers around the FDC (MAME `fm7.cpp` `fdc_r`/`fdc_w` cases 4-7,
implemented in `FDC.v`).

| addr | function | read value |
|---|---|---|
| `$fd1c` | side select (write bit 0) | `side \| $fe` |
| `$fd1d` | drive/motor (write: bits 1:0 drive, bit 7 motor) | `$3c \| drive \| (motor ? $80 : 0)` |
| `$fd1e` | mode — writes only matter on FM77AV+ | `$ff` on an FM-7 |
| `$fd1f` | transfer status | bit 7 = DRQ, bit 6 = INTRQ, rest 0 |

**`$fd1d` is a register where CSP and MAME disagree, and CSP is right.** MAME
(`fdc_w` case 5) zeroes the *whole* latch — motor bit included — when the
drive number exceeds 1, and echoes the latch on read. CSP takes the motor bit
**before** any drive validation (`floppy.cpp:221` `set_fdc_fd1d`) and its read
*builds* the value: bit 7 is the **live motor state**, gated on a drive being
present (`floppy.cpp:178` `get_fdc_motor`), not an echo of what was written.
Real software depends on this: Ys writes `$82`/`$83` (drive 2/3, motor on) and
then polls bit 7 via the boot ROM; under the MAME rule the motor bit vanished
and the poll never exited. This core follows CSP.

## $fd20-$fd23

Kanji ROM window (optional expansion hardware — MAME loads `kanji.rom`
`ROM_LOAD_OPTIONAL`, CRC32 `62402ac9`, 128 KB; software probes for it). MAME
`kanji_r` (`fm7.cpp:1054`) and CSP (`kanjirom.cpp:83`) agree exactly:

| addr | access | function |
|---|---|---|
| `$fd20` | write only | glyph address, high byte |
| `$fd21` | write only | glyph address, low byte |
| `$fd22` | read only | first byte of the 16x16 glyph row pair |
| `$fd23` | read only | second byte |

ROM index = `(address << 1) | bytesel`. The write-only pair reads back `$ff`
(undecoded), which is what MAME returns. Verified from F-BASIC against
`kanji.rom` contents at two addresses (`KANJI.v`, `MDECODE.v`).

## $fd37

Multi-page register: which VRAM planes the CPU can access and which are
displayed. Write-only in effect (reads are not decoded here). Both references
confirm the split — MAME `multipage_w` (`fm7_v.cpp`) masks `data & 0x77`, CSP
`display.cpp:444` `accessmask = val & 0x07; dispmask = (val & 0x70) >> 4` —
and the bit-to-plane order matches CSP.

| bits | function | polarity |
|---|---|---|
| 2:0 | CPU access mask, planes B/R/G | set bit = plane **inaccessible** |
| 6:4 | display mask, planes B/R/G | set bit = plane **blanked** |

Reset state `$00`: all planes visible and writable. Implemented in `FLAGS.v`
(`m46`), consumed in `PAL.v`.

## $fd38-$fd3f

Digital palette, 8 entries, one per address, 3 significant bits per entry:
bit 0 = blue, bit 1 = red, bit 2 = green (`PAL.v`, decode `PLTREGn` in
`MDECODE.v`). Readable — reads return the stored entry. Reset initialises
entry N to N.

## $ffe0-$ffff

Not `$fdxx`, but established alongside it:

- **`$ffe0-$fffd` is plain read/write RAM.** Verified directly:
  `poke65509,170:?peek(65509)` returns 170, and the boot ROM's own
  `W $ffe5 <- $3c` reads back `$3c`. CSP maps the range as unconditional
  read/write RAM (`mainmem_readseq.cpp` / `mainmem_writeseq.cpp`, no
  boot-RAM-write guard). MAME seeds only the reset vector into its vector RAM
  (`fm7.cpp:1738` → `$fe00`). *(Superseded claim: an earlier note said the
  `$ffe0-$ffef`/`$fff0-$ffff` vectors were ROM, not RAM — disproven; do not
  re-derive it.)*
- The boot ROM occupies **`$fe00-$ffef`** (CSP
  `refs/common-src-project/src/vm/fm7/fm7_common.h:19`), with the RAM mapping
  above taking `$ffe0-$fffd`; `$fffe-$ffff` is the reset vector, `$fe00`.
- The physical boot ROM is one 2 KB chip (`rtl/roms/TL11_11_M152.BIN`) holding
  **four 512-byte banks** — MAME: "actually 0.5K banks of the same ROM"
  (`fm7.cpp:2179`). The four OSD boot-ROM slots select the four banks. Bank 0
  loads the boot sector to `$0100` (required by real boot disks), bank 2 is
  the DOS revision loading to `$0300`, bank 3 is empty (`$ff`). Every bank's
  reset vector is `$fe00`.
- **`boot_bas.rom` is a bad dump**: its last two bytes (the reset vector) read
  `$ffff` instead of `$fe00`. It is otherwise byte-identical to bank 0 (and to
  MAME's copy, CRC32 `c70f0c74`). No longer used; the core addresses the whole
  chip.

## Not present on an FM-7

The 320x200/40-column width bit lives in `$fd12`, the "Sub mode status
register (FM-77AV or later)" (MAME `fm7_v.cpp:828`) — it does not exist on an
FM-7, so no FM-7 title can select it. `$fd08-$fd0c` and other undecoded
addresses read `$ff`.
