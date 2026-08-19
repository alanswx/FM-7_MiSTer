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

### Worked example: 77AVEMU's sector reads are off by one (we are right)

Recorded so nobody "fixes" the FDC to match the tiebreaker. On the original
Fujitsu FM77AV demo disk, the boot loader's first sector read at `pc=$521f`
yields:

| | first bytes returned |
|---|---|
| this core | `1A 50 86 FD 1F 8B 30 8D ...` |
| 77AVEMU   | `FF 1A 50 86 FD 1F 8B 30 ...` |

Both read exactly 256 times. Reading the `.d77` directly settles it: track 0
sector 1 is `1A 50 86 FD 1F 8B 30 8D 00 42 10 8E 01 00 86 02`. **This core is
correct**; 77AVEMU emits a leading `$FF` -- the data register's stale content
from the loader's own `$FD1B <- $FF` scratch test at `$5190` -- and so drops the
sector's last byte.

Its `$FD18` Type I status bit 6 is wrong on the same disk too: it reports
write-protect set (`$44` where we return `$04`) while the image's write-protect
byte at offset `$1A` is `$00`.

Neither artifact stops 77AVEMU rendering the disk, so neither is a lead. Both
look exactly like a first-byte bug on *our* side if you diff the traces without
checking the image — which is the whole point of writing them down.

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
subsequent track loads. The core reaches the Japanese Daisenryaku title screen
at frame 621. The narrow `$02`/`$42`/`$52` carry-dependent aliases and `$4e`
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
