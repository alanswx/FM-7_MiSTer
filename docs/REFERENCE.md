# FM-7 core — permanent reference

Durable facts and hard-won method for whoever works on this core next. Bug status lives in git
history and code comments, not here. `Pn-m` numbers cite sections of the retired `TODO.md` (in git).

---

## 1. Reference emulators — which to trust

| | path | role |
|---|---|---|
| **CSP** | `refs/common-src-project/src/vm/fm7/` (Takeda Toshiya) | **Primary authority.** Most complete FM-7: full keyboard tables, kanji, FDC, joystick, bubble cassette. |
| **77AVEMU** | `refs/77AVEMU/src/fm77av/` (CaptainYS) | **Tiebreaker.** Cleanest structure; best for CRTC/render behaviour and `.T77`; carries notes from experiments on real hardware. |
| **MAME** | `refs/mame/src/mame/fujitsu/fm7.cpp`, `fm7.h`, `fm7_v.cpp` | Most readable I/O map — and an **unreliable FM-7 driver**. Never treat it as correct on its own. Littered with `BAD_DUMP`; its VRAM-access halt is commented out at `fm7_v.cpp:643`. Following MAME has been the bug more than once. |

**Trap when reading CSP:** large parts are guarded by model defines. Code inside
`#if defined(_FM77AV40EX)` and friends is **not** the plain FM-7 path. Example: the `$fe00`/`$ffe0`
split at `fm7_mainmem.cpp:218` is AV40EX-only; the plain FM-7 boot ROM is `$FE00-$FFEF` per
`fm7_common.h:19`.

### Worked example: 77AVEMU's TRACE LOG is off by one, not its FDC

**This section previously claimed 77AVEMU's sector reads were off by one and that
this core was right. The second half is true and the first half is wrong.** The
emulator delivers the correct bytes; only its `--trace-io` output is shifted, and
diffing the traces without knowing that desynchronises the whole comparison at
the first sector read.

On the original Fujitsu FM77AV demo disk, the boot loader's sector read loop at
`pc=$521F` logs:

| | first bytes in the trace |
|---|---|
| this core | `1A 50 86 FD 1F 8B 30 8D ...` |
| 77AVEMU   | `FF 1A 50 86 FD 1F 8B 30 ...` |

Track 0 sector 1 of the `.d77` is `1A 50 86 FD 1F 8B 30 8D 00 42 ...`, so this
core's trace is the honest one. But the reference is not returning `$FF` to its
CPU. `FM77AV::IORead` (`fm77avio.cpp:632-651`) does:

    uint8_t byteData = NonDestructiveIORead(ioAddr);   // value BEFORE side effects
    ... if monitored, PRINT byteData ...
    switch(ioAddr) { ... case FM77AVIO_FDC_DATA: byteData = fdc.IORead(ioAddr); }

The print happens before the switch, so for any port whose read *advances*
something the log shows the previous value. `fdc.IORead` then performs the
advance and returns the right byte to the CPU. They know about the ordering --
`$FD02` re-reads after its side effect with the comment "This one needs to be
read after Move." The FDC ports do not.

**Consequences.** Do not "fix" 77AVEMU's FDC to match: patching it changes
nothing (tried -- six titles render byte-identical before and after, and the
logged sequence is unchanged) because there is nothing wrong with it.
`tools/seqdiff.py` now leaves the VALUE of a `$FD1B` read out of its comparison
key for both sides, which is what let a Luxsor disk 2 comparison run 3100
accesses further, out of the boot ROM and into the title's own loader.

(Superseded claim, corrected: "77AVEMU emits a leading `$FF` and so drops the
sector's last byte" -- it emits the leading `$FF` only into the log.)

Its `$FD18` Type I status bit 6 looked wrong on the same disk too -- reporting
write-protect where we return `$04`. **That was ours**: `tools/77avemu_headless.cpp`
was force-mounting every image write-protected. Fixed; see trap 50.

### Worked example: VRAM plane order (MAME is the odd one out)

Recorded so nobody "fixes" the display to match MAME:

| VRAM plane | MAME | CSP | 77AVEMU | this core |
|---|---|---|---|---|
| `$0000` | blue | blue | plane 0 | blue |
| `$4000` | **green** | **red** | plane 1 | **red** |
| `$8000` | **red** | **green** | plane 2 | **green** |

MAME's `fm7_v.cpp:1173-1178` reads `code_g` from `+0x4000` and `code_r` from `+0x8000`. CSP's
`vram.cpp:512-514` does the opposite, and 77AVEMU's `srcColor` agrees with CSP. This core follows
CSP (`SDECODE.v`: `SDRAMBn`=$0000, `SDRAMRn`=$4000, `SDRAMGn`=$8000). Changing it to match MAME
would swap red and green over the whole display. The palette *byte* layout is not in dispute —
MAME and CSP agree `b`=bit0, `r`=bit1, `g`=bit2, and the top levels match (`VGA_R=grb[1]`,
`VGA_G=grb[2]`, `VGA_B=grb[0]`).

### MAME's software list is a triage input

MAME ships `refs/mame/hash/fm7_disk.xml`, where an entry can carry `supported="no"` — meaning
**MAME itself cannot run that title** (14 of its 158 disk entries). Cross-referencing a failing
title against it separates "our bug" from "problematic for everyone", and it cuts both ways: titles
have worked here that MAME marks unsupported. **Caveat:** "MAME cannot run it" is evidence about
the title, not proof about this core — it shifts priority, it does not close a case.

Before counting failures at all, subtract disks that should not boot. `vsim/sweep/bootsector.py`
classifies them straight from the image: `BRA-self` halt stubs (`ORCC #$50 / STA $fd03 / BRA *`) and
`uniform-$xx` boot sectors (every byte identical — $e5 is the standard formatted-never-written fill
on FM/MFM media; $00 and $ff also occur); also exclude secondary disks of multi-disk sets and `[b]`
(known-bad dump) filenames. **A filter that was tried and is WRONG: "the boot sector is mostly
zeros, so it is not code".** A short loader padded to the 256-byte sector is the normal shape —
1942's boot sector is 92% zeros and opens `86 fd 1f 8b 97 0f ...` (6809 code); Tritorn's is 87%
zeros and renders correctly. Only "every byte identical" is safe; over-count failures, not the
reverse.

From the same XML: MAME flags `fm7`, `fm8`, `fmnew7` as working, `fm77av` as
`MACHINE_IMPERFECT_GRAPHICS`, and `fm7740sx`, `fm11`, `fm16beta` as `MACHINE_NOT_WORKING` — so
MAME is not a reliable oracle for AV40SX behaviour either.

---

## 1b. The FM-7 cassette format, from the Fujitsu manual

Written down because `rtl/t77_decode.v` describes the format in terms that do not match
it, and because tape loading does not currently work at all -- see TODO.md.

**FM-7 System Specifications section 1.12.4, 記録方式** (page 1-45, page 59 of the scan in
`refs/fm7-docs/archive-org-fm7-system-specifications`):

* The FM-7 records by **varying pulse WIDTH**, not by shifting between two carrier
  frequencies. A bit is exactly **one wave**:
  * bit **0** = one full cycle at **2400 Hz** = 416.7 us
  * bit **1** = one full cycle at **1200 Hz** = 833.3 us
* Frame: **start bit (=0), 8 data bits LSB first (b0..b7), then TWO stop bits (=1)**.
* Because the two bit values take different times, the baud rate depends on the data.
  The manual gives `baud = (m1+m2) / (m1*T1 + m2*T2)` with `T1 = 1/2400`, `T2 = 1/1200`,
  which for equal counts of 0s and 1s is the quoted **1600 baud** average (section 1.12.1).

`t77_decode.v` calls these "a 1200 baud half-bit" and "a 2400 baud half-bit", which is the
Kansas-City / FSK mental model and is the wrong one for this machine. The widths it uses
are right -- 77AVEMU's own decoder defines `0x1A+0x1A` as the off bit and `0x30+0x30` as
the on bit, and both commercial and generated images contain exactly those -- but the
naming will mislead the next reader.

**An unresolved discrepancy, recorded rather than guessed at.** If bit 1 is one 1200 Hz
wave and bit 0 is one 2400 Hz wave, bit 1 must take exactly TWICE as long as bit 0. In the
t77 images it does not: `0x30`/`0x1A` = 48/26 = **1.846**, not 2.0. So either the t77 tick
is not linear in time, or the images encode something slightly different from the manual's
idealised waveform. Do not derive a tape clock from the manual's microseconds alone until
this is settled -- at the current 9.125 us tick the average works out to 1481 baud against
the documented 1600, and forcing the tick to 8.458 us to hit 1600 changes nothing that
matters (measured: cassette-bit edges 162019 -> 174939, image consumption 37% -> 40%,
screen still on `Searching`).

## 2. The RDQEn two-strobe mechanism

**The single most valuable insight in this repo.** `RDQEn` (MCPU.v:55) is
`~(RWB & (QB | EB))`, wired through `core.v:348` into `MDECODE`'s read-strobe decoder. That
expression assumes Q and E **overlap** into one continuous strobe from Q rising to E falling. In
this model they do not, so
**every `$fdxx` read decodes as TWO strobes** — a Q-phase pulse, a dead gap, then an E-phase pulse.
Measured on `$fd03` (`$time` counts CLKSYS edges, **not** picoseconds — misreading that mis-sized
one fix attempt):

```
t=324215191  RFD03n=0  EB=0   pulse 1 opens, E LOW
t=324215201  RFD03n=1  EB=0   pulse 1 shuts, 10 cycles wide
t=324215211  RFD03n=0  EB=1   pulse 2 opens, E HIGH  <- the real data cycle
t=324215231  RFD03n=1  EB=0   pulse 2 shuts, 20 cycles wide
```

The 6809 latches on E's fall — **in the second pulse**. Any register that acknowledges, clears or
side-effects on a read edge therefore fires too early and hands the CPU the post-acknowledge
value. `$fd04`'s attention latch showed the identical signature on OS-9 (`t=171925871` onward:
clear fired at the close of pulse 1, pulse 2 read "no attention pending" every single time). This
one mechanism broke both the `$fd03` interrupt-cause register (no handler could ever tell which
source fired) and the `$fd04` attention flag (the main CPU never once saw an attention the sub had
sent).

**Why the obvious fixes fail:** a plain edge does not work — both edges of pulse 1 are too early —
and a short glitch filter does not work either; the gap is 10 cycles, not one.

**The fix idiom** (reference implementations: `rtl/CLKCTRL.v` `fd03_ephase`, `rtl/TIMER.v`
`fd04_ephase`): at each strobe opening, latch whether `EB` is high — that marks the E-phase pulse,
the cycle the CPU actually latches — and acknowledge only at the **close of that pulse**. Keep set
winning over clear, so an event landing on the acknowledge cycle is not swallowed. Keying on the
bus phase is why this is robust; a wide timeout would "work" and then break on software that reads
the register twice in quick succession.

```verilog
reg strobe_d, ephase;
always @(posedge CLKSYS) begin
  strobe_d <= RFDxxn;
  if (strobe_d & ~RFDxxn) ephase <= EB;      // strobe opening: is this the E-phase pulse?
  if (set_condition)            pend <= 1'b1;
  else if (~strobe_d & RFDxxn & ephase)      // close of the E-phase pulse
                                pend <= 1'b0;
end
```

Main `$fd01`, sub `$d401`, and sub `$d402` reads were measured as two decode
strobes; `KEYBOARD.v` and `FLAGS.v` now acknowledge them only at the close of
the E-phase pulse. The sub `$d402` measurement was made on 1942: Q opened with
`SEB=0/SQB=1`, then E opened with `SEB=1/SQB=0`. The sub-side `$d40a` BUSY
handshake uses `SBUSYSETn` from the overlap-qualified `SQANDEn` decode and was
measured as a single pulse in simulation.

The `$d404` read itself was then measured on OS-9 and 1942 as the same split Q/E
shape. `TIMER.v` sets `attn_pend` on the trailing edge of `ATTENTn`; both pulse
closes therefore set the same latch, and there is no lost acknowledge analogous
to the read-clear paths above. It needs no RTL change.

### FDC seek-time sector priming

Wizardry, Wizardry II, and Wizardry III share a boot loader that writes the
next sector number while a `$fd18=$1a` RESTORE/SEEK/STEP command is still busy,
then starts a `$fd18=$80` read. The WD179x retains that sector-register write;
dropping it makes the following read use the old sector number. `wd1793.sv`
therefore accepts `$fd1a` writes during those seek/step states, while still
rejecting sector changes during an active data-transfer command. This fixes all
three Wizardry images in simulation without changing the normal eight-case
regression.

### Daisenryaku FM page-zero path

Daisenryaku's apparent `$009f FCB $05` failure was an FDC ID-match bug. The RTL
matched the physical head track and sector but ignored the D77 ID cylinder
versus the WD1793 track register. The game leaves the register at 0 while the
head is physically at track 4; 77AVEMU therefore reports the read as missing,
restores, and reads track 0 / sector 11. The RTL now checks the ID cylinder
unconditionally, and its command stream matches the reference through the
subsequent track loads. The core draws the Daisenryaku title art -- soldier,
tank, aircraft -- at frame 400, then **clears it by frame 600 and never draws
the red 大戦略FM logo**, where the reference holds art *and* logo at 604/625
(67.7% coverage, 346 KB). Measured 2026-08-29 at matched instants.
(Superseded claim: "the core reaches the title screen at frame 621" -- at 621
this core is blank, 0.2%. Both that claim and the later "Daisenryaku renders
nothing, 3790 bytes" came from scoring ONE frame: 621 misses the art we do draw
at 400, and 1980 misses it too. The title is drawn and then erased, which
neither single sample can show.) The narrow `$02`/`$42`/`$52` carry-dependent aliases and `$4e`
CLRA correction in `mc6809i.v` remain covered by the local 77AVEMU comparison.
With the exact FM-7 ROMs, the first BIOS divergence against 77AVEMU is still
`$fd05`: 77AVEMU reads `$fe` (BUSY asserted after reset), while this core reads
`$7e`. Forcing the core BUSY bit high changes boot timing but is not required for
the title fix.

The supplied sibling `refs/TOWNSEMU` now satisfies 77AVEMU's build contract.
Its native CUI frontend needs a display, so a small headless driver was used.
The native-BUSY reference reaches the same loader and later FDC sequence when
the exact FM-7 ROMs and disk are used. Return and Space reach the keyboard latch
without affecting the boot path, and the DOS boot-ROM selections do not mount
this FM-7 disk.

Any other read-clear register driven directly from the sub-side read decode
(`SCPU.v:36`: `assign SRDQEn = ~((Q|E) & RnW);`) still needs the same audit before
being trusted.

**Related qualifier hazard:** two early bugs (P0-1, P0-4) were the same fault on the two CPUs — an
I/O read strobe qualified by `E` alone, which collapses at the exact edge `mc6809i` latches the
data bus. If a read path misbehaves, check its qualifier first.

---

## 3. Derived clocks in Quartus — a hardware-only bug class

Large parts of `rtl/` transliterate the FM-7 schematic, where a 74LS74 really is clocked by a
74LS138 decode output. In Verilog that becomes `always @(posedge SOMESTROBEn)` where the "clock"
is combinational logic over the address bus.

- **Verilator** evaluates the decode once per delta cycle: exactly one clean edge per access.
  The RTL behaves perfectly.
- **Quartus** builds the decode from LUTs on general routing. A LUT decode **glitches** as its
  inputs arrive skewed, and every glitch is a spurious clock edge — the register latches at
  moments that do not exist in simulation.

**A green simulation is not evidence about this class of bug.** The confirmed case: `core.v` tied
`FLAGS`' `SRESETn` to `1'b0`, holding four flip-flops in reset (glitchy clocks with nothing to
clock — latent). Commit `f9548d8` untied it and OS-9 immediately regressed **on real hardware
while remaining perfect in simulation**. That asymmetry is the diagnosis. Commit `3f85852` moved
the four onto `CLKSYS`; hardware confirmed the fix.

**Conversion recipe** — a clocking change only, semantics preserved exactly. Filter the strobe
through a short shift register so a 1-2-cycle decode glitch has to persist to be believed, then
take the edge from the filtered copy:

```verilog
reg [2:0] strobe_sr;
always @(posedge CLKSYS) begin
  strobe_sr <= { strobe_sr[1:0], WFDxxn };
  if (~RESETBn)                          m9 <= 3'd0;
  else if (strobe_sr[2] & ~strobe_sr[1]) m9 <= { ... };  // filtered leading edge
end
```

Rules: (1) sample the **leading** edge of the strobe — a trailing-edge sample races the CPU
releasing the bus (the `$fd37` / P1-4 hazard), with the `m77` exception below; (2) an edge cannot
be missed — E is 1.2288 MHz against 48 MHz `CLKSYS`, E-high is ~19 CLKSYS cycles, and the filtered
sample lands two cycles in, still comfortably inside the access; (3) preserve clear/set dominance;
(4) the module may need an `input CLKSYS` added and wired in `core.v`.

**Converted and confirmed on hardware:**

| file | register | commit |
|---|---|---|
| `FLAGS.v` | `m56_5`, `m56_9`, `m45`, `m44_5` | `3f85852` |
| `PERIPHERAL.v` | `m10`, `m2`, `m9` | `b34171e` |
| `MFD.v` | `m6_q` (FDC IRQ mask) | `649d054` |
| `PAL.v` | palette read-back | `5cae28c` |
| `MB60H010.v` | `SRL`/`SRH` (display offset) | `b632ea1` |
| `FLAGS.v`, `PERIPHERAL.v` | 3-cycle filters replacing 1-cycle edge detectors | `18e635c` |

**A ratio is not a pitch.** `sound_tb.sv` asserted the PSG's tone *divider* was 16 and passed for
the life of the project while the chip played every note an octave flat — the divider was right and
the clock feeding it was half what it should be. The bench now prints the tone in Hz for a 48 MHz
CLKSYS next to the number an AY-3-8910 at the FM-7's documented 1.2288 MHz plays, so the two can be
compared without deriving anything. Measure the quantity the ear judges, not a proxy for it.

**Still on async decode clocks:**

- **`KEYBOARD.v:543` `m77`** (keyboard routing, `LPMASKn`, `TMMASK`) — **three hardware conversion
  attempts all regressed OS-9, 0 boots in 8 tries each**: leading edge, trailing edge, and
  mid-strobe (`0ce7ad3`, reverted by `e443a02`). A sim experiment then showed all four designs
  capture the same values at the same times, so neither the sample point nor the captured data is
  the variable, and simulation has exhausted what it can say. **Recommendation: leave `m77` on its
  async clock** — it is empirically working. If it ever misbehaves, the open leads are: `m77` is
  the only such register fed from `MDATABUS_out`, a wide combinational mux over the whole main bus
  (a data-side timing question, reproducible in vsim); and the only one whose output crosses into
  another clock domain (`TMMASK` into `CLKCTRL`).
- **`SOUND.v`'s four `$fd0d`/`$fd0e`/`$fd15`/`$fd16` strobes** — **converted, awaiting hardware.**
  This is the entry that said "a conversion needs a listening test or a joystick test", and both
  were finally run: sound played, the joystick did not. That split is the diagnosis. A spurious
  command is a spurious PSG register write — inaudible among the thousands a music driver issues,
  but one bad write to register 15 clobbers the joystick *selection* and port A then reads `$ff`
  ("no stick") until software writes it again. They were on one-cycle edge detectors, which the
  recipe above says is too short. Now filtered. Sim is byte-identical either way, so only hardware
  can confirm it.
- **`FLAGS.v:228` `m46` (`$fd37`)** — behaviour verified correct in sim (latches on the leading
  `negedge WFD37n`; bit split matches MAME `& 0x77` and CSP `accessmask`/`dispmask`), but it is
  still an async decode-strobe latch on hardware.

These survivors are not emergencies — they have been live since the beginning and the machine
works on hardware as built. The narrow rule: **never release a held flip-flop, or re-time anything
near one of these, without converting its clock first.** Convert **one file per commit** so
hardware can bisect. `run_tests.sh` and the sweep only prove behaviour did not change; **building
an `.rbf` and flashing a MiSTer is the only real test** of this class. Good smoke tests: OS-9 at
`--bootrom 2` (reaches the `OS9:` shell), F-BASIC boot plus typing, a `.t77` `LOAD"` (exercises
tape motor `m10` end to end; JIS layout — `"` is Shift+2, not Shift+apostrophe), a title with
sound plus a joystick, and pixel-exact comparison of Thexder/Hydlide II for display-path changes.

Hardware-loop traps, each of which produced a confident wrong verdict: screenshot **byte size** is
not pass/fail (a garbage screen measured 7444 bytes and was scored as a successful OS-9 boot —
compare against a known-good reference image and score the text pixels separately, since a garbage
frame still matches ~95% of a mostly-black screen while matching 0% of the banner); selecting boot
ROM 2 from the OSD succeeds about one try in three, so a single failed run carries no information —
8 tries against a baseline that booted within 3 is the minimum worth reporting; and raw Linux
keycodes (`kbdRawDown:108`) go to the emulated FM-7's keyboard, not the MiSTer menu — only named
actions (`kbd:down`, `kbd:confirm`) drive the OSD.

---

## 4. Build and simulation gotchas

- **Build:** `cd vsim && make`, then `./obj_dir/Vemu --help`. `./run_tests.sh` is the guard rail.
- **`vsim` must be run from `vsim/`.** Every ROM loads via `$readmem` on the relative path
  `./roms/...`; from anywhere else Verilator prints `$readmem file not found` as a **warning**,
  the ROMs come up empty, and the run still completes with plausible counts and a blank
  screenshot. Any driving script must `cd` to `vsim/` and grep its log for `readmem file not
  found`. (Trap 9 below has the full failure story.)
- **`files.qip` is the canonical Quartus file list**, not the `.qsf` — the qsf sources it, and the
  IDE re-injects a duplicate per-file list into the `.qsf` whenever the project is opened in the
  GUI; delete that when it reappears. `vsim` has its own separate list in `vsim/Makefile`.
- **These files are CRLF** and must stay that way: `rtl/FLAGS.v`, `rtl/MFD.v`, `rtl/SRAM.v`,
  `rtl/ROMS.v`, `rtl/CLKCTRL.v`, `rtl/PERIPHERAL.v`, `files.qip`, `FM-7_MiSTer.qsf`. Check with
  `file` after any scripted edit.
- **macOS `awk` is BSD awk**, not gawk: no `asort()`, no 3-arg `match()`. A script using them
  fails silently if stderr is discarded.
- **`--vcd` requires `make clean && make TRACE=1`** and is windowed by
  `--trace-from`/`--trace-until`. Two frames is ~700 MB, so always window it. It has settled
  questions that rounds of `$display` could not — reach for it after the second failed printf, not
  the fifth.
- **`--trace-from`, `--trace-until` and `--trace-max` work for `--trace-mem`/`--trace-mem-sub` but
  do NOT apply to `--trace-io`**, which logs the whole run regardless — filter on the frame column
  yourself (`awk '$1>=1400'`).
- **`DEBUG_*` and `TRACE` are `+define+` args baked in when Verilator runs** — see trap 3 below.
- **Test images:** `software/Neo Kobe - Fujitsu FM-7 (2016-02-25).zip` holds 630 `.7z` archives,
  195 of them `[FD]` floppy sets unpacking to 350 disk images (221 FM-7, 129 FM77AV). `[FD]` is a
  shell/unzip character class, so `*[FD]*.7z` silently matches the wrong entries. Extract with a
  bracket-free pattern — `unzip -o -j -q "$Z" "*Hydlide II*FD*.7z" -d . && 7z x -y -o. *.7z` —
  or, for the whole collection, extract every `.7z` and filter by name afterwards.

---

## 5. Measurement traps — every one of these cost real time

More bugs in this project were *mis-diagnosed* than were hard to fix. All of these produced a
confident wrong answer at least once:

1. **A trace that hits `--trace-max` is truncated from the START of the run.** If the line count
   equals the cap, you are looking at the earliest frames, not the ones you asked for. Always
   check the frame range in the output.
2. **`--trace-cpu` prints one instruction late.** The log therefore does *not* contain the
   instruction that stopped the CPU. For "why did execution end", read the CPU state (`--vcd`),
   not the disassembly.
3. **`DEBUG_*` and `TRACE` become `+define+` args baked in when Verilator runs.**
   `make DEBUG_FDC=1` after a plain `make` relinks the old model with the old defines — clean
   build, clean run, no output, indistinguishable from a real null result. `touch` a file in the
   target module first and verify with `grep -l <MARKER> obj_dir/*.cpp`.
4. **Check frame numbers line up before concluding a value did not propagate.** Comparing a
   sub-CPU read at frame 1074 against a main-CPU write at frame 1076 "proves" a lost write that
   was never lost.
5. **A low VRAM write count proves nothing.** Thexder displays a full title screen while writing
   *zero* VRAM bytes — the image is already there. Only a cumulative count from reset, with the
   data values checked, means anything.
6. **Reconstructing state from a bus log is not the same as asking the RTL.** A Python decoder
   inferring `(track, side, sector)` from `$fd18-$fd1b` traffic reported sectors returning the
   wrong side's data; a `$display` in the RTL's own match arm showed all 19 matches exact.
   Instrument the decision, not its inputs.
7. **Triage a sweep by `main/frame`, not by screenshot.** Healthy titles sit at 4400-5800. Low
   rate + blank screen is a crash (expect a `CWAI` in page zero); low rate + content is a title
   idling at a screen it already drew; normal rate + blank is something else again. A screenshot
   cannot tell these apart.
8. **A proxy metric can stay flat while the bug is being fixed.** P4-13 was framed around "the
   main writes 6891 payload bytes and the sub reads 5833, a 15% shortfall". The fix took that to
   5878/6891 — 84.6% to 85.3%, near enough nothing — while the screen went from unreadable to
   correct. Commands vary in length, so the sub never had to read every byte of every block and
   the ratio was never measuring what it looked like it measured. Check the *outcome*, and only
   trust a proxy you have shown tracks it.
9. **`vsim` must be run from `vsim/`, and running it from anywhere else fails *silently and
   plausibly*.** The Verilog loads every ROM with `$readmem` on the relative path `./roms/...`.
   From another directory Verilator prints `$readmem file not found` as a **warning**, not an
   error; the ROMs come up empty, the machine runs away into the `$fdxx` window, and the run still
   completes, still writes a screenshot, and still reports plausible instruction counts. A
   350-title sweep driven from the repo root returned **3355 main / 2923 sub and a blank 3790-byte
   PNG for every single title** — which reads as a uniform "nothing boots on this core" result
   rather than as a broken harness, and is far more dangerous than a crash. Any script driving the
   simulator must `cd` to `vsim/` and check its log for `readmem file not found`.
10. **A verified WRITE path says nothing about the READ path.** P4-15 sat undiscovered through
    several investigations because `$8000-$fbff` accepted every write perfectly and returned zeros
    on read. An earlier log recorded "a clean contiguous 24 KB program load, no gaps, no
    double-writes ... this whole path is working" — which was true, and useless. A memory that
    stores and returns zeros does not look like broken memory; it looks like a software bug in
    whatever ran next. **Read back what you wrote.**
11. **`--trace-mem` only logs `$fdxx`, whatever its help text says.** It claims "every main-CPU
    bus cycle in that hex address range", but `--trace-mem 0100-0110` across the boot-sector load
    returns *zero lines*. That reads as "this region is never touched", which is a very convincing
    lie. For RAM use `--dump-shadow`, which records both directions
    (`shadow_m.mem[addr] = rw ? din : dout`) — a value in it is whichever access happened last,
    and comparing a written value against a later read is exactly how P4-15 was pinned down.
12. **`grep` a trace for a hex address and you will match cycle counters.** `grep -c d404` over a
    `--trace-mem-sub` log reports a healthy count of lines like `cycles 86d4041 reading D0` — the
    address appears as a substring of a cycle number, and it reads exactly like "the port is being
    used". Anchor on the trace format instead: `grep -cE 'smem .* \$d404'`. Related: the main-CPU
    trace prints `mem` followed by **two** spaces, so `grep ' mem W '` silently matches nothing
    and looks like a clean null result. And the other direction: a grep returning nothing is a
    claim about your pattern, not about the machine —
    `grep -oE 'W +\$fd05 <- \$[0-9a-f]{2}'` printed nothing over a log where `grep '\$fd05'`
    found 70629 hits. **Print raw lines first, then narrow.**
13. **`| tail -N` and `| head -N` will quietly delete the evidence.** Trace lines come out
    *before* the end-of-run summary, so `--trace-mem ... | tail -40` shows the summary and none of
    the trace — and it looks exactly like "the access never happened". The mirror image also bit:
    a port histogram printed with `head -15` hid `$fd02`, whose two writes ranked 16th, and that
    produced a confident *retraction* of a correct finding. Both directions cost a wrong
    conclusion in one session. Write traces to a file and query the file.
14. **An inherited repro flag becomes an unexamined premise.** `--key '820:@SPACE'` rode along in
    every Ys command for a whole investigation because it was in the original repro line. It was
    never the thing breaking a deadlock — Ys renders its title screen with no key at all, and the
    flag simply advances past it. Run the no-flag case once before characterising behaviour.
15. **A stale reference is worse than no reference.** `shots-ref/` sat three months behind the
    core while `run_tests.sh` compared nothing against it and still exited 0. "All 8 rows pass"
    meant only "eight sims produced plausible instruction rates". If a suite cannot fail, it is
    not evidence.
16. **A FIXED-frame screenshot is only comparable between builds of comparable TIMING.** This is
    trap 7 in new clothes and it cost a false regression report. The sweep shoots at frame 680.
    After an interrupt-path fix every title spent cycles in an ISR it never used to run, so boot
    shifted later and the same shot landed *earlier* in each title's startup. Three titles scored
    as regressions were in fact large gains — Alpha `6710 -> 3790` at 680 but **26281** at 1400,
    Solitaire Royale `3960 -> 3790` but **32000**, Take Out Vol. 6 `4827 -> 3790` but **13203**.
    A timing-affecting change makes the sweep under-report in **both** directions. Re-sweep at a
    longer frame count before believing either number.
17. **`find <symlink>` does not follow it without a trailing slash**, and `sweep.sh` uses
    `find "$DISKS"` bare. Pointing `$OUT/disks` at a symlink made the sweep report "0 disk images"
    and exit successfully in seconds — a mis-set path looks like a clean fast run, not an error.
    Check the image count in the sweep's own output before trusting the results file.
    `run_tests.sh` had the identical bug and it is worse there: `software/` is a real directory
    in the main checkout and a **symlink in a git worktree**, so in a worktree every disk row
    vanished from the run with no message, and a `BLESS=1` then left those references untouched
    and stale while reporting success. Fixed with a trailing slash; the same `.gitignore` patterns
    (`refs/`, `software/`) also fail to match the symlinks, so they showed up as untracked.

18. **"The counters moved by the expected timing shift" is a diagnosis, and it needs the same
    evidence as any other.** `ca75bfe` converted `SRAM.v`'s shared-RAM window from a single-port
    `ram` to a `dpram` and, in the rewrite, qualified each side's write with the *other* side's
    select: `main_write` gained a `& ~SSMEMn` term, so a main-CPU write only landed if the sub
    CPU happened to be addressing `$d000-$d3ff` at that instant. It never is — the main CPU
    writes that window while the sub is halted. The mailbox went dead, F-BASIC could no longer
    hand the sub a draw command, and the FM-7 booted to a **blank screen with both CPUs at
    completely normal instruction rates** (main 5558/frame, sub 8709/frame). The suite reported
    this for 15 commits as `SCREEN+CNT`, and it was written off in `TODO.md` as a startup timing
    shift from an unrelated `CLKCTRL.v` fix. Look at the actual PNG: a blank 640x200 shot is
    ~3790 bytes and every failing test was 3814. Restoring the two enable expressions reproduces
    `e19cde7`'s references *exactly*, counters and screenshots — which is the proof that the
    references were never stale.
19. **"The screen is wrong" is not a video-path finding until you have the reference picture.**
    The FM77AV demo's vertical colour bars were read as a raster/plane-combiner fault and cost a
    whole drawing-ALU implementation aimed at the wrong half of the chip. What settled it in one
    step was building `tools/build_77avemu_headless.sh` and dumping **both** VRAMs
    (`FM77AV_VRAM_DUMP` on the reference, `FM7_VRAM_DUMP` on the sim, same 12-plane layout) and
    diffing them plane by plane: the plane *contents* were byte-identical, they were simply in
    the wrong bank. Compare the stored bytes before theorising about the thing that draws them.
20. **A demo compared at "the same frame" may not be at the same point in the demo.** This core
    reaches the fully-typed FM77AV title around frame 2000; the reference reaches it in 20 M
    instructions. Comparing frame 870 against that reference shows five missing lines of text
    that are not a bug. Align on what is on screen, not on the counter.

21. **A fixed measurement window shorter than the signal's period reads as silence.**
    `sound_tb.sv` watched the PSG mix for 200,000 clocks after programming a tone whose
    full period is 409,600 — the window sat entirely inside the square wave's low half.
    Against the old chip that still showed a non-zero DC floor; against jt49, whose low
    half is a true zero, the identical, correct RTL reported "PSG mix stayed at zero", i.e.
    exactly the signature of the handshake bug the bench exists to catch. Size the window
    from the period you programmed.

23. **A signal can be DECLARED AND NEVER DRIVEN, and nothing warns you.** `core.v` had
    `wire EXTIRQ;` with no assignment for the life of the project. It reads as 0, so `$fd03`
    bit 3 reported "no external interrupt" forever — correct-looking, because the FM-7's own
    FDC interrupt reaches the CPU through `MFD.v` instead, so nothing ever raised one. It
    only surfaced when the FM77AV's YM2203 needed that path. Verilator does not warn (an
    undriven wire is legal), and neither does Quartus below its default severity. When a
    status bit is suspiciously constant, grep for a driver before theorising about the
    device behind it.
24. **A working interrupt and an interrupt storm look identical from outside.** Both show a
    high interrupt count and a CPU that is not making progress. What separates them is
    whether the handler *clears the source*: 2438 interrupts against 2439 writes to the
    YM2203's timer-control register is a working timer; the same 2438 with no clears is a
    storm. Count the acknowledge, not the interrupt — and note that connecting a real
    interrupt can make a title look *worse* (it ran away where it used to hang), which is
    progress, not regression.

25. **A screenshot suite whose references are its own output is blind to anything that moves
    the WHOLE picture.** The core displayed every frame right of where it belonged — three
    pixels in 640 mode, two in 320 — for the life of the project. Eleven blessed screenshots and a
    350-title sweep could not see it, because the reference shifted with the core. It took a
    pixel comparison against 77AVEMU to surface, and it showed up as "colour banding" and
    "vertical stripes" on dithered 4096-colour art — i.e. as a *palette* complaint, which is
    where the eye goes and where two sessions of investigation went. **A suite can only catch
    what it compares against something it did not produce.** `tools/raster_phase.py` now asks
    the question directly, and without a reference emulator: predict each pixel's code from the
    core's own VRAM dump and find the offset at which one palette explains its own screenshot.
    A corollary worth its own line: **a bench over the modules is not the assembled core.** A
    standalone bench over MB60H010 + CRTRAM + PAL — the real modules, wired as `core.v` wires
    them, sampled as `sim.v` samples — agreed with 77AVEMU in 320 mode and was one pixel out in
    640, i.e. it would have shipped the bug it was written to catch. Three measurements of the
    assembled core agreed with each other and against it.
26. **A search window that ends where the answer is reports the edge of the window.** The
    offset sweep that found the display shift ran dx from -2 to +2 and returned "+2, 94%",
    which looks like a clean peak. It is not: at ±5 the real peak is +3 at 99%, and +2 was
    simply the largest value the sweep was allowed to return. Two other measurements were
    already built on that wrong constant before the widened sweep caught it. Always sweep past
    the apparent maximum and check the curve falls off on BOTH sides.
27. **Comparing pixels between two emulators requires agreeing on the DAC first.** `PAL.v`
    expands a 4-bit gun level with CSP's `{n,$F}` (1 -> `$1F`); 77AVEMU replicates the nibble
    (1 -> `$11`). Neither is wrong, but every non-black pixel differs, so a byte-exact
    comparison reports 100% mismatch and carries no information — which reads exactly like a
    catastrophic video fault. Both keep the level in the HIGH nibble, so compare `>>4` on each
    side. In nibble space the same pair of images went from "100% different" to 96.8% identical.
28. **"Ours has more non-zero bytes than the reference" is a claim about alignment until you
    have excluded it.** A Deep Forest VRAM diff showed ~15% more non-zero bytes in all twelve
    planes and was written up as "we set pixels that should not be set". It was the title
    logo: the reference had drawn a black box over the landscape and this core had not yet.
    The reference's own screenshots settle it for free — `--shot-every` on 77AVEMU takes
    seconds and shows whether the picture is still changing at the frame you dumped.
29. **A blessed screenshot can be a picture of the bug, and the prettier it is the more it
    looks like coverage.** `av-kohakuiro` earned its place in the gate as "81% coverage, 18
    colours — the strongest exercise of the 320-mode plane path outside the demo". The scene
    was an artifact of a palette stuck at the identity ramp; 77AVEMU renders that disk BLACK
    from its frame 500 onward, and the corrected core matches it on 100.0% of pixels with zero
    non-black pixels. A reference nobody has compared against a second implementation is a
    record of what the core did, not of what the machine does — and a rich-looking one buys
    false confidence in exactly the path it fails to test.
30. **A register file can be write-only by construction and nothing complains.** The FM77AV
    analog palette at `$FD30-$FD34` never took a single write: `PAL.v` asked for
    `~PLTREGn && ~MADDRBUS[3]` where `PLTREGn` is itself `... & MADDRBUS[3]`, so the condition
    was unsatisfiable. 12,288 writes from one title landed nowhere and the table stayed at its
    power-on ramp. Verilator does not warn about an unsatisfiable condition any more than it
    warns about an undriven wire (trap 23). **Read the table back.** `FM7_PAL_DUMP` did it in
    one run: 4096 of 4096 entries still at the reset value.
31. **A declared, DRIVEN signal that nothing consumes is the same bug as trap 23.** `CRTRAM.v`
    takes `SVCASBn/SVCASRn/SVCASGn` as inputs and never mentions them again, so `$FD37`'s CPU
    access mask gates no VRAM access at all. An audit for module inputs that appear exactly
    once — in the port list — is worth re-running after any refactor; it found this plus
    `SADRSEL` into `MB60H010` and `SVDHALT` into `FLAGS`.

32. **77AVEMU's PNG dimensions do not tell you the screen mode.** `BuildImage` sizes the
    buffer 640x400 for `SCRNMODE_640X200` *and* `SCRNMODE_640X400`, line-doubling the former
    (`fm77avrender.cpp:102-114`), and 320x200 for both 320-line modes. "This title renders
    640x400, so it selects the 640x400 mode" is therefore not an inference, and it was made
    here and written into `TODO.md` before being caught. The test that does work: in 640x200
    every even row equals the odd row below it, because the renderer writes the same pixel to
    `rgba0` and `rgba1`. By that test **all 22 640-wide AV renders in the collection are
    line-doubled 640x200 and none is a true 640x400** — including the two titles the wrong
    inference had blamed on the missing mode.

33. **`--trace-io` covers `$FDxx` only, and a title can do all its real work outside it.**
    Woody Poco halts the sub CPU at frame 16 and then drives the whole machine from the main
    side through the MMR aperture: the drawing ALU at `$D41x`, the page select at `$D430`, and
    53311 VRAM accesses — none of which appear in a `$fdxx` trace. Its `$fdxx` stream matches
    77AVEMU's port for port and value for value while the screen stays blank, which reads as
    "the I/O is fine, so the problem is elsewhere in the CPU" and is exactly backwards. The
    reference's own trace *does* show them, as `IOWRITE SUB: <pc> IO:D4xx ... by Main CPU` —
    note that the `SUB:` prefix is the address space and the trailing `by ...` is the CPU, so
    those lines are main-CPU accesses with a stale sub PC printed beside them. Read the `by`
    field, not the prefix. `make DEBUG_AVDRAW=1` gives the matching view on this side.
34. **A halted sub CPU is not by itself a fault.** The run stats flag `sub 6809 ... halted 99.2%
    of cycles`, and on Woody Poco that is *correct behaviour* — the main CPU holds the sub
    halted for the whole run on purpose so it can reach sub space itself, and 77AVEMU does the
    same on the same frame from the same PC. Two hours went into "why is the sub CPU stopped"
    before the reference was checked and found to be equally stopped. Compare the reference's
    sub activity before treating a halt as the bug.

35. **PNG byte size is not a coverage measure.** The sweep records it because it is free and
    separates "blank" from "something", and that is *all* it separates. After the ALU read
    trigger, Valis Disk 1 went 17149 → 14873 bytes and was written up here as having lost
    content; scored against the reference it had *gained* 1.7 points, 73.03% → 74.75%. PNG
    size tracks how compressible the image is, so a screen that resolves from dithered noise
    into flat colour gets smaller as it gets more correct. Score against the reference before
    calling a direction.

36. **An address decoder's outputs can be side effects, so "we never read that register"
    does not mean the address is harmless.** Every Y-output of `SDECODE`'s `m87`/`m98`
    *does* something when merely addressed: `SCRTSWn` toggles the CRT on/off latch,
    `ATTENTn` raises the main CPU's attention FIRQ. On the AV those decoders were missing
    address bits 9:8 and 5:4, so a drawing-ALU write to `$D428` switched the display off
    and a read of hidden RAM at `$D7F4` raised a spurious FIRQ. Neither address was ever
    "accessed as I/O" by any software; the aliasing did it. When a symptom implicates a
    register nothing appears to touch, check what else decodes to the same low bits.
37. **Two faults that cancel look like one working machine, and fixing either alone looks
    like a regression.** On the FM77AV demo disk the spurious `$D7F4` FIRQ hung the disk
    loader, while the `$D428` display-off was being undone by an equally accidental
    `$D5xx` read switching it back on. Fixing the FIRQ alone cleared the hang and left a
    black screen — which reads as "the fix did nothing" and nearly ended the
    investigation. If a well-evidenced fix produces a *different* wrong answer rather
    than a right one, suspect a second fault in the same mechanism before backing it out.

38. **Half the AV set renders blank on the REFERENCE, and a blank reference scores 100%.**
    33 of 67 titles. Agreement is per pixel, so two blank screens agree perfectly: those
    rows inflate any whole-set mean, make "titles >= 99%" meaningless, and — the part that
    cost real time — score a core that *starts rendering one correctly* as the worst
    regression in the sweep. World Golf II disk 1 sat at 100.00% while both machines drew
    nothing; when `c2fc867` made this core draw its full title screen the number fell to
    57.58%. **Check the reference's own coverage before believing any agreement figure.**
    `sweep/score.py` splits the set into scored / blank-both / drawn-here-only and refuses
    to print a single mean; `DRAWN_ONLY=1 sweep/av-sweep.sh` skips the blank half, which is
    also half the wall clock — but run the full set after anything that could plausibly
    unblank a title, or wins like that one stay invisible.

39. **archive.org's `_djvu.txt` for a Japanese book is often ENGLISH OCR run over Japanese
    pages.** It ships beside the PDF, looks like a text layer and greps like one, so it is
    easy to trust. It is close to worthless: 330 pages of FM-7/8活用研究 gave 1.4 MB in
    which the prose is shattered into per-character fragments. Same page, same scan:

        archive.org (eng OCR):  PE EE 所 / FM- フ / 日 62fkp オ / に に 還 叶 拉
        re-OCR (jpn+eng):       エディタ・アセンブラ マシン語ダンプ・リスト

    `tools/reocr.sh` re-runs it with Japanese data, resumably, one page at a time. Do that
    before concluding a book does not cover something.
40. **Even after a good OCR, grep the pattern you have and not the one you want.** OCR
    swaps `0/O/Q/D`, `1/l/I`, `5/S`, `8/B` and inserts spaces inside tokens. On the FM-7/8
    scan, plain `grep FD05` returns **1** hit; `tools/ocrgrep.py FD05` returns **103** —
    the rest are on the page as `FDO5`, `FDQ5`, `FDQO5`, `FD0S`, `7FFDOS`. Use `ocrgrep.py`,
    and treat a zero from it as "look at the rendered page", not as absence.
41. **OCR of a schematic is worthless in any language** — the text is tiny, rotated and
    scattered among the symbols. Render and *look*:
    `pdftoppm -f 300 -l 300 -r 110 -png book.pdf /tmp/p`. 77AVEMU cites this book's
    schematics by page number (`pp.294`, `pp.300`), and those pages are drawings, not text.

42. **The reference runner's third argument is 6809 STEPS, not frames.** `ref-sweep.sh`
    passes 20,000,000 and calls it "about 22 s of machine time"; passing `3010` there to
    match a `--stop-at-frame 3010` run gives **3.2 ms**. Worse is the near miss: an
    existing 26,000,000-step Woody Poco log covers 58.55 s against our 50.17 s, and
    comparing per-port write totals across that pair reads as a uniform ~7% shortfall in
    this core that is entirely run length. Both logs carry `INPUT frame=N` lines for every
    `--joystick`/`--key` event — **bucket both sides between those anchors** and the
    comparison is exact. Doing that turned a vague "we write less" into "identical through
    frame 2200, diverges the frame the scroll starts".

43. **77AVEMU's PC field on a `$D4xx` line is the SUB CPU's PC, and on an AV title the sub
    is halted, so it is a constant.** Every one of Woody Poco's 166,484 `$D4xx` accesses is
    logged `SUB: E146` — and `RESULT ... sub=$e146` confirms that is just where the halted
    sub is parked. `tools/iodiff.py` keys its comparison on PC, so for exactly the accesses
    that matter on an AV title it is matching a constant against our main-CPU PC and the
    result is meaningless. Ours logs the *main* PC there, which is the useful one. Compare
    `$D4xx` by port+value sequence, never by PC.

44. **Matching N entries of a low-entropy stream is not evidence of lockstep.** `$D410`
    takes only three values in this title (`$86`, `$9E`, `$80`). Our first 637 `$D410`
    writes matched the reference's first 637 exactly, which read as "identical, then we
    stop early" — and was wrong. The port *mix* had already diverged: over the same frame
    window we wrote `$D411` 1297 times against 3204, while `$D41C` matched at 97%. Check a
    high-entropy key (port+value across all ports) before believing a prefix match.

45. **Two different AV main-CPU clock rates both break the same title, so the fault is
    not the rate.** The FM77AV main CPU had no AV leg in the clock mux at all --
    `MCPUCLK = switch ? CLK4_9 : SCLK1` gives it the FM-7 leg's 4.8/4 = 1.2 MHz E, where
    MAME's `fm77av` is 2.016 MHz (fm7.cpp:1986) and CSP has 1.798 MHz normal / 1.565 MHz
    with MMR on for a base AV (fm7_common.h:79-82, fm7.h:254-258). Two attempts:

        E = 2.016 MHz (SCLK1)   FM77AV demo 92.8%/13 -> 100.0%/1  (solid screen)
        E = 1.714 MHz (48/7)    FM77AV demo 92.8%/13 -> 100.0%/1  (solid screen)
                                Valis disk 2 87.2%/22 -> 84.1%/24

    1.714 MHz is the closest an integer divide off 48 MHz gets to CSP's 1.798, and it sits
    above the 1.5 MHz threshold 77AVEMU uses for `$FD00` b0 -- and it fails exactly like
    2.016 did. **Both reverted.** That a *slower, closer* rate fails the same way says the
    demo is not calibrated to some specific frequency; something else in this core is
    coupled to the main CPU clock and comes apart when it moves. Find that coupling before
    trying a third number -- the rate is wrong, but changing it is not the fix.

    The first attempt also disproved a separate theory cleanly: at 2.016 MHz ROM fetches
    went 8.5M -> 17.9M and `$fdxx` I/O cycles 2.7M -> 5.4M in the same run, and Woody
    Poco's frame-3000 render came out **byte-identical** -- 55.7% coverage, 37 colours,
    58.73% agreement, all three unchanged. Whatever was wrong there, it was not throughput.

46. **A `$display` string survives into `obj_dir/*.cpp`; a WIRE NAME does not.** Trap 3
    says to confirm a rebuilt model with `grep -l <MARKER> obj_dir/*.cpp`, which is right
    for a debug print and wrong for a signal. After adding `AV_OFFSET_FINE`,
    `grep -c AV_OFFSET_FINE obj_dir/*.cpp` returned 0 in every file and that read as "the
    change never reached the binary" -- but Verilator had simply folded a one-bit wire into
    the expression that used it. Confirm RTL changes with a `$display` under a `DEBUG_*`
    guard, or by a behavioural probe, never by grepping for the name of a wire.

47. **A probe that stops before the event proves the probe stopped, not that nothing
    happened.** `DEBUG_SCROLL` printed `page0=0000 page1=0000` for a whole Woody Poco run
    and that read as "the scroll registers still are not latching" -- twice, once before
    the fix and once after. The run was `--stop-at-frame 2400`; the title's first scroll
    write is at frame **2443**. The frame numbers were already in the trace
    (`grep 'W \$d40[ef]' ` shows 191, 2443, 2526) and one look at them would have
    settled it. Before believing a flat probe, find the frame of the first event you are
    probing for and check it is inside the window.

48. **A half-finished fix can look exactly like a failed one.** The scroll path had two
    independent faults: the offset registers were unreachable through the MMR aperture,
    and `$D430` b2's unmasked offset was not implemented. Fixing only the routing moves
    Woody Poco from 58.73% agreement to **60.27%** -- indistinguishable from noise, and
    every reason to revert it. Both together give **97.30%**. This is trap 37 again from
    the other side: when a well-evidenced fix barely moves the number, look for a second
    fault in the same mechanism before backing the first one out.

49. **Now that scrolling works, a sweep agreement score on a scrolling title measures
    PHASE, not correctness.** `ref-sweep.sh` captures every blessed reference at a fixed
    20,000,000 steps and the core samples at a fixed frame; those are different points in
    machine time (~22 s against 33 s), which never mattered while nothing scrolled. After
    `c50a852` it matters a lot. Dragon Buster read as the worst regression in the sweep,
    74.90% -> 65.98%, with coverage and colour count unchanged (87.4% -> 87.5% against the
    reference's 87.6%; 16 colours against 15) -- the giveaway that the picture had *moved*
    rather than broken. Sampling our own render across frames 1800-2300 swings the score
    from 57.94% to 73.76% with no RTL change at all. Rendering the REFERENCE at 18M/20M/22M
    steps moves it the same way, and against the 22M reference the numbers inverted:

        our frame-2000 render   vs ref@18M   vs ref@20M   vs ref@22M
        pre-fix                   13.61%       74.90%       65.45%
        post-fix                  13.61%       65.98%       97.70%

    So the title improved by 32 points and the sweep reported it as a 9-point regression.
    **Fixed in the tooling since.** The sweep now takes a spread of screenshots per run
    (`SHOTLIST` in `av-sweep.sh`) and `score.py` scores the closest one, printing the frame
    that won; it also flags a row `shift?` when coverage and colour count match the
    reference but agreement does not, which is the signature of a picture that moved rather
    than broke. On the FM77AV demo the old single-frame scoring read 0.00% and the new one
    reads 94.60% at frame 1400, against a 94.20% baseline.

    The root cause is worth keeping even though the tool now absorbs it: the reference is
    frozen at 20,000,000 6809 steps (~22 s) and this sweep samples at a fixed frame
    (2000 = 33 s). Those only ever matched by accident, because the AV main CPU was clocked
    at the FM-8 rate and did roughly 22 s of work in 33 s of frames. `6a7030e` corrected the
    clock and a third of the set "regressed" without a pixel being wrong.

50. **Every reference render in this project was made with the disk WRITE
    PROTECTED, and the disks are not.** `tools/77avemu_headless.cpp:250` sets
    `param.fdImgWriteProtect[0] = true`. 77AVEMU itself reads the flag from the image --
    `DiskDrive::WriteProtected()` -> `DiskImage::WriteProtected(diskIdx)` ->
    `d77.GetDisk(idx)->IsWriteProtected()` -> `0 != header.writeProtected` where
    `header.writeProtected = d77Img[0x1a]` -- and every d77 in the collection checked so
    far has `0x1a` = `0x00`. So the reference is right given its input and the input is
    ours. It surfaces in `$FD18` bit 6, but only for the commands that report it:
    `MakeUpStatus` puts write-protect in bit 6 for Type I, Write Sector, Write Track and
    Force Interrupt, and nothing else. **Before treating any FDC status difference as a
    core bug, check what the harness told the reference.** Two useful controls: a title
    known to agree (Woody Poco's reference shows 30 reads of `$40` and 3 of `$44` where
    this core shows none, and it still agrees on 97.30% of pixels), and the image's own
    `0x1a` byte.

51. **The reference harness silently stopped building, and nobody noticed for six days.**
    77AVEMU removed `EnableDiffMouse`/`ToggleDiffMouse` from `Outside_World`, so the two
    `override` keywords on them in the harness's own `NullWorld` became hard errors and
    `tools/build_77avemu_headless.sh` failed against the current
    `~/Documents/development/77AVEMU` checkout. `refs/local/fm77av_headless` sat frozen at
    2026-08-17 and every reference render came from it. Fixed by dropping just those two
    keywords -- the base still declares them pure virtual on the vendored tree, so the file
    now compiles against both. (I first reported this as an error on
    `CreateSound`/`DeleteSound`; those lines only produce warnings. Read the diagnostic,
    not the nearest plausible line.)

    **Whenever the reference binary is rebuilt, prove it reproduces the old one before
    trusting a single number from it**: render a title you already have a blessed shot for
    and `cmp` the PNG. Both rebuilds here were byte-identical on Woody Poco, which is what
    made it safe to keep the blessed set rather than regenerate it.

52. **`iodiff.py` cannot open the traces this project now produces.** It holds both
    sides in memory and did not finish inside ten minutes on a 90 MB / 140 MB pair
    (~1.2 M main-CPU accesses each). `tools/seqdiff.py` streams both and returns in
    seconds. Its output has one rule: **only the first divergence or two are real.** The
    streams are compared positionally, so the moment one machine emits an access the other
    does not, every later row is offset by one -- the tell is "ours" row N starting to
    match "reference" row N-1. Fix the first difference, re-run, let the next appear. That
    loop walked Shounen Mike from `$FD01` to `$FD04` b2 to `$FD0B` to `$FD18` to `$FD00`
    to `$FD1F`, one readback at a time, and four of those six turned out to be real bugs.

53. **A readback that looks obviously wrong can be the only honest thing in the module.**
    `$FD00` b0 reads back inverted against the reference, CLKCTRL's own comment says the
    switch flip-flop *is* bit zero, and `SW2 = 1'b1` means "not FM-8". Every sign says
    flip it. Flipping it **blanks Luxsor disk 2** (81.8% coverage in 37 colours to 0.0% in
    1) and moves Valis disk 2. The reference's own code says why: it clears b0 when the
    main CPU is below 1.5 MHz, so b0 is a CPU-SPEED bit and this core really does run its
    AV main CPU at 1.2288 MHz. The register was telling the truth about a clock that is
    wrong elsewhere. **Ablate a two-part fix into its parts before believing either half**
    -- the undriven-bits half of the same edit is bit-identical on the gate.

54. **`T77SUM`'s tick counter starts at simulation time zero; its length counter starts
    when the tape does.** Comparing them looks like a clean "intended versus actual
    playback duration" measurement and is not one. On snake-apple it reports
    `summed_len=1763058 ticks_elapsed=2607085`, a 1.48x overrun that reads as ~20 ticks of
    dead time inserted between every pulse -- exactly the shape of a decoder stalling on
    an SDRAM prefetch, and exactly the bug you would go and "fix". It is not there. The
    run was 1500 frames with the motor on 69.8% of it, so 7.55 s -- about 838000 ticks --
    elapsed before the tape ever started, against a measured excess of 844027. The tape
    plays at the correct rate. Subtract the pre-motor-on time before reading anything into
    that pair, or gate `dbg_tick_count` on `start`.

55. **A register that flips a title between working and blank is not necessarily the
    register at fault.** Luxsor Disk 2 renders at 81.9% coverage with `$FD00` b0 = 0 and
    blanks with b0 = 1, which reads as "b0 is the bug" and cost a long investigation that
    eliminated `$FD1D` b5:2, `$FD05` BUSY-on-reset, the FDC and `$FD00` itself, one at a
    time, all correctly and all beside the point. b0 = 1 is *right* -- 77AVEMU builds the
    same value (`fm77avio.cpp:806`, b0 clear only when `mainCPU.state.freq < 1500000`) and
    with b0 = 1 this core's 300 `$FD00` reads match the reference exactly. What b0 actually
    does is pick a delay constant: the AV boot ROM at `$FF42` is `LDY #$00E0 / LDA <$00 /
    ASRA / BCS` with `DP=$FD` (set at `$FE0B`), so b0 = 1 keeps Y = 224 and b0 = 0 loads
    Y = $99 = 153, a 1.46x shorter wait. **b0 = 0 was not fixing anything; it was
    perturbing a race this core was losing for an unrelated reason** (the sub-CPU VRAM
    stall -- see docs/FM77AV.md). The tell that the framing was wrong was available from
    the start and was not read: with b0 = 1 the two machines run entirely different code,
    the reference in `$40xx-$44xx` and this core stuck in `$3Bxx`, which no single readback
    value explains.

56. **When two CPUs race, compare their progress against a shared yardstick, not against
    frames.** 77AVEMU has no frame counter and its `--trace-io` lines carry no timestamp, so
    "our sub CPU is 64 frames late" cannot be checked against it at all. What both machines
    do log is the main CPU's `$FDxx` accesses, in order, and `tools/seqdiff.py` already
    aligns the two streams on exactly that. So count **main-CPU I/O accesses before the
    landmark** on each side and compare those two integers. On Luxsor Disk 2 the sub's
    `$D40A` read at `$E13B` lands at access 17,844 on the reference and after 21,084 here,
    against a main-CPU poll at access 20,604 on both -- the reference wins the race by
    2,760, this core loses it. That is a measurement; "the sub looks slow" is not.
    `head -N ref.log | grep -c 'MAIN:'` is the whole technique.

57. **`vsim/sweep/results-av-*.tsv` is a record, not a baseline.** Those files are checked
    in and look exactly like the "before" numbers you want, and they are not: they were
    produced on whatever the core was that day, and the AV set has moved through the clock
    commit and several others since. Judging a change against them attributes every
    pre-existing regression to the change. That happened here, twice in one session: the
    sub-CPU VRAM arbitration change was read as blanking Kohakuiro no Yuigon (TSV 16857,
    measured 3790) and shredding Wizardry IV (TSV 17884, measured 12522), and BOTH are the
    state of HEAD without it -- Wizardry IV in fact renders a byte-identical 12522-byte PNG
    with the change and without. Build the "before" from the same tree, in the same
    session, with the same binary you are about to modify: `git stash push rtl/`, `make`,
    run, `git stash pop`. It costs one rebuild and it is the difference between a
    measurement and a story. Look at the picture, not the byte count.

    **And then do not over-read the picture.** Neither of those two was a regression at
    all. Kohakuiro paints its logo at frame 199 and fades it by 400, and 77AVEMU does the
    same and is black from 600 to 2400 -- the gate simply photographs 400 frames after the
    only thing the title draws. Wizardry IV at frame 400 is byte-identical to its previous
    blessed shot. Both moved because the 1.65x clock speed-up walked the attract animation
    past a FIXED shot frame, which is trap 49. So the sequence of errors was: compare
    against a stale record, conclude "my change broke it", discover it was already broken
    at HEAD, conclude "then it regressed earlier" -- and that was wrong too. The only way
    to settle a moving picture is to compare the SAME instant on both machines, which is
    what `vsim/sweep/ref-gate.py` and trap 58 exist for.
58. **"Frame N" is not the same instant on the two machines, and nothing corrected for it.**
    A vsim frame is a real raster frame off the core's video timing, 16 MHz over a
    1024 x 262 raster (`sim_main.cpp:73`) = **59.63740 Hz**. A 77AVEMU frame is exactly
    1/60 s of `vm->state.fm77avTime`. So

        reference_frame = vsim_frame * 60 * 1024 * 262 / 16000000 = vsim_frame * 1.00608

    exactly — +6 frames per 1000, i.e. 4 at the gate's 600, 12 at the sweep's 2000, 22 at
    3700. `tools/77avemu_headless.cpp` claimed in its own header that the numbers "mean the
    same thing here and in vsim"; they do not, and the claim is corrected in place. It only
    starts to bite on a title that is still moving at the shot frame, which is trap 49 all
    over again. `--stop-at-frame` on the harness plus `vsim/sweep/ref-gate.py` apply the
    conversion; do not re-derive it.

    A second trap sits behind the first: **the gate's shot frame is not its stop frame.**
    `run_tests.sh` runs to `FRAMES` (620) but photographs at `SHOT_AT = FRAMES - 20` (600).
    Converting 620 gives 624 and lands twenty frames after the picture being compared.

59. **`pkill -f Vemu` kills the OTHER agent's run too.** When a background agent is working
    the same repository -- a re-bless in a git worktree, say -- its simulator is the same
    binary name at a different path, and a broad `pkill -f 'obj_dir/Vemu'` to free the
    machine takes it out as well. That is what happened during the reference rebuild in
    this session: two AV rows were SIGTERMed mid-run and reported `MAIN-STALLED
    SUB-STALLED NO-SCREENSHOT` with `?` counters, and a `BLESS=1` would have written
    `0 0 0` into `counters.tsv` for them and called it a reference. From the victim's side
    it looks like an environment fault with no cause, which is an expensive thing to debug.
    Kill by PID, or match the full path, or give the run its own binary name -- `EXE=` on
    `run_tests.sh` is overridable for exactly this. And treat any row reporting STALLED
    with `?` counters as "something killed it", not as a core result.

60. **`--dump-shadow` is a HISTORY, not a snapshot, and on a banked machine that matters.**
    It records the last byte the CPU actually saw at each address, so a region read under
    one mapping keeps those bytes after the mapping changes. Compared against the
    reference's `FM77AV_CPU_DUMP` -- which IS a snapshot, via `NonDestructiveFetchByte`
    on the current mapping -- that makes stale regions look like hard differences. It
    cost an hour here: the sub CPU's whole vector table appeared corrupt, FIRQ reading
    `$1800` against the reference's `$FDAC` and IRQ `$0000` against `$E06E`, with only NMI
    matching, which reads as a devastating bug. `rtl/roms/subsys_m154.rom.mem` -- the ROM
    `SMEM.v` actually maps there -- contains the reference's table exactly. Nothing was
    wrong. Before believing any difference this dump shows in a ROM or banked region,
    read the ROM FILE. Agreement in the dump is strong evidence; disagreement is only a
    question.

61. **A bug that only a WARM reset can expose is invisible to every test you have.** The
    6809 core never masked NMI after reset -- `CPUSTATE_RESET` sets `s_nxt = $FFFD`, which
    satisfied the `s != s_nxt` release condition on the same cycle. On a cold boot nothing
    notices: the CPU finishes its init before any NMI source is running. It only bites
    when something resets a CPU while an NMI is already ticking, and on this machine the
    only thing that does that is the FM77AV's `$FD13` sub-system reset. Nothing in the
    gate performs one. When a fault appears only on real software and never on the tests,
    ask what STATE the tests never reach, not what register they never touch -- "reset
    while the rest of the machine is already running" is a state, and it is one a
    power-on test can never construct.

62. **When a CPU is wrecked, every conclusion downstream of it is worthless.** Luxsor's
    sub CPU walked a VRAM sled from frame 27, and its still-working timer handler kept
    notifying the main CPU, which pinned an FIRQ that stole the main CPU's timer IRQ 340
    frames later. From the main-CPU trace everything looked healthy: identical `$FDxx`
    accesses, identical 7,168 sector bytes, identical code. Hours went into `$FD00`, the
    FDC, the MMR and the loaded data, all of them downstream of a sub CPU that had been
    dead since frame 27. **Check that both CPUs are executing sane code before believing
    anything else.** `--pc-profile-sub`, or a glance at the sub's PC range and its stack
    pointer, would have cost a minute: an S of `$FFED` in ROM space is a dead giveaway and
    was visible in the very first sub trace taken.

63. **Two instruments and three window lengths will agree on nothing, and you will believe
    whichever you looked at last.** On Pro Yakyuu Fan disk A, within one session, a
    reconstructed read list (paired `$FD19`/`$FD1A` writes against `$80` commands), a
    `WDMATCH` list from a 120-frame run, and a sector-register probe from a 70-frame run
    each told a different story -- a skipped sector, a missing five-sector pass, and a
    perfectly contiguous register. Two of the three became published findings and both had
    to be retracted. None of them was a lie; they were answers to three different
    questions asked over three different intervals. **Before comparing anything against
    the reference, write down which instrument produced each side and over what window,
    and if they differ, fix that before reading the numbers.** A reconstruction is not an
    instrument: if the reference cannot produce the same measurement directly, add the
    print to `tools/77avemu_headless.cpp` instead of inferring one.

64. **`docs/` paraphrased a reference formula, dropped a term, and the RTL matched the
    paraphrase.** `docs/FM77AV.md` recorded the FM77AV TWR window as
    `(TWR_offset*256 + addr[9:0]) & $FFFF`; both references use the FULL CPU address, so
    the real base is `$7C00` higher and register 0 sits over physical `$07C00`.
    `AVMEM.v` implemented the doc. Reviewing the RTL against the doc therefore agreed,
    twice, and the window sat 31 KB low for as long as this core has had one. It is
    invisible unless a title both banks code into low RAM page 0 *and* uses the window --
    FM Sound Editor loads 4 KB at physical `$00000` and then walks a RAM-size probe
    through the window from `$00`, erasing it. **When an RTL block cites a doc in this
    repo rather than a `refs/` file:line, that citation is worth nothing. Re-derive it
    from `refs/`.** Two independent references agreeing (77AVEMU
    `memory/fm77avmemory.cpp:1239-1243` and CSP `fm7/mainmem_mmr.cpp:16-22`) is what
    settles a translation, not one doc sentence.

65. **`seqdiff.py` reporting a clean stream is not a working machine.** It collapses runs
    of identical accesses and deliberately does not compare counts, so a core that has
    stopped doing anything looks *identical* to one that is keeping up. On FM Sound
    Editor it printed one benign `$FD05` spin-count difference over 700 frames while the
    main CPU was in fact issuing **16** sub-system calls against the reference's **281**
    and had spent 414 frames doing nothing but 676,356 reads of one port. The tells were
    both outside the diff: the raw line counts (829,210 ours against 703,941, i.e. ours
    was *longer* and still said less) and
    `awk '$1>300' ours.log | awk '{print $2,$3,$6}' | sort | uniq -c` collapsing to a
    single row. **After a clean seqdiff, count the writes that represent work** -- sub
    calls, FDC commands, ALU triggers -- on both sides before believing it.

66. **Do not run anything else heavy while a sweep is timing itself, and do not read a
    DURATION as a symptom.** A 68-title sweep was left running while gates, 2000-frame
    single-title runs, VRAM dumps and multi-million-line traces went on beside it, and
    the workers from a previously-`pkill`ed sweep were never confirmed dead. Load average
    reached 18.5 on 16 cores. Two titles at the back of the queue -- both Ys II disks --
    took **five to seven hours** on a run that takes **six minutes** on a quiet machine,
    and sat at 100% CPU with the frame counter crawling. That was read as "the frame
    counter has stopped, the video timing has hung", then as "this is a regression I
    introduced, because Ys II completed in both previous sweeps". Neither was true.
    Three separate errors, and the order matters:
    * **The measurement was corrupted by its own environment.** Anything a long run says
      about time is worthless if the box was saturated. Check `uptime` and the process
      count before believing a duration.
    * **A regression was declared from one data point** -- "worked before, slow now" --
      without first reproducing it.
    * **The repro command was CHANGED rather than reproduced.** `--bootrom 0` and
      `--screenshot` were dropped from the failing invocation, and the conclusion "it
      hangs on HEAD" was drawn from a machine that had booted a different ROM bank. This
      is trap 62 inverted: there the danger is inheriting a flag you never examined, here
      it is dropping one. **Copy the failing command verbatim, including the flags that
      look irrelevant.**

67. **`compare-ref.py` and `ref-sweep.sh` disagree about what a reference picture IS, and
    nothing in the pipeline says so.** `ref-sweep.sh` renders by 6809 INSTRUCTION COUNT
    and its own header warns that this is "the WRONG unit the moment a render is going to
    be scored against a vsim screenshot"; `compare-ref.py` then scores exactly that way.
    Joining a sweep against `ref-sweep.sh` output therefore compares two different moments
    in a title and reports the difference as a verdict. Measured on the 68-title AV set,
    the same core shots scored two ways:

    | | by instruction count | frame-matched |
    |---|---|---|
    | CORE-BLANK | 4 | 5 |
    | CORE-WORSE | 2 | **0** |
    | MATCH | 22 | **27** |

    **Two of the six "actionable" rows were not bugs at all.** How Many Robot disk 0
    looked like 21% against 85% -- our frame 1100 is pixel-for-pixel the reference's
    title screen, and the canonical 1980 sample merely catches us further into the
    attract sequence. Gambler Jikochuushinha looked like 10% against 75% -- at the
    matched frame the reference shows the same border and the same portrait we draw,
    and the real defect is missing text.

    Use `sweep/ref-shots-at-frame.sh <outdir>` before `compare-ref.py`. It renders every
    title at `round(vsim_frame * 1.00608)` and drops the result in `ref-shots`. And note
    the join is on filename: the safe-name rule (`sweep_one.sh:9`) KEEPS `-`, so a
    retyped `tr` expression silently produces 40 NO-SHOT rows instead of an error.

68. **The sweep's safe-name is not unique, and a collision merges two different
    disks into one row.** `sweep_one.sh:9` keys on the disk's *basename* only,
    so two images with the same filename in different directories become one
    row -- and because `tr -c` maps every non-ASCII byte to `_`, any two
    Japanese-named disks of equal length collide as well. Measured on the FM-7
    half: 663 files, 401 distinct by content, and **3 safe-names hold two
    genuinely different disks each** (`Tritorn`, `Xevious`, and two Shift-JIS
    names that both flatten to `________.D77_`). The join is on filename alone,
    so the two machines can render *different disks* under one verdict.

    The sweep does not fail; it renders 38 pictures for 40 disks. That gap is
    the only symptom, and if you check for missing renders by name you find
    none -- the names are all present, two of them just mean two disks. Verify
    by content: `md5` the sampled paths and confirm one safe-name per hash.
    `run_tests.sh` already reports this class ("skipped 324 disk(s) whose
    basename was already taken").

    Related, and the reason `compare-ref.py` calls `.rstrip('_')`: `tr -c
    'A-Za-z0-9._-' '_'` converts the trailing **newline** too, so every safe
    name gains a trailing `_` -- `Thexder [b]` becomes `Thexder__b__`. A shell
    one-liner that pipes many names through one `tr` without re-emitting the
    newline joins them all into a single line, and a `sort -u | wc -l` on that
    reports **1**.

69. **`pgrep -fc` does not exist on macOS, and `|| echo 0` turns that into
    "nothing is running".** The count flag is a Linux procps extension; the BSD
    pgrep here prints a usage error and exits non-zero. Wrapped as
    `$(pgrep -fc Vemu 2>/dev/null || echo 0)` it reports a perfectly plausible
    **0 processes** for a job that is running fine. Combined with a log that was
    still buffered inside a `| tail`, that produced a confident "the gate is a
    dead run" for a gate which went on to pass 11/11, and a second gate was
    started on top of the first.

    Use `pgrep -f PATTERN | wc -l`, which works on both. More generally: a
    fallback on a *process* check is not a safety net, it is a way to convert a
    broken check into a plausible number. `|| echo 0` and `2>/dev/null` belong
    on things that are allowed to be absent, never on the measurement itself.

    Related and in the same hour: never read a still-running job's progress
    through `| tail` -- the pipe buffers until the writer exits, so a working
    job looks like one producing no output at all. Redirect to a file and tail
    the file.

70. **Coverage cannot tell a picture from a flat fill or from noise, so
    CORE-BLANK fires on titles that are broken everywhere.** All four of the
    first FM-7 cohort's "actionable" rows were this, and every one dissolved on
    being looked at:

    | title | what the reference actually shows |
    |---|---|
    | Argo | flat blue, **100% coverage / 1 colour**, byte-stable frames 200-3000, PC parked in the boot ROM at `$fe0b` |
    | Hot Dog `[b]` | flat white, 100% / 1 colour, stable from frame 600 |
    | Ishtar | coloured **noise**, 7 colours -- a garbage screen, not art |
    | GAME2 | 2 colours against our 1, a marginal difference |

    A flat fill is 100% covered and contains nothing; noise scores well on both
    coverage and colour count. `compare-ref.py` now rejects the flat-fill case
    (`colours <= 1 and coverage >= 99`) and reports a genuine colour shortfall
    as its own `CORE-MONO` verdict rather than as `MATCH`. Noise it cannot
    detect, and should not try to -- that is what looking at the picture is
    for.

    **The one-colour test alone is wrong**, and an early version of this check
    made exactly that mistake: a monochrome picture at 33% coverage is a real
    picture, and rejecting every 1-colour render turned two ordinary rows into
    CORE-BLANK. It is the *combination* of one colour and near-total coverage
    that means featureless.

    The reusable form: before triaging a CORE-BLANK, render the reference at
    several frames and check the PNG size actually changes. A byte-stable size
    across 200 -> 3000 frames means the reference is not running the title
    either, whatever its coverage says.

71. **A dead working directory reads as a core regression, not as a broken
    harness.** A long-running shell's cwd became inaccessible mid-session
    (`pwd: .: Operation not permitted`). `run_tests.sh` then reported
    **REGRESSION** with eight rows at an identical 5589 main / 5137-5158 sub /
    882 I/O and `RUNAWAY-INTO-IO` -- because vsim's `$readmem` ROM paths are
    relative, a failed load is a *warning*, and the machine runs away into
    `$fdxx` while still printing plausible counters. The same run passed
    `boot-basic`, `boot-dos1` and `av-kohakuiro`, so it looked like a partial,
    believable failure of an FDC change made minutes earlier.

    **The tell is identical counters across unrelated tests.** `basic-print`
    and `basic-keys` do not touch the FDC and cannot fail the same way as
    `boot-dos3` by coincidence. The second tell is in the same log: eight
    `awk: can't open file shots-ref/counters.tsv` lines, absent from the
    previous green run. A harness that cannot find its own reference data is
    not reporting on the core.

    Re-run from a verified directory before believing any regression. Here the
    clean re-run was 11/11 green with every counter byte-identical, including
    `boot-dos3` back at 11179/8774/0.

    Two ways this wasted more time than it needed to. `cd <abs> && cmd` is
    fine, but `pwd && cd <abs> && cmd` is not: the diagnostic runs *first*,
    fails from the dead directory, and short-circuits the `cd` that would have
    repaired it. And `ls` kept working throughout while `head`, `python3
    open()` and the Read tool all returned EPERM on the same file, so "the file
    is there" proved nothing about being able to read it.

72. **The FM-7 disk set contains FM77AV software, and sweeping it as an FM-7
    turns a real core bug into an unreadable one.** Cohort 03 scored
    `Ys - Ancient Ys Vanished Omen (1987)(Falcom)(JP)[a].d77` CORE-BLANK: ours
    blank, reference 40.2% / 7 colours. The reference picture is **noise**, and
    byte-identical (223,862 B) at frames 402/805/1207/1992 -- trap 70's own
    test. It is an **AV title**: under `--machine av` on both sides the
    reference draws its proper title screen (32.1%) and this core is still
    **blank (0.0%)**.

    So the mis-classification did not manufacture a false finding, it **hid a
    real one** behind a junk comparison. Both readings are wrong in opposite
    directions, which is why neither "the reference draws and we don't" nor
    "the reference is broken too" can be trusted until the machine flag is
    checked.

    **There is a positive detector, so this needs no eyeballs.** The run
    summary's `UNDECODED ports` line names the AV MMR registers when an AV
    title is run as an FM-7:

        Ys Omen [a]  UNDECODED ports : ... $80-$90 $93   <- $FD80-$FD93, AV MMR
        Penguin-kun  UNDECODED ports : $15 $16 $25 $27 $29 $2b   <- ordinary FM-7

    A cohort row that is CORE-BLANK *and* touches `$FD80`-`$FD93` under
    `--machine fm7` is an AV title in the FM-7 set. Re-run it as `av` before
    triaging it as anything. This is the same fault the handoff records for the
    28 multi-disk containers, whose first pass ran two FM77AV titles as FM-7 --
    it is a property of the disk set, not of those containers.

73. **A blank screen with a healthy CPU is a disk bug until the I/O profile says
    otherwise, and the port histogram finds it in one command.** Ys - Ancient Ys
    Vanished Omen `[a]` wrote ZERO of 98,304 VRAM bytes while running 21.9M
    instructions from RAM with the sub CPU executing downloaded code, display
    on, palette at the default identity. Everything about the machine looked
    well.

    What located it was counting ports on both sides over the same window:

        port           reference     ours
        $FD1F  status     177,304  762,388
        $FD18  cmd/stat       259   10,245
        $FD1A  sector          64    3,402
        $FD15  PSG         12,271       55

    Hammering the FDC 50x harder while never reaching the music is not a video
    symptom. `$FD18` then read `$10` -- RECORD NOT FOUND -- 5,633 times at
    `$0362`/`$03F2`, and the cause was the scan bound (`9b9af08`).

    **The generalisable part is the order.** VRAM dump first: all-zero excludes
    the raster, the palette and the page-select outright, and costs one run.
    Then the port histogram, which is one `grep -oE | sort | uniq -c` per side
    and points at the subsystem. Only then the instruction-level trace. Reading
    `seqdiff.py` first would have been worse here: its top divergence was a
    write-protect difference at `$FD18` (`$44` against `$04`) that is real,
    harmless, and NOT the bug -- the reference reports `$44` at `$516E` too.
    A first divergence is the first difference, not the important one.

74. **An invalid `--machine` value is a printf, not an exit, so a whole sweep
    runs the wrong machine and says nothing.** `sim_main.cpp:854-858` accepts
    `fm7` or `fm77av`; anything else prints `Error: --machine needs fm7 or
    fm77av` and leaves `opt_machine_av` at its default, **FM-7**. `sweep_one.sh`
    sends stdout to a temp file it discards, so the error is never seen.

    `MACHINE=av ./sweep-list.sh ...` therefore produces a complete, plausible,
    entirely FM-7 result set. 16 runs were wasted this way. The confusion is
    real and built in: **`ref-shots-at-frame.sh` takes `av`, the simulator takes
    `fm77av`** — the reference and the core use different names for the same
    machine, and the pair is normally written on adjacent lines:

        MACHINE=fm77av ./sweep-list.sh      <- the CORE:      fm7 | fm77av
        ./ref-shots-at-frame.sh ... fm7     <- the REFERENCE: fm7 | av

    `av-sweep.sh:65` gets this right (`export MACHINE=fm77av`); copying the
    machine name from the reference invocation is what gets it wrong.

    **The tell is in the data, and it is the same tell as trap 71:** identical
    results across configurations that cannot legitimately agree. All 16 titles
    returned byte-identical PNG sizes on "two machines" that boot different ROM
    sets. Two machines agreeing to the byte on every title is not a result, it
    is one machine measured twice.

75. **The sweep's single 1980 sample is a verdict generator with a measured
    false-positive rate: three of four candidates from one cohort were sampling
    artifacts.** Not a theoretical risk — this is what it cost:

    | title | verdict at 1980 | truth |
    |---|---|---|
    | Ys II - The Final Chapter | CORE-BLANK | draws **94.5%** at 1200/1400; animated intro, 1980 falls between scenes |
    | Penguin-kun Wars | CORE-WORSE | draws its title at 900 and advances to its menu; the REFERENCE is stuck |
    | Daisenryaku FM | "renders nothing" | draws its title art at 400, erases it by 600 |
    | Ys Omen `[a]` | CORE-BLANK | **real** — blank at all nine samples |

    **The discriminator is persistence, not the value at any one frame.** The
    real bug was blank at every sample and had a persistent I/O signature —
    4,242 retried reads, zero VRAM writes. The three artifacts each had a frame
    at which the picture was right.

    The same error has a second form, in aggregates rather than screenshots.
    Ys II's `$FD18` count is **37x** the reference's, which reads as an FDC
    retry storm; the excess is confined to frames 11-16, the loader waiting out
    the mount-time scan (`ready0 = mounted & ~scanning`). Excluding it, the FDC
    matches. **A ratio over a whole run hides its own time distribution — plot
    the count per frame before believing it.**

    Cheapest defence, and it is nearly free: `SHOTLIST=600,1000,1400,1980`
    on the sweep. `sweep_one.sh` still copies the last entry to the canonical
    PNG, so every downstream tool is unchanged.

And one more: **a null result from one title says nothing about a register, only about that
title** — Ys reads `$fd04` once in 900 frames; OS-9 drives the same path 578 times.

---

## 6. Working practices

- **Do not assume MAME is correct.** It is the most readable I/O map, but its FM-7 driver is
  unreliable and its VRAM plane order is the odd one out (section 1). CSP is the primary
  authority; 77AVEMU is the tiebreaker.
- **`run_tests.sh` judges itself.** It compares screenshots *and* counters against `shots-ref/`
  and exits non-zero on a difference. Accept an intentional change with `BLESS=1 ./run_tests.sh`,
  and say why in the same commit. Run it before and after any RTL change; all 8 rows should be
  unchanged unless you meant to change them.
- **Instrument the decision, not its inputs** (trap 6); **read back what you wrote** (trap 10);
  **run the no-flag case once** (trap 14).
- **One file per commit** for anything touching clocking or reset, so hardware can bisect
  (section 3). The CRLF list, `files.qip` discipline and BSD-awk caveat in section 4 apply to
  every scripted edit.
