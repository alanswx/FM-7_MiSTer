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

## Handoff — read this first

**State.** The core boots F-BASIC (cassette and disk), runs games from `.d77`,
and boots OS-9's kernel. **62 of the 221 FM-7 disk images in the Neo Kobe
collection render a real screen** (P4-16), up from 33 before P4-15. The FDC, the main/sub handshake and
its BUSY completion flag, the shared-RAM aperture, the full keyboard (both
routings, shift/ctrl/graph/kana/break) and the boot-ROM bank select are all
verified working against the reference emulators. What remains is mostly
per-title software archaeology plus a handful of scoped RTL items.

The single biggest remaining bucket is **18 FM-7 images that are primary, good
dumps, run at a healthy rate and still draw nothing** (P4-16). That was 46
before P4-15 fixed `$8000-$fbff` returning zero on every read whenever the
`$fd0f` RAM window was open — the window games load into.

**Subtract the disks that should not boot before counting anything.** Of the 77
blank-at-a-healthy-rate images, 22 have a boot sector that cannot boot (13
**deliberately halt** with `ORCC #$50 / STA $fd03 / BRA *`, 9 are a single
repeated byte — $e5 blank-format fill, $00 or $ff), 27 are **secondary disks of
multi-disk sets**, and 10 more are marked `[b]`, a known-bad dump.
`vsim/sweep/bootsector.py` identifies the boot-sector cases straight from the
image. Quoting 77, or the older 108, badly overstates the failure rate — and see
the warning in P4-16 about the one filter that overstates it in the other
direction.

**Build and run.**

```sh
cd vsim && make                 # then ./obj_dir/Vemu --help
./run_tests.sh                  # 8-row regression; screenshots land in shots/
```

`run_tests.sh` is the guard rail — run it before and after any RTL change and
diff the numbers, not just the screenshots. All 8 rows should be unchanged
unless you meant to change them.

**Test images.** `software/Neo Kobe - Fujitsu FM-7 (2016-02-25).zip` holds 630
`.7z` archives, of which **195 are `[FD]` floppy sets** unpacking to **350 disk
images** (221 FM-7, 129 FM77AV). Extract with a *bracket-free* pattern — `[FD]`
is a shell/unzip character class, so `*[FD]*.7z` silently matches the wrong
entries:

```sh
unzip -o -j -q "$Z" "*Hydlide II*FD*.7z" -d . && 7z x -y -o. *.7z
```

For the whole collection, extract every `.7z` and filter by name afterwards
rather than trying to glob the brackets — that is what the sweep script does.

**Open work, in the order I would take it:**

| | where | why |
|---|---|---|
| **P4-16** | The 21 remaining blanks | Primary, good-dump disks that run healthily and draw nothing. The honest target, already stripped of halt-stubs, secondary disks and bad dumps. |
| **P4-8** | Ys: the play field is black | **Not a deadlock — that framing was wrong and is corrected in the P4-8 section.** Ys boots unaided, draws its title screen with no key at all, and advances into the game on SPACE: border, `H.P 020/020`, `EXP`, `GOLD` and both gauges all render. Only the play area inside the border is black. The `$1113` (`TST $ffe5` / `TST $28e9`) lead was traced on the broken core, so **re-derive it before chasing it.** |
| **P4-7** | CHAN.POP wild jump | Last sane PC in `$75xx`. Re-check against P4-15 first: it is the same *class* as the runaways that fix cured, and it may simply be gone. |
| **P4-16** | The 8 remaining crashes | A different set from P4-14's fifteen. Seven still show `sub` = exactly 8721; three are `(Disk 1)` of multi-disk sets. |
| **P4-3** | PSG `sel_n_i` pitch | Needs a human ear, cannot be settled in sim. |
| | FM-77AV | `FM77AV_PLAN.md` — 12 phases, not ROM-blocked, binding constraint is block RAM at ~76%. |
| | second drive, 2DD, multi-disk `.d88` | Unstarted. Scoped in P4-1. |
| | `$fd04` bit 2 | Carries BUSY here; no reference puts it there. Recorded in P3-2, not acted on. |

### Measurement traps — every one of these cost real time

More bugs in this project were *mis-diagnosed* than were hard to fix. All of
these produced a confident wrong answer at least once:

1. **A trace that hits `--trace-max` is truncated from the START of the run.**
   If the line count equals the cap, you are looking at the earliest frames, not
   the ones you asked for. Always check the frame range in the output.
2. **`--trace-cpu` prints one instruction late.** The log therefore does *not*
   contain the instruction that stopped the CPU. For "why did execution end",
   read the CPU state (`--vcd`), not the disassembly.
3. **`DEBUG_*` and `TRACE` become `+define+` args baked in when Verilator runs.**
   `make DEBUG_FDC=1` after a plain `make` relinks the old model with the old
   defines — clean build, clean run, no output, indistinguishable from a real
   null result. `touch` a file in the target module first and verify with
   `grep -l <MARKER> obj_dir/*.cpp`.
4. **Check frame numbers line up before concluding a value did not propagate.**
   Comparing a sub-CPU read at frame 1074 against a main-CPU write at frame 1076
   "proves" a lost write that was never lost.
5. **A low VRAM write count proves nothing.** Thexder displays a full title
   screen while writing *zero* VRAM bytes — the image is already there. Only a
   cumulative count from reset, with the data values checked, means anything.
6. **Reconstructing state from a bus log is not the same as asking the RTL.** A
   Python decoder inferring `(track, side, sector)` from `$fd18-$fd1b` traffic
   reported sectors returning the wrong side's data; a `$display` in the RTL's
   own match arm showed all 19 matches exact. Instrument the decision, not its
   inputs.
7. **Triage a sweep by `main/frame`, not by screenshot.** Healthy titles sit at
   4400-5800. Low rate + blank screen is a crash (expect a `CWAI` in page zero);
   low rate + content is a title idling at a screen it already drew; normal rate
   + blank is something else again. A screenshot cannot tell these apart.
8. **A proxy metric can stay flat while the bug is being fixed.** P4-13 was
   framed around "the main writes 6891 payload bytes and the sub reads 5833, a
   15% shortfall". The fix took that to 5878/6891 — 84.6% to 85.3%, near enough
   nothing — while the screen went from unreadable to correct. Commands vary in
   length, so the sub never had to read every byte of every block and the ratio
   was never measuring what it looked like it measured. Check the *outcome*, and
   only trust a proxy you have shown tracks it.
9. **`vsim` must be run from `vsim/`, and running it from anywhere else fails
   *silently and plausibly*.** The Verilog loads every ROM with `$readmem` on
   the relative path `./roms/...`. From another directory Verilator prints
   `$readmem file not found` as a **warning**, not an error; the ROMs come up
   empty, the machine runs away into the `$fdxx` window, and the run still
   completes, still writes a screenshot, and still reports plausible instruction
   counts. A 350-title sweep driven from the repo root returned **3355 main /
   2923 sub and a blank 3790-byte PNG for every single title** — which reads as
   a uniform "nothing boots on this core" result rather than as a broken
   harness, and is far more dangerous than a crash. Any script driving the
   simulator must `cd` to `vsim/` and check its log for `readmem file not
   found`.
10. **A verified WRITE path says nothing about the READ path.** P4-15 sat
    undiscovered through several investigations because `$8000-$fbff` accepted
    every write perfectly and returned zeros on read. P4-1j recorded Ys doing
    "a clean contiguous 24 KB program load, no gaps, no double-writes ... this
    whole path is working" — which was true, and useless. A memory that stores
    and returns zeros does not look like broken memory; it looks like a software
    bug in whatever ran next. **Read back what you wrote.**
11. **`--trace-mem` only logs `$fdxx`, whatever its help text says.** It claims
    "every main-CPU bus cycle in that hex address range", but
    `--trace-mem 0100-0110` across the boot-sector load returns *zero lines*.
    That reads as "this region is never touched", which is a very convincing
    lie. For RAM use `--dump-shadow`, which records both directions
    (`shadow_m.mem[addr] = rw ? din : dout`) — so a value in it is whichever
    access happened last, and comparing a written value against a later read is
    exactly how P4-15 was pinned down.
12. **`grep` a trace for a hex address and you will match cycle counters.**
   `grep -c d404` over a `--trace-mem-sub` log reports a healthy count of lines
   like `cycles 86d4041 reading D0` — the address appears as a substring of a
   cycle number. It reads exactly like "the port is being used". Anchor on the
   trace format instead: `grep -cE 'smem .* \$d404'`. Related: the main-CPU
   trace prints `mem` followed by **two** spaces, so `grep ' mem W '` silently
   matches nothing and looks like a clean null result.
13. **`| tail -N` and `| head -N` will quietly delete the evidence.** Trace lines
   come out *before* the end-of-run summary, so `--trace-mem ... | tail -40`
   shows the summary and none of the trace — and it looks exactly like "the
   access never happened". The mirror image also bit: a port histogram printed
   with `head -15` hid `$fd02`, whose two writes ranked 16th, and that produced a
   confident *retraction* of a correct finding. Both directions cost a wrong
   conclusion in one session. Write traces to a file and query the file.
14. **An inherited repro flag becomes an unexamined premise.** `--key
   '820:@SPACE'` rode along in every Ys command for the whole investigation
   because it was in the original repro line. It was never the thing breaking a
   deadlock — Ys renders its title screen with no key at all, and the flag simply
   advances past it. Run the no-flag case once before characterising behaviour.
15. **A stale reference is worse than no reference.** `shots-ref/` sat three
   months behind the core while `run_tests.sh` compared nothing against it and
   still exited 0. "All 8 rows pass" meant only "eight sims produced plausible
   instruction rates". If a suite cannot fail, it is not evidence.

### Working practices

- **Do not assume MAME is correct.** It is the most readable I/O map, but its
  FM-7 driver is unreliable and its VRAM plane order is the odd one out (P1-5).
  CSP is the primary authority; 77AVEMU is the tiebreaker.
- **These files are CRLF** and must stay that way: `rtl/FLAGS.v`, `rtl/MFD.v`,
  `rtl/SRAM.v`, `rtl/ROMS.v`, `rtl/CLKCTRL.v`, `files.qip`, `FM-7_MiSTer.qsf`.
  Check with `file` after any scripted edit.
- **`files.qip` is the canonical Quartus file list**, not the `.qsf` — the qsf
  sources it, and the IDE re-injects a duplicate list whenever the project is
  opened in the GUI. Delete that when it reappears (P4-6).
- **macOS `awk` is BSD awk**, not gawk: no `asort()`, no 3-arg `match()`. A
  script using them fails silently if stderr is discarded.
- **`--vcd` exists** (`make clean && make TRACE=1`) and is windowed by
  `--trace-from`/`--trace-until`. Two frames is ~700 MB, so always window it. It
  has settled two questions that several rounds of `$display` could not — reach
  for it after the second failed printf, not the fifth.
- **`run_tests.sh` now judges itself.** It compares screenshots *and* counters
  against `shots-ref/` and exits non-zero on a difference. Accept an intentional
  change with `BLESS=1 ./run_tests.sh`, and say why here in the same commit.
- **`--trace-from`, `--trace-until` and `--trace-max` do NOT apply to
  `--trace-io`.** It logs the whole run regardless, so a `--trace-io` log is
  never evidence about a particular window unless you filter on the frame column
  yourself (`awk '$1>=1400'`). They *do* work for `--trace-mem`/`--trace-mem-sub`.

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
aperture, the main/sub halt handshake and its BUSY completion flag; the raster,
character generator and palette; the `$fd03` interrupt cause register; and the
keyboard in full — unshifted, shift, ctrl, graph, kana and the break key.

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

### What renders today

**33 of the 221 FM-7 disk images in the collection render a real screen** — see
P4-14 for the full table. The ones worth calling out:

| title | what you get |
|---|---|
| **Thexder** (Game Arts) | full title artwork and credit line. Richest screen in the collection |
| **Hydlide II** (T&E Soft) | logo, ornate border, story panel, LIFE/STR/MAGIC status bar, and **the story text now reads correctly** (was P4-13) |
| **Ys** (Falcom) | **title screen with no key at all**; `--key '820:@SPACE'` advances into the game: ornate border, `H.P 020/020`, `EXP 00000/00200`, `GOLD 01000`, PLAYER and ENEMY gauges. Play area still black -- P4-8 |
| **Archon** (BPS) | full title screen -- logo, artwork, border |
| **Mugen no Shinzou II** | title artwork with kanji logo |
| **The Knight of Wonderland** | HummingBird Soft logo and artwork |
| **Dezeni Land** (Hudson) | HUDSON SOFT splash |
| **The Castle & Castle Excellent** | clean menu, colour, Japanese katakana |
| **`[Utility]` File Master FM** | seven dated revisions, all render |
| **`[OS]` F-BASIC v3.0 L10** (Fujitsu) | official first-party disk, boots Disk BASIC |
| `[Compilation]` Game 013 | Disk BASIC to `Ready`; `FILES` lists the directory |
| **`[OS]` OS-9 Level 1** | **boots to an interactive shell** with `--bootrom 2`; `dir` lists the directory (P4-10) |
| Voodoo Castle, The Palms, Mission Impossible, Strange Odyssey, The Count, DNA, Genmu no Shiro, Pop Lemon, Lovely Gal, Cream Lemon, Templo del Sol, Team AB music disks | title or menu screens |

### Fixes this session

| | |
|---|---|
| `9fc762b` | **The sub BUSY flag was inverted against both references.** `FLAGS.v` held it asynchronously *cleared* for the whole time the sub was halted; MAME and CSP both *set* it on the halt request and hold it until the sub reads `$d40a`. That is the completion handshake, so the main CPU saw "sub idle" the instant it released a halt and could overwrite command blocks the sub had not consumed. **Hydlide II's story text is now legible** — see P4-13. |
| `c72a312` | `$fd04`'s attention latch was held cleared except during its own read, so the sub's `$d404` attention never reached the main CPU as a FIRQ, and bit 0 read a constant "no interrupt" (P3-2). Correctness only — nothing measured uses it. |
| `6aad4a8` | CTRL / GRAPH / KANA keyboard tables from CSP, and the break key wired through (P2-1, P2-3). `vsim` gained `--key '400:@CTRL+ac'` modifier chords, without which the tables cannot be tested at all. |
| `5ac7684` | `ROMS.v`'s boot-ROM/RAM switch was a flip-flop **clocked by reset being asserted**, so it depended on a power-up edge the FPGA build never guaranteed (P0-2). Now a plain synchronous reset-and-load. Cannot be proved in sim — `vsim` manufactures that exact edge — so the evidence is "no regression" plus the argument. |
| `47abd60` | The keypad `/` is a different FM-7 key from the main `/` and takes a different GRAPH code. Found by `vsim/sweep/check_kbd.py` diffing the tables against CSP; all 202 entries now match exactly (P2-1). |
| `684c2cf` | **Kanji ROM at `$fd20-$fd23` (P3-3).** Never actually blocked — `refs/fm7.zip` had `kanji.rom` (crc32 `62402ac9`, matching MAME and *not* a `BAD_DUMP`) all along, just never extracted. New `rtl/KANJI.v` plus the decode in `MDECODE.v`. Verified from BASIC at two addresses. |
| `ada5c37` | **`$8000-$fbff` read as ZERO whenever the `$fd0f` RAM window was open (P4-15).** The biggest bug found so far. `core.v`'s read mux had no arm for the RAM case, so 31 KB — the window games load into — returned `$00` on every read. **Writes always worked**, which is why every prior investigation that checked the write path pronounced it healthy. Xevious, Tritorn and Hokuto no Ken go from dead runaways to rendering. |
| `ab290b7` | FDC dropped one of two back-to-back register writes. The core edge-detects `wr` *as it samples it*, so a strobe that goes low and high between two `ce` ticks is never an edge. Ys sets track+sector with one 16-bit store and lost every sector write. |
| `9026de8` | `files.qip` was missing `rtl/wd1793.sv` — **the Quartus build could not have compiled the FDC**. |
| `a5a9b27` | `(int)main_time` overflowed INT_MAX at frame ~2666, so `BeforeEval`'s `cycles < 2000` guard went permanently true and the block device silently stopped serving. Invalidated every long run. |
| `f92d112` | `$fd03` bit 2 read the opposite sense to its three neighbours, costing keyboard input to any game with its own ISR. |
| `bb25cba` | M152 bank select — the OSD's four boot-ROM settings are now four real banks. Boots OS-9. Also found `boot_bas.rom` is a **bad dump** whose last two bytes are a corrupt reset vector. |
| `e8af46c` | Windowed VCD tracing — the Makefile advertised `TRACE=1` but no VCD code existed. |

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

**`rtl/wd1793_dpram.v` is now in `files.qip`.** Its `dpram` module wraps
Cyclone V `altsyncram` and implements the 2048 x 56-bit EDSK/D77 sector index.
Quartus 17 could not infer that table from the two parser write paths and instead
created 111,552 flip-flops. The wrapper has a behavioral `VERILATOR` branch so
the same WD1793 instantiation remains usable in simulation.

Verified both tops connect every one of `core`'s 28 ports, with none left over.

### P4-10 [FIXED] OS-9 reaches a working shell — it was P4-15, not the keyboard

**OS-9 Level 1 now boots to an interactive shell and takes commands:**

```
* OS-9 Kernel Started !
* System Module Loading Completed !

      ****  Welcome to OS-9 Level 1 System ****
        [  OS-9 レベル 1  Version 1.0   ]

  yy/mm/dd hh:mm:ss
Time ?
Shell
OS9:dir
   directory of .  00:00:00
OS9Boot    SYS        DEFS       NEAF
asm3-u     cmds       startup    Bassou
CMDS3u     chgboot    BASIC_WORK SFORM

OS9:
```

```sh
cd vsim && ./obj_dir/Vemu --headless --bootrom 2 \
    --disk "[OS] OS-9 Level 1 (Disk 1) {boot DOS mode}.d77" \
    --key '1000:@RETURN' --key '1100:dir' --key '1250:@RETURN' \
    --stop-at-frame 1500 --screenshot 1480
```

**The cause was P4-15**, the `$8000-$fbff` read hole. OS-9's console came up as
soon as reads from the RAM window returned real data; input was never the
problem.

> **I got this wrong first and the mistake is instructive.** I found OS-9's
> console working right after changing the `$fd02` keyboard-route reset value
> and attributed the fix to it. The "before" I compared against was a *different
> command* — no keypresses, screenshot at frame 1380 — against an "after" with
> keys at 1000-1250 and a screenshot at 1480. Two variables moved at once.
> Rebuilding with the old reset value and running the **identical** command gives
> **the identical result**:
>
> | | png |
> |---|---|
> | pre-P4-15, no keys, frame 1380 | 4380 (kernel banner only) |
> | post-P4-15, no keys, frame 1480 | **5829** (the shell comes up) |
> | post-P4-15, with keys, frame 1480 | **7662** (shell + `dir` output) |
> | either keyboard reset value | **no difference at all** |
>
> OS-9 writes `$fd02 <- $00` then `$fd02 <- $01` itself, so it selects the main
> route and the reset value never applied to it — which also contradicts the
> earlier note in this entry that "OS-9 never writes `$fd02`". That measurement
> came from a run I killed part-way and had flagged as needing re-checking. It
> did.
>
> **A/B one variable, against the same command.**

**A separate, real defect found while chasing this**, kept because both
references agree even though it fixes nothing measurable: `KEYBOARD.v` reset
`m77` to `3'b111`, routing the keyboard to the MAIN CPU, and both references
reset it to the SUB.

| | |
|---|---|
| **MAME** | `m_irq_mask = 0x00` at reset (`fm7.cpp:1792`), and delivery is `if(m_irq_mask & IRQ_FLAG_KEY) main_irq_set_flag(...); else m_sub->set_input_line(M6809_FIRQ_LINE, ASSERT_LINE);` (`:1120-1126`). Mask 0 takes the **else** branch. |
| **CSP** | `reset()` sets `irqmask_keyboard = true` (`fm7_mainio.cpp:268`), cleared only when `$fd02` bit 0 is written **set** (`:500-503`). The same flag drives the sub as `SIG_FM7_SUB_KEY_MASK` with `firq_mask = !flag`, so the reset state leaves the sub's FIRQ **enabled**. |

It can only bite a title that **never writes `$fd02`**, because anything that
does overrides the reset value immediately. **No such title has been found.**
All 18 of P4-16's remaining blanks were re-run against the change and not one
moved, and OS-9 turned out to write `$fd02` after all. So this is a
correctness-only fix, in the same category as P3-2. The sub monitor ROM's input
wait at `$fd76` is

```
$fd76  ORCC  #$40        mask FIRQ
$fd78  LDB   <$04        $d004
$fd7a  BNE   $fd86
$fd7c  BCC   $fd92
$fd7e  LDB   <$00        $d000
$fd80  BNE   $fd92
$fd82  ANDCC #$bf        unmask FIRQ
$fd84  BRA   $fd76
```

— it spins until its FIRQ handler puts a byte in `$d000`/`$d004`. Route the
keyboard to the main CPU and that byte never arrives.

Only bit 0 was changed. `LPMASKn` (`m77[1]`) and `TMMASK` (`m77[2]`) keep their
old reset value, because nothing has been measured about those and the timer is
load-bearing.

`run_tests.sh` all 8 rows byte-identical, including the three keyboard tests —
F-BASIC writes `$fd02` itself, so it is unaffected either way.

> **`keyboard: n strobes` counts the SUB route only** (`stat_kstrobes` edges on
> `dbg_kstroben`, i.e. `KSTROBEn`). That is not a bug, but it is easy to
> misread: the OS-9 run reports `0 strobes` while visibly executing a typed
> `dir`, because OS-9 routes the keyboard to the *main* CPU. A zero there means
> "nothing arrived on the sub route", not "the keyboard is dead".

**The route change fixed no title.** Penguin-kun Wars, Fairie's Residence and
Yellow Lemon still sit blank at 3790 despite sharing the `$fd76` loop, and all
18 of P4-16's blanks are unmoved. They stall for a different reason — see the
investigation under P4-16, which did not reach a cause but did eliminate
several.

### P4-10-orig [superseded] OS-9 boots its kernel, then makes no visible progress

With P3-6b fixed, `--bootrom 2` boots OS-9 as far as

```
* OS-9 Kernel Started !
```

printed twice, then the screen stops changing. Both CPUs stay live (5277 main /
5843 sub per frame).

**It is not a deadlock, and the sub/main handshake is working.** An earlier
version of this entry claimed a stuck `BUSY` flag; that was wrong, and the way
it was wrong is worth recording because it is the fourth instance of the same
mistake this session.

- The `$d40a` busy handshake is **still running at frame 2387** of a 2400-frame
  run -- 1218 accesses, the sub dispatching (`write $d40a` at `$e14a`) and
  clearing (`read` at `$e13b`) throughout. It only looked stuck because the first
  trace ended at its own `--stop-at-frame`, so the "last" access was an artefact
  of the window, not a hang.
- Main is not spinning either. The PC histogram over frames 2000-2010 is
  dominated by `$0424`/`$0427` (27090 each) but also contains `$0368`-`$036e`
  (169), `$040b`-`$0441` (34/13) and `$0358` (8). So the wait at

  ```
  $0424  LDA  $fd05
  $0427  BMI  $0424
  ```

  **does** fall through regularly; it is a poll that succeeds, not a block.

So OS-9 is in a steady state where the kernel runs and polls the sub normally
but never reaches a shell. That is a much weaker signal than a hang, and it is
not obviously an emulation fault at all -- it may simply need something the boot
is not being given (a second disk, a console device, a keypress).

**Both cheap options tried; neither helps.**

- **Disk 2** boots the same banner and briefly shows a **cursor block** on the
  third line, so a console does come up. Disk 1 never shows one.
- **Keys do not reach it.** RETURN, `dir`, RETURN fed between frames 1400 and
  2300 change nothing on either disk -- the screen is byte-identical at 1600,
  2000 and 2580 -- and the cursor is transient rather than a steady prompt.

So the kernel starts, the sub handshake runs, a console appears momentarily, and
input never lands. Note this is *not* the P1-6 class of bug: keyboard delivery to
both the main (`$fd03` bit 0 -> `$fd01`) and the sub (`$d401` via FIRQ) is
verified working by other titles (P4-9). OS-9 installs its own drivers, so the
question is which route its console driver expects and what it polls.

**[UPDATED after the BUSY fix]** With `9fc762b` (P4-13) the picture improves
slightly but does not resolve: **disk 1 now shows a cursor block on the third
line**, where before only disk 2 did and disk 1 never did. Rates are 5269 main /
5975 sub per frame at frame 1380, and the banner is still printed twice with no
shell. So the console comes up more completely than it did, and the remaining
problem is still input.

Also measured, and it narrows the question usefully: **OS-9 never writes `$fd02`
at all** over 1500 frames, so it never selects a keyboard route and simply
inherits whatever the boot ROM left. Worth confirming which that is and whether
the console driver agrees with it. *(This one measurement was taken from a run
that was later killed; the `$fd02` half had completed and printed no matches,
but re-run it before building on it.)*

Next: find what `$0368`-`$036e` does between the `$fd05` polls -- that is the
only main-CPU code running besides the wait, so the console loop is in there --
and check whether OS-9 ever touches `$fd00`/`$fd01`/`$fd02` at all after the
kernel starts.

### P4-11 [CLOSED — not a core bug] Arion crashes into a CWAI

Picked out of the P4-9 sweep by its instruction rate, and **the triage signal is
the part worth keeping**: every other title runs the main CPU at 4400-5800
instructions/frame; Arion reports 1087 with a healthy sub. That means "ran
normally then stopped", which is far sharper than a blank screen. **Sort a sweep
by main/frame, not by screenshot.**

It executes zero main instructions from frame 151 onward, after running off into
page zero and executing data as instructions (`FCB $61`, `FCB $01`, last printed
`NEG <$90` at frame 150).

**Resolved by waveform, and it is Arion's own crash, not ours.** A `--vcd` over
frames 149-151 shows the main CPU's state register ending in

```
CpuState 108 (CPUSTATE_CWAI) -> 109 (CWAI_DONTCARE1) -> 83 (PSH_ACTION) -> 110 (CWAI_POST)
```

and staying at 110, with `nHALT=1` and `nRESET=1` throughout. So the core is
**correctly executing a `CWAI`** -- clear CC bits and wait for interrupt -- which
it reached among the garbage it was executing. A `CWAI` whose operand leaves I
and F set waits forever by definition, which is exactly right behaviour.

**Two things I got wrong on the way, both worth remembering:**

1. *"A 6809 that is not halted, not waiting and not in a stop state stops
   fetching -- a core bug that would mask other crashes."* Wrong: it **was**
   waiting.
2. The reason I believed that: `grep -E 'SYNC|CWAI'` over the instruction trace
   returned **zero**. The trace is emitted *one instruction late* (see the
   comment on `emit_cpu_trace` in `sim_main.cpp`), so the `CWAI` after `$0101`
   was never printed. **A `--trace-cpu` log does not contain the instruction that
   stopped the CPU.** Read the CPU state, not the disassembly, when asking why
   execution ended.

So nothing to fix here. What remains is why Arion crashes into page zero in the
first place, which is an ordinary per-title question and low priority.

### P4-12 [verified] Second breadth sweep: 18 titles, triaged by instruction rate

Sorted by main/frame rather than by screenshot, per the lesson from P4-11. The
rate turns out to separate three distinct failure modes that a screenshot cannot:

| main/f | sub/f | png | title |
|---|---|---|---|
| **1049** | 8721 | 3790 | Solitaire Royale |
| 1913 | 8718 | 3976 | Daisenryaku FM |
| 1965 | 7011 | 3790 | Miner 2049er |
| 2021 | 8529 | 4401 | Psy-O-Blade (FM77AV) |
| 3690-4963 | ~8700 | 3790 | Hokuto no Ken, Relics, Penguin-kun Wars, Riglas, Lupin Sansei, Might and Magic |
| 4836 | 7983 | 5068 | Castle Excellent |
| 4858 | 8117 | 5228 | Soukoban 2 |
| 5018 | 6630 | **7832** | **The Castle & Castle Excellent** |
| 5278 | 7871 | **26335** | **Hydlide II** |
| 4474 | 8424 | 4831 | Space Harrier (FM77AV) |

**Reading it:** a *low* rate with a *blank* screen is the P4-11 crash signature
(Solitaire Royale at 1049 matches Arion's 1087 almost exactly -- expect a `CWAI`
in page zero). A low rate *with* content is a title idling at a screen it has
already drawn (Daisenryaku, Psy-O-Blade). A *normal* rate with a blank screen is
something else again -- those titles are executing happily and choosing not to
draw.

**Two new titles render properly:**

- **The Castle & Castle Excellent** -- a clean menu, colour, and Japanese
  katakana, all legible.
- **Hydlide II** -- by far the richest screen the core has produced: the
  HYDLIDE logo, an ornate full-screen border, a story panel and a right-hand
  status bar (LIFE / STR / MAGIC / FORTH / EXP / STATUS / ATTACK).

### P4-13 [FIXED] Hydlide II dropped characters -- the sub BUSY flag was inverted

Hydlide II's story text used to come out with characters missing:

```
T  S  S A STORY OCCURR N N
  WAS AT WONACR UL WORL
```

It now reads:

```
THIS IS A STORY OCCURRED IN
DIFFERENT WORLD FROM OUR LIVE.
IT WAS A WONDERFUL WORLD
DOMINATED BY THE SWORD AND
THE MAGIC. MOST OF WHICH FOUND
THAT WORLD CALLED FAIRLAND.
```

**The cause was `FLAGS.v` clearing the sub-system BUSY flag while the sub was
halted, when it should have been SET by the halt request.** The old line was

```verilog
wire s3 = RESETBn & SHALTACn;   // held the BUSY flip-flop cleared for the halt
```

Both references do the opposite, and it is the whole completion handshake:

| | |
|---|---|
| **MAME** | `subintf_w`: `m_video.sub_halt = data & 0x80; if(data & 0x80) m_video.sub_busy = data & 0x80;` and `sub_busyflag_r` only clears `if(m_video.sub_halt == 0)` |
| **CSP** | `display.cpp:1879` -- `case SIG_FM7_SUB_HALT: if(flag) { sub_busy = true; }` |

The intended sequence is

```
main: poll $fd05 bit 7 until CLEAR      -- sub is idle
main: $fd05 <- $80                      -- halt requested, AND BUSY SET
main: write the command block to $fc80+
main: $fd05 <- $00                      -- halt released; BUSY STAYS SET
sub:  wakes, consumes the command, draws
sub:  returns to its ROM idle loop, reads $d40a -> BUSY clears
main: sees bit 7 clear and may send the next command
```

With BUSY force-cleared during the halt, bit 7 read 0 **the instant the main
released the halt** -- "sub idle" -- although the sub had not yet executed a
single instruction of the command. A main CPU looping "wait for idle, halt,
write, release" therefore overwrote command blocks the sub had not consumed.
Being a race it cost *some* commands and not others, which is exactly the
symptom: whole glyphs absent, not corrupted.

The flag is now clocked rather than assembled from a stack of asynchronous
edges, since it has three inputs (the halt request plus the sub's read and
write of `$d40a`), so `FLAGS` gains a `CLKSYS` port. `TIMER.v`'s
`BUSY | ~SHALTACn` for bit 7 stays -- redundant now that the request sets BUSY,
but MAME ORs `sub_halt` in the same way.

**Thexder improved too**, which is the corroborating evidence: its title
artwork gains detail and its rate moves 5005 -> 5008 main/frame. That is the
same residual byte loss (the ~3-of-433 the pump used to cost) easing on the
title that leans hardest on this window.

**A/B'd properly rather than assumed.** The change alters a flag that titles
poll in a wait loop, so "it fixed my test case" is not enough — it could have
hard-blocked something else. The pre-fix core was rebuilt and 93 titles (every
render plus 60 healthy-rate blanks) run through both:

| | |
|---|---|
| better with the fix | **7** |
| worse with the fix | **0** |
| unchanged | 86 |

| | before | after |
|---|---|---|
| Ys (FM7) (Disk A) | 3790 (blank) | **26146** |
| DNA (Disk A) | 4094 | **9791** |
| Dezeni Land | 3790 (blank) | **8529** |
| Templo del Sol - Asteka II | 3790 (blank) | **6407** |
| Thexder | 55364 | 57826 |
| Hydlide II | 26335 | 28715 |

**One real hazard the A/B did NOT show, recorded because it will matter later.**
1942 polls `LDA $fd05 / BMI` — waiting for bit 7 to *clear*. Before the fix it
read `$7e` and fell through; after, it reads `$fe` and spins forever, because
its sub CPU never returns to the ROM idle loop to read `$d40a`:

```
sub handshake : BUSY=1  SHALTn=1  SHALTACn=1   $fd05 would read $fe
   $d40a access : 3 reads (clear BUSY), 2 writes (set BUSY)
```

Three `$d40a` accesses in 700 frames, with the sub executing 8370
instructions/frame — so the sub is running *something*, just not the ROM's idle
loop. 1942 was blank before and is blank now, so this is not a regression in
outcome, and the flag semantics match both references. But it does mean **a
title whose sub never reaches `$e13b` will now hard-block on `$fd05` bit 7**,
and that is a sharp, checkable signature to look for in the remaining blanks:
`BUSY=1` with `SHALTACn=1` and a near-zero `$d40a` count.

**A metric that did NOT show the fix, worth recording.** The write/read ratio
this entry was originally built on barely moved: the main still writes 6891
payload bytes to `$fc83`-`$fc8f` over 700 frames and the sub now reads 5878
against 5833 before -- 84.6% to 85.3%. The screen went from unreadable to
correct over that same change. Commands vary in length so the sub need not read
every byte of every block, and the ratio was never a proxy for whether a
command survived. **Look at the rendered result, not at the byte counts.**

Two mechanisms had already been eliminated by measurement before this, and both
eliminations were correct -- they are kept below because the measurements are
reusable.

**The sub-CPU VRAM wait state is NOT the cause -- ruled out by experiment.** The
theory was that `sub_vram_wait` throttles drawing badly enough to starve the
transfer, since `SCASSEL` is high only during blanking and the sub is stalled on
every VRAM access outside it. Setting `sub_vram_wait = 1'b0` and measuring:

| | with wait | without |
|---|---|---|
| Hydlide II sub | 7871/frame | 8293/frame (+5%) |
| Thexder sub | 6873/frame | 7342/frame (+7%) |
| Hydlide II screen | 26335 bytes | **3870, broken** |

So the wait costs only about **6%** of sub throughput -- far short of a 15%
shortfall -- and removing it corrupts rendering exactly as the comment in
`core.v` predicts, because `SVRADRS` follows the raster during display and the
access lands at the wrong address. Reverted. Neither CSP nor 77AVEMU models a
sub VRAM wait at all, so ours is stricter than both, but that strictness is not
what is losing the characters.

**The shared-RAM aperture is not dropping the writes either -- also ruled out.**
Main-side writes are gated on `SHALTACn` (P4-1h), so a title that writes command
blocks *without* halting the sub first would have them silently discarded. That
would fit the symptom exactly. It is not happening: `DEBUG_SRAM` reports

| title | accepted | misdirected |
|---|---|---|
| Hydlide II | 33074 | **0** |
| The Castle | 37724 | **0** |
| Thexder | 156699 | **0** |

So two mechanisms are now eliminated -- the VRAM wait state and the aperture
gating -- and the main's writes demonstrably land. Look instead at the
command-block protocol itself: whether the sub is being told to draw every glyph
and dropping some, or the main never sends them. The Castle's console path is
the working control to compare against.

*(Method note: the first run of this measurement produced no output at all and
looked like a clean null result. The `DEBUG_SRAM` define had not actually been
compiled in -- see the warning now at the top of the flag section in
`vsim/Makefile`. Check `grep -l SRAMSUM obj_dir/*.cpp` before believing silence.)*

### P4-14 [verified] Third breadth sweep: the whole Neo Kobe floppy collection

Every `[FD]` archive in `software/Neo Kobe - Fujitsu FM-7 (2016-02-25).zip`,
unpacked to **350 disk images**, each booted at `--bootrom 0` for 700 frames
with a screenshot at 680. Run against commit `6aad4a8`.

> **⚠ SUPERSEDED BY P4-16.** This sweep predates P4-15, which fixed
> `$8000-$fbff` reading as zero whenever the `$fd0f` RAM window was open — the
> window games load into. The re-run against `ada5c37` moved **44 titles better,
> 0 worse**: renders 33 → 62, blanks 108 → 77, crashes 15 → 8. The bucket
> *method* below is still the right method and the halt-stub / secondary-disk
> analysis still holds, since those are properties of the disks rather than of
> the core. **The counts are not.** Use P4-16.

**Split FM-7 from FM77AV before reading any of it.** 129 of the 350 images are
FM77AV software — a different machine (MMR paging, the MB61VH010 drawing ALU,
analog palette, 4096-colour mode, YM2203), none of which this core implements
(P5). Counting those as FM-7 failures is meaningless, and the split is its own
sanity check on the sweep: FM-7 images produce 33 rich screens, FM77AV images
produce **one**.

| | FM-7 (221) | FM77AV (129) |
|---|---|---|
| renders a rich screen | **33** | 1 |
| healthy rate, some content | 48 | 30 |
| healthy rate, drawing nothing | 108 | 82 |
| low rate with content (idling) | 1 | 2 |
| low rate, blank (crash — expect a `CWAI`) | 15 | 6 |
| did not boot, fell back to cassette F-BASIC | 16 | 8 |

**The 33 FM-7 images that render** (main/frame, sub/frame, PNG bytes — PNG size
is the content proxy; a blank 640x200 raster compresses to ~3790):

| main | sub | png | title |
|---|---|---|---|
| 4859 | 6739 | 57826 | **Thexder** |
| 5277 | 7865 | 28715 | **Hydlide II** (and `[Set 1]`) |
| 4519 | 4481 | 26146 | **Ys (FM7) (Disk A)** — new, see P4-8 |
| 4918 | 7318 | 16957 | **Mugen no Shinzou II** — title artwork, kanji logo |
| 5456 | 6662 | 12286 | Cream Lemon - SF Choujigen Densetsu Rall (Disk 2) |
| 4420 | 7557 | 11156 | **Archon** |
| 5035 | 7319 | 10167 | **The Knight of Wonderland** — HummingBird Soft logo |
| 4915 | 6556 | 9814 | Pop Lemon (Disk 1) |
| 4960 | 7769 | 9791 | DNA (Disk A) |
| 4930 | 7182 | 8840 | Voodoo Castle |
| 5173 | 7171 | 8767 | The Palms |
| 5072 | 7042 | 8529 | **Dezeni Land** — HUDSON SOFT splash |
| 4920 | 7230 | 8407 | Mission Impossible |
| 5059 | 8610 | 8328 | `[Utility]` Expert FM (Construction 2) |
| 4864 | 7447 | 8080 | Strange Odyssey |
| 4930 | 7146 | 7939 | Genmu no Shiro |
| 5018 | 6630 | 7832 | **The Castle & Castle Excellent** |
| 5131 | 6208 | 7358-7421 | `[Utility]` The File Master FM — seven dated revisions |
| 4920 | 7402 | 7105 | The Count |
| 4894 | 7139 | 6763 | Lovely Gal (Disk 1) |
| 4615-5017 | 6565-8463 | 6373-6607 | Team AB Music Disk — four variants |
| 4242 | 3265 | 6407 | Templo del Sol - Asteka II (Disk A) |

Spot-checked by eye rather than trusted from the byte count: Thexder, Hydlide II,
Ys, Archon, Mugen no Shinzou II, The Knight of Wonderland and Dezeni Land all
show real, legible artwork.

**The largest single failure mode is "healthy rate, drawing nothing"** — 108 of
221. But that raw number is wrong to quote, because a large slice of it is
disks that *should not* boot:

| | |
|---|---|
| 108 | FM-7 images at a healthy rate with a blank screen |
| −13 | boot sector is a deliberate **halt stub** — not bootable by design |
| −35 | **secondary disk of a multi-disk set** — `(Disk 2..9)`, `(Disk B..Z)`, `- Data)`, `- Scenario)`, `(User disk)`, `{run NAME}` |
| **60** | genuine "should boot and does not" |
| (14) | of those 60 are marked `[b]`, a known-bad dump |
| **46** | primary, good-dump disks that should boot and come up blank |

The secondary disks are worth understanding rather than just filtering. Their
boot sector is not a halt stub, it is simply **not code** — `DNA (Disk B)` is
256 zero bytes, `Take Out Vol. 7 (Disk B)` is pattern data, `Alpha` is
`86 b9 b7 ff f5 ...`. The boot ROM loads it at `$0100` and jumps in, so the
machine executes data as instructions and falls quiet at ~3518 I/O cycles.
That is what real hardware does with a data disk, and it is not a defect.

**The halt-stub finding is the useful part**, and `vsim/sweep/bootsector.py`
tests for it directly from the image. 31 disks in the collection have a track 0
/ side 0 / sector 1 that reads

```
$0100  1a 50        ORCC #$50     ; mask IRQ and FIRQ
$0102  86 41        LDA  #$41
$0104  b7 fd 03     STA  $fd03
$0107  20 fe        BRA  $0107    ; spin forever
```

That is a program/data disk telling the machine to stop — they are meant to be
loaded from Disk BASIC on another disk, and several say so in their own names
(`{run NUGI}`, `{run AKUNIN-1}`, `(User disk)`). The core boots them into that
loop and shows a blank screen, which is **exactly right**. Their signature is
main 6399 / sub 8721 / 3519 I/O cycles, identical across every one of them, and
a `--pc-profile` puts 3841350 of the main CPU's instructions on `$0107` alone.

So the honest remaining target is **46** titles, not 108.

**And those 46 are not one bug.** Measuring the sub handshake state at the end
of each run splits them cleanly:

| | |
|---|---|
| 62 of 87 | `BUSY=0`, sub not halted, **fewer than 20 `$d40a` accesses in 700 frames** — the main CPU never talks to the sub at all |
| 10 | `BUSY=1` with real `$d40a` traffic — a live handshake that has not finished |
| 2 | the 1942 signature: `BUSY=1`, `SHALTACn=1`, near-zero `$d40a` |

So the dominant failure is **upstream of the display entirely**: the main CPU
never gets far enough to ask the sub to draw. Chasing the video path for these
is wasted effort.

**A large sub-group of those is a main-CPU runaway, and it has a signature.**
Titles with a *low* main rate (~3700, below the 4400-5800 healthy band), sub
**exactly 8721**, and a *huge* I/O count (2-4M) turn out to be executing
zeroed memory:

```
$00f2  00 00    NEG  <$00
$00f4  00 00    NEG  <$00
$00f6  00 00    NEG  <$00
```

Opcode `00 00` is `NEG` direct-page — i.e. the CPU jumped into cleared RAM and
is executing zeros. With `DP=$fd` the operand is `$fd00`, so every one of those
is a read-modify-write on an I/O port, which is exactly why the I/O count is in
the millions and the instruction rate is *below* normal: `NEG` is slow. Sub
= 8721 exactly is the sub sitting in its ROM idle loop at `$e13e`-`$e148`,
never given work.

Confirmed on Xevious (`$00b8`), Tritorn (`$00f2`) and Hokuto no Ken (`$e5db`).
Wing Man 2 and Thunder Force share the rate/IO profile; Thunder Force is
actually different — a decrypt loop at `$010a LDA ,X / EORA #$93 / BNE` — so
check each rather than assuming.

**This is the same class as P4-7 (CHAN.POP) and P4-11 (Arion)**, and it now has
five or six more instances to compare against, which is a much better position
than one title. `sub == 8721` and `NEG <$00` in the instruction tail are the two
things to grep for.

*(A trap in the tooling itself, worth the same warning as the rest: some of
these archives unpack into an `alts/` subdirectory, so a flat `os.listdir` over
the extraction directory silently misses 26 of the 350 images. That does not
look like a bug, it looks like 26 titles having no disk image. `find` and
`os.walk` see them; `os.listdir` and `ls *.d77` do not.)*

**The sweep reproduces the earlier numbers exactly**, which is the check that
the harness is honest: Arion 1087, Solitaire Royale 1049, Miner 2049er 1965,
Daisenryaku FM 1913, The Castle & Castle Excellent 5018/6630/7832 — all
identical to what P4-11 and P4-12 recorded.

**A new diagnostic falls out of the crash bucket: `sub = 8721`.** Ten of the
fifteen crashed FM-7 images report *exactly* 8721 sub instructions/frame, and
that is the sub CPU idling in its ROM loop with nothing to do. So the pair
"low main + sub exactly 8721" is a sharper crash signature than the rate alone:
it says the main died and the sub was never given work, as opposed to the sub
also being off in a game's own code. The handful with a *different* low sub
rate — Take Out Vol. 4 (2021/3043), Take Out Vol. 7 (2276/3523), Game 4
(1866/3633) — are a different failure and worth separating.

**50 images tripped the `RUNAWAY-INTO-IO` guard**, i.e. the main CPU fetched
instructions from the `$fdxx` window. Undecoded I/O reads return `$ff`, which
never traps, so a runaway there executes forever instead of crashing. Worth
noting `Thexder [Alt 1] [b]` is among them while plain `Thexder [b]` is the best
render in the collection — so it is a per-dump property, not a per-title one.

**Caveats on this sweep, all of which under-report:**

- **One configuration only.** Everything ran at `--bootrom 0` with no keyboard
  input. Three images are marked `{boot DOS mode}` and need `--bootrom 2`; OS-9
  is one of them and correctly shows up here as "did not boot".
- **No input.** Titles waiting at a "press any key" prompt score as blank. Ys
  needed `--key '820:@SPACE'` to reach the screen credited above and would have
  scored blank without it.
- **700 frames.** A slow loader is indistinguishable from one that never draws.
- Multi-disk sets are counted per image, so a game with a program disk and a
  scenario disk contributes two rows.

Reproduce:

```sh
vsim/sweep/sweep.sh /tmp/sweep 12 700      # extract, run, write results.tsv
vsim/sweep/triage.py /tmp/sweep/results.tsv fm7   # or 'av', or 'all'
```

**The harness must `cd` to `vsim/` — see measurement trap 9; the first run of
this sweep produced 350 rows of uniform garbage because it did not.**
`sweep_one.sh` now does that itself and flags `NOROM` if a run's log mentions
`readmem file not found`, so the failure cannot be silent a second time.

`vsim/sweep/check_kbd.py` is unrelated to the sweep but lives here for the same
reason: it diffs `KEYBOARD.v`'s CTRL/GRAPH/KANA tables against CSP's header
through the PS/2 ↔ physical-key mapping, and it caught a real transcription
error (P2-1).

### P4-17 [verified] `SRESETn` sweep: a correctness fix, not an unlock

`f9548d8` untied `SRESETn` from `1'b0` in the `FLAGS` instantiation, which had
been holding three flip-flops permanently in reset — including `m45`, so
`SUBIRQn` could never assert and the sub CPU could never take the main's
attention IRQ. A full 350-image sweep against it, diffed against
`vsim/sweep/results-P4-16.tsv`:

| | |
|---|---|
| FM-7 comparable | 221 |
| better | **1** |
| worse | **1** |
| FM77AV (129) | 0 better, 0 worse |

| | before | after |
|---|---|---|
| **1942** | 3790 (blank) | **5880** |
| Templo del Sol - Asteka II (Disk B) `[b]` | 4464 | **3790** (blank) |

The bucket totals are byte-identical to P4-16 (62/53/77/4/8/17) because those
two swapped places between BLANK and PARTIAL.

**Be honest about what this is: a small fix, not an unlock.** One title in 221,
against P4-15's 44. But it is a *correct* one with a fully traced mechanism, and
a permanently-dead interrupt path is wrong on its own terms — any title using
`$fd05` bit 6 works now where it could not before.

**1942 moves through `SUBIRQn`, exactly as `f9548d8` first reasoned — and the
"correction" that previously stood here was itself wrong.** The story is worth
keeping in full, because it is the same measurement error twice in one day.

I claimed 1942 never writes `$fd05` and therefore could not be explained by the
attention IRQ. **That measurement was a false negative.** 1942 writes `$fd05`
**70629 times** over 700 frames, including `$40` — the CANCEL bit — at frame
265 from `pc=$1953`:

```
  265 mem  W $fd05 <- $40   pc=$1953     <- attention requested
  265 mem  W $fd05 <- $00   pc=$1956
  265 mem  W $fd05 <- $80   pc=$4b05     <- halt requested
  265 mem  R $fd05 -> $fe   pc=$4b08
```

So the mechanism is exactly the one originally described: `$fd05` bit 6 drives
`CANCELn`, whose release clocks `m45`, which asserts `SUBIRQn`; the sub's `$e06e`
handler then writes `$d000 = $ff` and the `$fd76` wait exits. With `SRESETn`
tied low, `m45` was pinned at 0 and none of that could happen.

**What went wrong in the measurement, twice.** The original batch ran three
titles through
`grep -oE 'W +\$fd05 <- \$[0-9a-f]{2}'` and printed three headers with nothing
under them, which read as "none of these touch `$fd05`". Re-running the same
title with `grep '\$fd05'` and looking at raw lines shows 70629 hits. The
lesson is the one already at trap 9 and 11 in this document and it did not
take: **a grep returning nothing is a claim about your pattern, not about the
machine. Print raw lines first, then narrow.**

**Penguin-kun Wars really does not request attention** — re-measured properly,
172 writes of `$00` and `$80` only, no `$40`. So it is genuinely unexplained,
and that half of the earlier note survives.

**And it costs one title.** `Templo del Sol - Asteka II (Disk B)` drops from
4464 to blank, reproducibly; Disk A is untouched at 35230. Disk B is a secondary
disk of a multi-disk set *and* marked `[b]`, a known-bad dump, so both of
P4-16's exclusion filters would drop it from any failure count — but a
regression is a regression and it is recorded rather than filtered away. The fix
is kept because tying a reset pin to 0 is indefensible regardless of the
scoreboard.

### P4-18 [verified] MAME's own software list is a triage input

MAME ships `refs/mame/hash/fm7_disk.xml`, a software list where an entry can
carry `supported="no"` — meaning **MAME itself cannot run that title**. 14 of its
158 disk entries are marked so. Cross-referencing them against the sweep
separates "our bug" from "this title is problematic for everyone", and it cuts
both ways.

**Two of the 14 work here and not in MAME:**

| title | MAME | this core |
|---|---|---|
| Champion ProWres Special | `supported="no"` | **renders, 18986 bytes** |
| DNA (Disk A) | `supported="no"` | **renders, 9791 bytes** |

**The rest land in our failure buckets**, which is evidence they are bad dumps or
need something neither emulator provides: Abyss, Märchen Veil, Transylvania,
Game 011/012/02G/03G/04G and the four Ura DOS disks.

Folding that in as a fourth exclusion alongside the halt-stub, secondary-disk and
`[b]` bad-dump tests gives the honest remaining target:

| | blank at healthy rate | crash (low rate, blank) |
|---|---|---|
| raw | 77 | 8 |
| − boot sector not bootable | 23 | 1 |
| − secondary disk of a set | 27 | 2 |
| − **MAME cannot run it either** | 5 | 1 |
| − marked `[b]` bad dump | 5 | 2 |
| **genuine, good dump, MAME runs it** | **17** | **2** |

So **19 real failures out of 221 FM-7 images**, not the 85 the raw buckets
suggest.

**Caveat, so this is not used as an excuse.** "MAME cannot run it" is evidence
about the title, not proof about this core — MAME's FM-7 driver is unreliable
(that is the project's own standing rule, and P4-17 and the `$fd1d` fix are both
cases where following MAME was the bug). A title on that list could still be
failing here for a reason of ours. It shifts priority, it does not close a case.

Also worth knowing from the same file: MAME flags `fm7`, `fm8` and `fmnew7` as
working with no caveats, `fm77av` as `MACHINE_IMPERFECT_GRAPHICS`, and
`fm7740sx`, `fm11` and `fm16beta` as `MACHINE_NOT_WORKING` — relevant to
`FM77AV_PLAN.md`, since it means MAME is not a reliable oracle for AV40SX
behaviour either.

### P4-16 [verified] Fourth breadth sweep: the whole collection, after P4-15

Same 350 images, same method as P4-14, run against `ada5c37` (the P4-15 read-mux
fix plus the P3-3 kanji ROM). The binary's md5 was recorded before the run and
checked after, because an earlier attempt was invalidated by rebuilding
underneath it.

**44 FM-7 titles better, 0 worse.** For a change to the main CPU's read path,
the zero is the number that matters.

| FM-7 (221 images) | P4-14 | **P4-16** | |
|---|---|---|---|
| renders a rich screen | 33 | **62** | +29 |
| healthy rate, some content | 48 | 53 | +5 |
| healthy rate, drawing nothing | 108 | **77** | −31 |
| low rate with content (idling) | 1 | 4 | |
| low rate, blank (crash) | 15 | **8** | −7 |
| did not boot, fell to F-BASIC | 16 | 17 | |

Rescoping the blank bucket the same way P4-14 did — subtracting disks that
should not boot — gives the honest target:

| | P4-14 | **P4-16** |
|---|---|---|
| blank at a healthy rate | 108 | 77 |
| − boot sector is not bootable | 13 | 22 |
| − secondary disk of a multi-disk set | 35 | 27 |
| genuine | 60 | **28** |
| (of those, marked `[b]` bad dump) | (14) | (10) |
| **primary, good-dump, should boot** | **46** | **18** |

`bootsector.py` gained two classes on the way: `uniform-$xx`, a sector where
every byte is identical ($e5 is the standard formatted-but-never-written fill on
FM/MFM media, and $00 and $ff both turn up), and the `(Disk 1-B)` naming that
the secondary-disk pattern previously missed. Counts are now 13 `BRA-self`,
4 `uniform-$e5`, 3 `uniform-$00`, 2 `uniform-$ff`.

> **A filter that was tried and is WRONG, recorded so it is not re-tried:
> "the boot sector is mostly zeros, so it is not code".** A short loader padded
> out to the 256-byte sector is the *normal* shape. **1942's boot sector is 92%
> zeros** and opens `86 fd 1f 8b 97 0f ...`, which is 6809 code; **Tritorn's is
> 87% zeros**, opens `1a 50 86 fd 1f ...`, and Tritorn renders correctly. An
> 85%-zeros threshold silently removed both from the failure count — it made the
> numbers look better by discarding a real failure and a real success. Only
> "every byte identical" is safe. **Over-counting failures is the safe
> direction.**

**The FM77AV column barely moves** (1 render before, 1 after), which is the
control: P4-15 is an FM-7 memory-map fix and FM77AV software fails for reasons
this core does not implement at all.

**Biggest movers**, all previously blank or near-blank:

| title | P4-14 | P4-16 |
|---|---|---|
| **Ys (FM7)** | 26146 (HUD, empty fields) | **35880** |
| **Templo del Sol - Asteka II** | 6407 | **35230** |
| **Lefty Mouse** | 3790 (blank) | **31824** |
| **Tritorn** | 3790 (blank) | **30657** |
| **Take Out Vol. 1/2/3/4/7** | 3790 (blank) | 12655-21001 |
| **Champion ProWres Special** | 3790 (blank) | 18986 |
| **Thunder Force** | 3790 (blank) | 14398 |
| **Mahoutsukai no Deshi I / II** | ~3810 (blank) | 13445 / 14442 |
| **Wibarm** | 3790 (blank) | 11531 |
| **Helicoid**, **Topple Zip** | 3790 (blank) | 10629 / 10611 |
| Thexder | 57826 | **65102** |

Two things worth noting from the movers. The whole **Take Out** series moved
together — same publisher, same loader, same dependency on reading back what it
loaded. And **Thunder Force** is here, which P4-15 had explicitly set aside as
"actually a decrypt loop at `$010a`, so check each rather than assuming" — that
caution was right in method and wrong in conclusion; it was the same bug.

#### Triaging the 18 by sub-system handshake state

Running `vsim/sweep/handshake_one.sh` over them splits the 18 three ways:

| | | |
|---|---|---|
| **5** | `BUSY=1`, `SHALTACn=1` | 1942, Fairie's Residence, Lupin Sansei, Penguin-kun Wars, Yellow Lemon |
| 2 | `BUSY=1`, `SHALTACn=0` (still halted) | `[Compilation]` Game 4, Bishoujo Shashinkan |
| 11 | `BUSY=0`, sub idle | the rest |

The **5** are the hazard P4-13 predicted: the main halted the sub, the sub never
returned to its ROM idle loop to read `$d40a`, so `$fd05` bit 7 stays set and a
main CPU polling `LDA $fd05 / BMI` waits forever.

**This is NOT a regression from the BUSY fix**, which was the obvious suspicion
and had to be checked. Four of the five appear in the pre-`9fc762b` A/B sample
and were blank there too — 3790 before, 3790 after. (Yellow Lemon was not in
that sample, so for it this is unverified.)

**Two of them sit in the same sub-ROM loop as Ys**, which is the actually useful
finding. Penguin-kun Wars and Fairie's Residence both end at

```
$fd7e  d6 00     LDB   <$00      ; DP page $d0
$fd80  26 10     BNE   $fd92
$fd82  1c bf     ANDCC #$bf      ; unmask FIRQ
$fd84  20 f0     BRA   $fd76
```

which is the `$fd76` wait loop P4-8 records Ys passing through **during boot**.
But Ys *leaves* it and goes on to render its title screen; these two never do,
and six keypresses do not move them. So this is a shared **location**, not a
shared cause — see the correction at the head of P4-8. `ANDCC #$bf` clears the F flag, and the sub's
FIRQ is the keyboard (`KSTROBEn`), which suggests "waiting for a keypress" —
**but that was tested and is wrong**: feeding SPACE/RETURN/SPACE at frames
400/600/800 leaves both at 3790. Either they take the main-side keyboard route
(`$fd02` bit 0) and the sub's FIRQ is correctly masked, or they are waiting on
something else entirely. Start by checking which route each one selects.

#### What the three `$fd76` titles are actually doing [no cause found]

Penguin-kun Wars, Fairie's Residence and Yellow Lemon were chased hard and the
cause was **not** found. Recorded because the eliminations are reusable:

- **They halt the sub but never request attention.** Re-measured properly:
  Penguin-kun Wars 172 `$fd05` writes, Fairie's Residence 61, Yellow Lemon 248 —
  every one of them `$80` or `$00`, **never `$40`**. So unlike 1942 they never
  use the CANCEL/attention path, and P4-17's `SRESETn` fix cannot help them.
- **Keyboard input does not move them**, tested on the fully-fixed build (P4-15
  + `$fd02` route + `SRESETn`) with SPACE/RETURN at four frames out to 1400.
  All three stay at 3790.
- **The `$fd76` framing was over-read.** That came from a `--trace-tail`
  snapshot, i.e. the last few instructions before the run ended. A proper trace
  shows the sub also executing `$ff4e LDA $d381` exactly once per frame
  throughout, which is a healthy periodic task, not a spin. The sub is not
  simply wedged.
- **Penguin-kun Wars is running F-BASIC, not a self-loading game.** Its command
  block into `$fc80` comes from `pc=$f61a` — inside the F-BASIC ROM — and the
  payload spells `AUTO ` in ASCII (`41 55 54 4f 20`). So the disk boots BASIC
  and autoloads, which makes a blank screen a plausible *software* state rather
  than an emulation failure. That has not been confirmed.

Next thing to try: find which command byte the main is dispatching and follow
the sub's `$e14a` dispatch for it, rather than reasoning from where the CPU
happens to be at frame 700.

**The 8 crashes that remain** are a different set from P4-14's fifteen — Arion,
Solitaire Royale and Miner 2049er are gone from it:

```
1913  8718  Daisenryaku FM
1245  8727  [Compilation] Ura DOS 01 [b]
2172  8721  Wizard and the Princess (Disk 1)
1410  8721  Girls Paradise (Disk C) [b]
1195  8721  Thexder [Alt 1] [b]   [RUNAWAY-INTO-IO]
 951  8721  Transylvania (Disk 1)
 943  8721  The Quest (Disk 1-A)
 920  8721  The Dark Crystal (Disk 1-B)
```

Seven of the eight still show `sub = 8721` exactly, so the "sub idling in its ROM
loop, never given work" signature is still the thing to grep for. Three of them
are `(Disk 1)`/`(Disk 1-A)`/`(Disk 1-B)` of multi-disk sets, which the secondary
-disk filter does not catch because they *are* the first disk.

### P4-15 [FIXED] `$8000-$fbff` read as ZERO whenever the `$fd0f` RAM window was open

**This is the largest single bug found so far, and the reason it hid for so long
is worth more than the fix.**

`core.v`'s `MDATABUS_in` mux had no arm for the RAM window. `RAM1HB2n` is really
"F-BASIC ROM selected" despite its name — `ROMS.v` has
`m107_q = ~(MADDRBUS[15] & FCXXn & ff_q)` — so:

| `$fd0f` mode | `RAM1HB2n` | what the mux did |
|---|---|---|
| ROM (`ff_q=1`) | 0 | `~RAM1HB2n` arm matches → `ROMDATA`. Fine. |
| **RAM** (`ff_q=0`) | **1** | ROM arm stops matching. The MRAM arm cannot match either: `~(RAM1HB1n & RAM1HB2n)` is `~(1 & 1)` = 0, because `ROMS.v` forces `RAM1HB1n` high for anything outside `$fc00-$ffff`, and `MADDRBUS <= 16'h8000` is false above `$8000`. **Falls through to `8'h0`.** |

So every read of that 31 KB window returned zero while the RAM map was open —
and the RAM map is exactly what games open to load into.

**WRITES WERE ALWAYS FINE.** `MRAM.v` is a full 64 K with `ce_n` tied low, so
stores landed perfectly. That is the whole reason this survived: it presented as
*"the data I stored comes back as zeros"*, not as dead memory, so every
investigation that verified the **write** path concluded the path was healthy.
P4-1j says so in as many words — Ys performing "a clean contiguous 24 KB program
load, no gaps, no double-writes ... this whole path is working". The writes
*were* working. Nobody checked the reads.

**Generalise it: verifying a write path proves nothing about the read path, and
a memory that accepts writes and returns zeros looks like a software bug in
whatever ran next.**

#### How it was found

Traced Xevious to the exact instruction where control was lost. The boot ROM's
delay routine at `$feba`-`$fec0` ends in an `RTS`, and that `RTS` jumped to
`$0000`:

```
$fed8  8d e0     BSR   $feba        s=bee7
$feba  17 00 00  LBSR  $febd        s=bee5
$febd  17 00 00  LBSR  $fec0        s=bee3
$fec0  39        RTS                s=bee5
$0000  00 00     NEG   <$00         <- should have returned to $fec0
```

`--dump-shadow` then settled it. The stack held the correct pushed values at
`$bee7` (`fe da`) and `$bee5` (`fe bd`), but `$bee3` read back `00 00` where
`$fec0` had been pushed — and `$bee3` sits inside the `$fd0f` window. Opcode
`$00 $00` is `NEG` direct-page, so the CPU walked page zero doing
read-modify-writes on `$fd00` (`DP=$fd`), which is exactly the signature the
P4-14 sweep had already isolated: main rate *below* the healthy band, sub pinned
at **exactly 8721** in its ROM idle loop, and millions of I/O cycles.

*(`--dump-shadow` records both directions — `shadow_m.mem[addr] = rw ? din :
dout` — so a value in it is the last access either way. `$bee5` showing the
pushed value proves the write landed; `$bee3` showing `00 00` is the read
result.)*

#### Effect

| | before | after |
|---|---|---|
| **Xevious** | 3902/8721, blank | 5137/6493, **title screen** |
| **Tritorn** | 3723/8721, blank | 5209/7033, **full title artwork** |
| **Hokuto no Ken** | 3690/8721, blank | 4797/6682, content |
| **Ys** | HUD with empty fields | HUD showing `H.P 020/020`, `EXP 00000/00200`, `GOLD 01000` — P4-8 advanced, **not** solved; the play area is still black |

All 8 rows of `run_tests.sh` byte-identical. F-BASIC itself lives in this window
in ROM mode, so the existing rows exercise the ROM arm heavily — it is the RAM
arm that had no coverage at all.

#### Three wrong hypotheses on the way, recorded so they are not re-tried

1. **The F-BASIC ROM is mapped over the stack.** No — `fbasic300.rom` holds
   `d7 ba` at `$bee3`, not `00 00`.
2. **`$ffe0-$ffef` is mis-mapped** (P3-5 flags it, and both Xevious and Ys touch
   `$ffe5`). No — it is working RAM: `poke 65509,123 : print peek(65509)`
   returns 123.
3. **`--trace-mem` can watch RAM.** It cannot. Despite the help text promising
   "every main-CPU bus cycle in that hex address range", it only logs `$fdxx`
   here — `--trace-mem 0100-0110` over the boot-sector load returns zero lines.
   That reads as "the region is never touched", which is a very convincing lie.
   Use `--dump-shadow` for RAM instead.

**Everything P4-14 concluded about blank screens was measured on this broken
core** and must be re-derived — see the re-sweep note there.

### P4-9 [verified] Breadth sweep: 12 titles from the Neo Kobe collection

`software/Neo Kobe - Fujitsu FM-7 (2016-02-25).zip` holds **156 floppy titles**
as nested `.7z` per game. Extract with a bracket-free pattern -- `[FD]` is a
shell/unzip *character class*, so `*[FD]*.7z` silently matches the wrong things:

```sh
unzip -o -j -q "$Z" "*F-BASIC v3.0 L10 *FD*.7z" -d .   # good
7z x -y -o. *.7z
```

Booted at `--bootrom 0`, screenshot at frame 680:

| title | result |
|---|---|
| **Archon** (BPS) | **full title screen**, logo + artwork + border |
| **`[OS]` F-BASIC v3.0 L10** (Fujitsu) | **boots Disk BASIC** to its drive prompt |
| **Amnork** (ASCII) | credits screen, "PROGRAMMED BY H.SONOBE" |
| **A-Train** (Artdink) | loads all five sections, "SECTION 5/5" |
| `[Compilation]` Game 1 | content on screen |
| `[OS]` OS-9 Level 1 | **falls back to cassette BASIC** -- needs DOS boot mode, blocked by P3-6b |
| 1942, Albatross, Alpha, Arion | blank |

**Archon is the second game to render a title screen**, and the official Fujitsu
BASIC disk booting is a stronger result than the compilation disk, since it is
first-party system software.

**OS-9 gives P3-6b a concrete cost.** Its image is named `{boot DOS mode}` and it
cannot boot because settings 1/2/3 all resolve to bank 2. That raises P3-6b from
tidiness to "blocks an OS".

**Both keyboard routings verified working.** Titles split on `$fd02` bit 0:

- `$fd02 <- $05` (bit 0 set, keyboard to **main**): Ys, 1942. Verified in P1-6.
- `$fd02 <- $40` (bit 0 clear, keyboard to **sub**): Archon, Amnork. Verified
  here -- Archon's sub does a 16-bit read at `pc=$fdae` and gets
  `$d400=$00 / $d401=$0d` for RETURN and `$20` for SPACE, once per press via
  FIRQ. Correct codes, correct delivery.

So the sub-side keyboard is **not** the reason Archon waits at its title, and
that whole path is now cleared. No new bug came out of this sweep -- which is
itself the finding: the remaining failures are per-title software problems, not
shared subsystem faults.

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

### P1-6 [FIXED] `$fd03` bit 2 read the opposite sense to the other three

`CLKCTRL.v` returned the interrupt-cause register as

```verilog
MDATABUS_out = { 4'hf, ~EXTIRQ, m50_qn, LPINTn, KEYINn };
```

Bits 0, 1 and 3 are active low -- `KEYINn`, `LPINTn` and `~EXTIRQ` each read 0
when that source is pending -- but bit 2 was `m50_qn`, i.e. `~m50_1`, and
`m50_1` is itself the active-low timer flag: `IRQn = m50_1 & KEYINn & LPINTn`
asserts on 0. So the timer bit read the opposite sense to the IRQ line driving
it, and to its three neighbours.

Both references agree the whole register is active low. CSP clears a bit when
its source is pending (`irqstat_reg0 &= ~0x08`, `fm7_mainio.cpp:1141`) and
acknowledges on read by setting the timer and printer bits back
(`irqstat_reg0 |= 0x06`); MAME's assignments match (`IRQ_FLAG_KEY 0x01`,
`PRINTER 0x02`, `TIMER 0x04`, `OTHER 0x08`, `fm7.h:69`). Now `m50_1`.

**Confirmed effect: it repairs keyboard delivery to games with their own ISR.**
Ys's interrupt handler dispatches on this register:

```
$117d  LDA  $fd03
$1180  BITA #$04        ; timer?
$1182  BEQ  $1195       ; yes -> music tick
$1184  BITA #$01        ; no  -> keyboard?
$1186  BEQ  $1189
$1189  LDA  $fd01       ; read the key
$118c  LDB  $fd00
$118f  BMI  $1194
$1191  STA  $11a4       ; hand it to the game
```

With bit 2 inverted the timer always appeared pending, so `$1182` was taken
every single time and **`$1184`-`$1193` never executed at all** -- measured, not
assumed. `$11a4` stayed `$00` forever and Ys sat in its key-wait loop at
`$1026`. After the fix `$fd03` reads `$fe` (bit 0 clear = key pending, bit 2 set
= not timer), the branch falls through, `$fd01` returns `$20` for SPACE, `$11a4`
receives it, and the poll loop's `CMPA #$20` matches. The whole path works.

This did not show up as a working title, because Ys has further problems (P4-8),
which is why an earlier version of this entry wrongly recorded "no confirmed
improvement". Any game that services `$fd03` itself was losing keyboard input.

No regression: F-BASIC boots and runs (`print 12-3` -> ` 9`), Thexder's title is
pixel-identical to the reference, all 8 `run_tests.sh` rows pass. F-BASIC's I/O
also rises sharply -- `boot-basic` 777310 -> 1094418 cycles -- consistent with a
timer interrupt now being recognised. (A separate attempt to confirm through the
BASIC clock failed for a silly reason: `print time` is a syntax error, it needs
`TIME$` and the `$` needs shift.)

### $fd02 [FIXED] the interrupt-enable bits were inverted on 1 and 2 — 1942 was blank because of it

`$fd02`'s bits are interrupt **enables**: a set bit turns the source on. Both
references say so, despite MAME naming its variable `irq_mask`:

```c
MAME fm7.cpp:1098   if(m_irq_mask & IRQ_FLAG_TIMER) main_irq_set_flag(...)
CSP  fm7_mainio.cpp:482   if((val & 0x04) != 0) irqmask_timer = false;  // enabled
```

The core was **internally inconsistent** — the same write meant "enable" on one
bit and "disable" on the next two:

| bit | source | was | refs |
|---|---|---|---|
| 0 | keyboard | `KEYINn = ~(m132 & m77[0])` — set = enabled | set = enabled ✓ |
| 1 | printer | `LPMASKn = m77[1]` → set = **disabled** | set = enabled ✗ |
| 2 | timer | `TMMASK = m77[2]` → set = **disabled** | set = enabled ✗ |

Both consumers treat their input as an active-high mask (`CLKCTRL.v:107`
`m50_1 <= TMMASK`, `PERIPHERAL.v:127` `LPINTn <= LPMASKn`), so enabling on a set
bit means inverting in `KEYBOARD.v`. The `m77` reset moved `3'b110` -> `3'b000`,
which leaves reset behaviour **unchanged** — with the inversion, 0 now means the
"masked" that 1 used to — and matches CSP resetting every `irqmask_*` to true.
Bit 0 was already right and keeps its reset value, so the keyboard still routes
to the sub.

**Scoped before changing anything.** `$fd02` writes over eight titles:

| title | writes | bit 2? |
|---|---|---|
| **1942** | `$00`, `$05`x11 | yes |
| Hydlide II | `$00`, `$05` | yes |
| Ys | `$00`, `$05` at `pc=$116f` and `$2897` | yes |
| **Thexder** | `$00`, `$04` | yes — timer only |
| Penguin-kun Wars | `$00`, `$40`x4 | no — bit 6, rxrdy |
| Yellow Lemon | `$00`, `$40`x2 | no — bit 6 |
| Thunder Force, Xanadu | `$00`, `$01` | no |
| Relics | `$00` | no |

(That also kills the old claim that "Ys writes `$fd02 <- $40`". It writes `$05`;
`$40` belongs to the blank titles.)

**Result — 1942 was blank and now renders its title screen and menu**, logo plus
`1PLAYER`/`2PLAYERS` and `HIT X KEY`, 3790 -> 5880 bytes at the same 700-frame
sweep settings. It writes `$05` eleven times, i.e. it kept asking for a timer
interrupt the core kept refusing. This was predicted before the run, not fitted
afterwards.

No regressions:

| check | result |
|---|---|
| Hydlide II | screenshot **byte-identical**, counters moved |
| F-BASIC (4 rows) | screenshots **byte-identical**, +83 main/frame, +70k I/O |
| Thexder, 2450 frames | title animation completes **identically** at frame 2400; only the animated background's dither phase differs; rates within 1% |

Thexder was the one to watch — it writes `$04` and is the pixel-exact reference.
Its screenshot does move, so `shots-ref` was re-blessed here; the fixed-frame
shot lands at a different point in a screen that animates once the ISR actually
consumes cycles.

**It does NOT fix Ys, which was predicted and wrong.** What it does is move Ys
one link along: its timer ISR now runs **11554 times instead of 1**. It still
gives up immediately, for a separate reason — see the `$fd03` entry below.

### $fd03 [NEXT] reading it clears the flag before the CPU can latch it

Ys's handler is the ordinary "which source?" dispatch:

```
$117d  LDA  $fd03     ; a = $ff, every single time
$1180  BITA #$04      ; timer bit, active low
$1182  BEQ  $1195     ; -> timer handler. NEVER TAKEN
$1184  BITA #$01      ; keyboard bit
$1186  BEQ  $1189     ; never taken
$1188  RTI            ; gives up
```

`$fd03` reads `$ff` — "no source is requesting" — so `$1195` never executes,
which is what P4-8 recorded without a cause, and `$11e2 STA $ffe5` never runs.

The race:

```verilog
PERIPHERAL.v:121  assign IRQCLRn = RFD03n & RESETBn;   // low for the WHOLE read
CLKCTRL.v:108     if (~IRQCLRn) m50_1 <= 1'b1;         // every CLKSYS cycle while low
```

`CLKSYS` is 48 MHz against a 1.2288 MHz E, so the flag clears a cycle or two into
the read and the combinational readback at `CLKCTRL.v:126` presents the cleared
value for the rest of it — which is when the CPU latches. CSP captures first and
clears afterwards, explicitly:

```c
val = irqstat_reg0 | 0xf0;   // capture FIRST
irqstat_timer = false;        // clear AFTER
return val;                   // pre-clear value
```

Fix is to clear on the **trailing** edge of `IRQCLRn`, once the CPU has taken the
data. That keeps the property the comment at `CLKCTRL.v:89-99` cares about — the
strobe is many `CLKSYS` cycles wide, so its trailing edge cannot be missed. It is
the mirror of the `$fd37` lesson: capture writes on the leading edge, clear reads
on the trailing edge.

### $fd37 multi-page [verified] — the open "needs a check" item checks out

Checked because a wrong display mask produces exactly the Ys symptom below:
some artwork drawn, the rest black. It is correct end to end.

| stage | code | verdict |
|---|---|---|
| decode | `MDECODE.v:100` asserts `WFD37n` for `$fd37` | writable (was not, before the fix recorded there) |
| capture | `FLAGS.v:242` latches on `negedge WFD37n` — **leading** edge, data valid | right edge |
| split | `m46[2:0]` CPU-access mask, `m46[6:4]` display mask | matches MAME `data & 0x77` and CSP `accessmask/dispmask` |
| polarity | `PAL.v:63` `clr1 = DPAGE1 \| m25_3` — set bit **blanks** the plane | mask semantics, correct |
| reset | `m46 <= 8'h0` | all planes visible and writable, sane |

`m25_3 = ~(SVDOFFn & SBLANKn)` is video-off/blanking, so the term reads "plane
masked **or** blanked" — correct. No change needed. Note `FLAGS.v:242` is still
an async decode-strobe latch, so it remains on the derived-clock list for the
hardware side even though its behaviour is right in sim.

### P4-8 [NEXT] Ys renders and plays; the play field inside the border is black

> **Heading corrected.** This section was titled "Ys deadlocks: main waits for
> the sub, sub waits for the main". It does not deadlock. See the correction
> below the measurements.

**The deadlock, measured.** Over 1200 frames Ys's main CPU reads `$fd05`
**899932 times** and sees bit 7 clear on **36** of them — 99.996% of the run it
is parked in the F-BASIC ROM's sub-busy wait:

```
$f899  LDA <$05      ; DP=$fd -> $fd05
$f89b  BMI $f899     ; reads $fe, bit 7 SET
```

Sampling the PC at frames 400, 800 and 1200 finds it there every time. Meanwhile
the sub sits at `$c03e  LDB -1,U / BEQ $c03e` — the byte-wait loop, waiting for
the main to hand it the next byte. **Main waits for the sub to go not-busy; the
sub waits for the main to send data.**

**It is NOT the BUSY flag change (`9fc762b`), and that had to be checked because
the symptom is exactly the hazard that change introduced.** Rebuilding with the
pre-`9fc762b` semantics — BUSY held cleared while halted, set only by the sub's
own `$d40a` write — gives an **identical** distribution, 899896 `$fe` against 36
`$7e`. The flag is not what is holding bit 7. Only 34 halt/release pairs occur
in that window, so `~SHALTACn` is not it either; BUSY is being set by the sub's
own `$d40a` writes and simply not cleared for long stretches, under either
design.

So the sub is *genuinely* busy, and the question is what it is busy doing. It
writes `$d40a` 1414 times and reads it back 1417 times over 2000 frames, so the
handshake cycles — but between a write and the matching read it spends a very
long time in `$c03e`.

**Ys's own ISR runs exactly once in 2000 frames.** `$117d`-`$1194` each show a
count of 1 in the PC profile, and the timer branch at `$1195` never executes at
all. That single entry was a keyboard interrupt that took `BMI $1194` and
returned without storing. So the periodic work Ys expects — including
`$11e2 STA $ffe5`, the only in-game writer of the flag the `$1113` loop polls —
never happens.

Note `TMMASK` is *not* the cause: Ys writes `$fd02 <- $40`, so `m77[2:0] = 000`
and `TMMASK = 0`, which in `CLKCTRL` means `m50_1 <= 0` on every `_2MS` tick,
i.e. the timer IRQ is **enabled**. The CC trace also shows `I` clear for part of
the run, so interrupts are not permanently masked either.

**The deadlock is the SAME ONE as the P4-16 `$fd76` cluster, which makes this
one problem across at least three titles rather than three problems.** Sampling
Ys's sub PC early in the run:

| frame | main | sub |
|---|---|---|
| 150 | `$f899` | `$fd7a` |
| 200 | `$f899` | `$fd80` |
| 250 | `$f89b` | `$fd82` |
| 300-350 | `$f89b` | `$fd7e`/`$fd82` |

`$fd7a`-`$fd82` is the sub monitor ROM's input wait — the `$fd76` loop P4-16
records for Penguin-kun Wars and Fairie's Residence. So all three sit in exactly
the same place: **sub in the monitor's input wait, main in the F-BASIC ROM's
sub-busy wait.** Neither can move.

The `$fd76` loop only exits on `$d000` (written by the sub's IRQ handler at
`$e06e`, i.e. the main's *attention*) or `$d004` (the keyboard FIRQ handler at
`$fdac`). Ys never sends attention — it writes only `$80`/`$00` to `$fd05`,
never `$40` — so the keyboard is the only way out.

**⚠ THE TWO PARAGRAPHS THAT STOOD HERE WERE WRONG. Ys is not deadlocked, and it
is not the same problem as the P4-16 blanks.** They claimed the `--key
'820:@SPACE'` is what breaks a deadlock, and that "without that keypress Ys is
blank." Both are false — and the refuting evidence was **already in this file**. P4-16's
sweep sends no keys, and it scored Ys at **35880 bytes** (see the P4-16 table),
which is the title screen. That number sat a few sections away from the sentence
"without that keypress Ys is blank" for the entire investigation without the
contradiction being noticed. The key was inherited from the original repro line
and never questioned.

**Method note, worth keeping:** a repro line's flags are part of the claim. When
a title's behaviour is being characterised, run it with the flags *removed* at
least once — otherwise an inherited flag silently becomes a premise.

Measured directly, at frame 1980, two runs differing only in the key:

| run | png | what is on screen |
|---|---|---|
| **no key at all** | 35997 | the **title screen** — "Ancient Ys Vanished Omen", full artwork |
| `--key '820:@SPACE'` | 18650 | the **in-game screen** — ornate border, `H.P 020/020`, `EXP 00000/00200`, `GOLD 01000`, PLAYER/ENEMY gauges |

So Ys boots on its own, draws its title screen unaided, and the keypress does
what a keypress at a title screen normally does: **advances past it into the
game.** It is not escaping a deadlock, and the smaller PNG is the plainer game
screen, not a worse one.

The early sampling above (`$f899` / `$fd7a`-`$fd82` at frames 150-350) is real,
but it is a **boot-phase transient**, not a terminal state — Ys leaves it. Read
as a deadlock only because no one sampled late or ran the no-key case.

**The P4-16 cluster is a separate population, not "three instances of this."**
All 17 genuine blanks were re-run with a 6-key schedule (`300/500/700/900/1100/1300`,
SPACE and RETURN): **0 of 17 moved** — every one still 3790-3817 bytes, blank.
Ys renders without any key; they render with six. Whatever holds them is not
what Ys was doing.

**Remaining Ys defect: the play field inside the border is black.** The HUD,
border and gauges all draw correctly, so VRAM writes and the sub's display path
work. That is a much narrower bug than "deadlock" and is what P4-8 should now
track.

#### Re-derived on the fixed core

This section used to warn that the `$1113` lead was traced on the broken core
and had to be re-derived. Done -- 2600 frames, `--key '820:@SPACE'`, `--pc-profile`.
It is still the loop, and it is now the top of the histogram:

| addr | insn | count |
|---|---|---|
| `$1113` | `TST $ffe5` | 1266096 |
| `$1116` | `BMI $1120` | 1266096 |
| `$1118` | `TST $28e9` | 1266096 |
| `$111b` | `BEQ $1113` | 1266062 |
| **`$1120`** | the `BMI` exit | **2** |

`$1120` is reached exactly **twice** in the whole run, both early, then never
again. Sub-side, `$c03e`/`$c040` (`LDB -1,U` / `BEQ $c03e`) take 7.83 M hits each
-- **86.6% of every sub instruction executed** -- so the sub is parked waiting for
a byte.

**The ISR runs exactly once, and the store never runs at all.** Every address in
`$117d`-`$1194` shows a count of exactly 1, and **`$11e2` — the `STA $ffe5` —
does not appear in the histogram at all.** So the flag `$1113` polls is never
written after boot. The open question is now specific: *why does Ys's interrupt
fire once and never again?*

**Two candidate causes eliminated, both by measurement:**

*`$ffe0-$ffef` is not mis-mapped* — P3-5 flags it and Ys touches it, so it looked
compelling. It is wrong. `poke65509,170:?peek(65509)` prints **170**, and the
boot ROM's own accesses round-trip in the trace:

```
0 mem  W $ffe5 <- $3c   ... pc=$fef2
0 mem  R $ffe5 -> $3c   ... pc=$ff04
```

CSP agrees that region is RAM: `mainmem_readseq.cpp` returns
`fm7_mainmem_bootrom_vector[]` for `$ffe0-$fffd`, and `mainmem_writeseq.cpp`
writes it **unconditionally** — no `#if`, no `boot_ram_write` guard. (Careful
reading the CSP map: the `$fe00`/`$ffe0` split at `fm7_mainmem.cpp:218` sits
inside `#if defined(_FM77AV40EX)` and is *not* the plain FM-7 path. The FM-7
boot ROM is `$FE00-$FFEF` per `fm7_common.h:19`.)

*Not a display-mask or palette fault* — the stalled run reports `$fd37 = $00`
(all three planes visible), identity palette `0 1 2 3 4 5 6 7`, display on. The
play field is black because nothing drew it, not because it is masked. See the
`$fd37` section above.

**Also seen, unexplained:** Ys touches four ports the core does not decode --
`$fd25`, `$fd27`, `$fd29`, `$fd2b`, exactly **7 accesses each**. Even counts on
four adjacent odd addresses looks like a hardware probe rather than anything in
the stall loop, but it has not been chased.

Everything below predates P4-15 and was measured on a core where `$8000-$fbff`
read as zero. Re-derive before relying on it.

### P4-8-old [superseded] Ys draws its HUD now, but still never enters its loaded program

**[UPDATED after the BUSY fix]** With `9fc762b` (P4-13) Ys stops being a blank
screen. At frame 1980, with `--key '820:@SPACE'`, it renders **its in-game
furniture**: an ornate full-screen border, and a status bar reading
`H.P  /   EXP  /   GOLD` with `PLAYER` and `ENEMY` gauge bars. 4550 main / 6543
sub per frame.

```sh
cd vsim && ./obj_dir/Vemu --headless --bootrom 0 \
    --disk "Ys (FM7) (Disk A).d77" --key '820:@SPACE' \
    --stop-at-frame 2000 --screenshot 1980
```

**The central finding below still stands, though: execution never reaches
`$8000-$dfff`.** A `--pc-profile` over 2000 frames puts every hot address in
`$02xx`, `$08xx`, `$10xx`-`$15xx` and `$ff4x`:

| address | count | |
|---|---|---|
| `$1155`/`$1158` | 884839 | **now the hottest thing in the run** — the halt-the-sub routine |
| `$1113`-`$111b` | 662283 | a two-flag wait loop, see below |
| `$15ef`/`$15f1` | 589824 | |
| `$ff4d`/`$ff4f` | 317491 | boot ROM |
| `$1026`-`$102f` | 113422 | the key-wait loop from before |

*(Careful with the "fetched from: RAM 8384178 ROM 720498" line in the run stats
— it is tempting to read 92%-from-RAM as "it is running the program it loaded
into `$8000+`", and that is wrong. `$1113` is RAM too. Only the histogram
answers this.)*

**The new lead is the wait loop at `$1113`:**

```
$1113  TST  $ffe5
$1116  BMI  $1120        ; leave when $ffe5 goes negative
$1118  TST  $28e9
$111b  BEQ  $1113        ; else keep spinning
```

Ys is waiting on two flags that never change, and `$ffe5` is in the `$ffe0-$ffef`
RAM window (see P3-5). Meanwhile the sub sits in `$c03e  LDB -1,U / BEQ $c03e`,
the byte-wait loop. So the shape is now "main is driving the sub hard and waiting
for a completion flag that never arrives" rather than the old "two healthy idle
loops". Start from who is supposed to write `$ffe5` and `$28e9`.

Everything below predates the BUSY fix and was measured against the broken
completion handshake, so re-check it before building on it.

### P4-8-orig [superseded] Ys runs its own code for thousands of frames and draws nothing

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
is drawing, and what it draws is blank. **Stop looking at the video path.**

**What the main CPU is actually doing** (PC histogram over frames 3000-3010, so
long after loading finished). Not one tight loop -- it cycles through three
places, and all three are healthy:

```
$1471  ADDD ,S          3359x   a counted delay loop
$1473  LEAY -1,Y
$1475  BNE  $1471

$1180  BITA #$04        706x    an interrupt handler
$1182  BEQ  $1195
$1194  RTI
$1195  DEC  $11a3               every-Nth-interrupt counter
$1198  BNE  $1194
$119a  JSR  $11b7               ...do the periodic work
$119f  STA  $11a3               reload = 2

$11e9  LDA  $18,X       1048x   a sound driver, channel state at $165c
$11ec  ANDA #$c0
$11ee  CMPA #$c0
$11f3  DEC  $21,X               note duration countdown
$11f9  LDA  $1e,X               reload from the pattern
$11fc  STA  $21,X
```

Ys is sitting in an idle state with its timer interrupt and music player running
normally.

**`$1440` is not a wait, and is not worth chasing.** `LDB 6,X` / `BITB #$40`
looks like a ready-flag poll, but X there only ever takes `$1612`, `$1637`,
`$165c` -- three structures `$25` apart, the same `$165c` the sound driver at
`$11e9` walks. It is the music player iterating its three channels. (Recorded
because it reads convincingly as a handshake and it is not one.)

**Input is not what it wants either**: feeding SPACE, RETURN and joystick
fire/A at frames 820-3000 changes nothing, screen still blank at 3580.

**[UPDATED after P1-6]** The `$fd03` fix moved this on substantially. Ys now
accepts the keypress, hands the sub CPU a command through the shared window
(`$1155` waits on `$fd05`, halts, writes `$14` to `$fc80`, releases), and then
**runs a second disk-load phase** -- execution appears in `$0100-$03ff`, the
boot-sector loader, which never happened before:

| frame | before the fix | after |
|---|---|---|
| 800 | `$10xx` `$11xx` `$12xx` `$13xx` `$14xx` `$15xx` | `$10xx`, **`$15xx` 905403** |
| 1000 | the same fixed pattern | **`$01xx`, `$02xx` 120111, `$03xx` 3281**, `$11xx`, `$15xx` |
| 1200+ | the same fixed pattern, forever | **`$11xx` only** |

**The second load succeeds and hands off to the sub CPU.** Traced through:

```
$02c4  LDA  <$18 / ANDA #$9f / BEQ $02d3   ; error check -> clean
$01ec  CLRA                                 ; return code 0 = success
$01ed  PULS CC,DP,PC
$1043  LDX  #$2000                          ; back in Ys's own code
$1046  JSR  $1120
$1120  LEAY $2400,X                         ; Y = $4400
$1124  BSR  $1155                           ; halt the sub
$1126  LDA  #$06                            ; command $06
```

`$2000` and `$4400` are **sub-side VRAM addresses** (`$0000-$5fff` is VRAM), so
Ys is telling the sub to draw what it just loaded. Then it settles into `$11xx`
alone -- ISR and sound driver -- and never reaches `$8000-$dfff`.

**The sub side now works too, and the protocol is clear.** Ys uploads a payload
through the shared window rather than just poking a command:

```
$1126  LDA  #$06
$1128  STA  $fc80      ; command
$112b  CLR  $fc81
$1133  LDB  #$78       ; 120 bytes
$1135  LDU  #$fc82     ; into the window, +2
$1138  LDA  ,X+        ; from $2000
$113a  STA  ,U+
$113d  BNE  $1138
```

120 bytes into `$fc82`-`$fcfa`, which fits the 128-byte aperture exactly.

Traced on the sub side: it leaves the ROM idle loop at `$e13e`, consumes the
commands (`CLR $d382`, and acknowledgements `STA $d380` with `$07` then `$46`),
and by frame 1100 is executing at `$fd76` with **`x=c000, y=c7d0`** -- pointers
into the `$c000` region where a game's own sub code lives (Thexder's sits at
`$c054`/`$c133`). It sits in a masked wait loop there polling `<$00` and `<$04`
in DP page `$d0`.

So before P1-6 the sub idled in ROM forever; now both CPUs are exchanging
commands and the sub is running game code.

**Neither CPU is deadlocked -- both are idle but serviced.** The sub waits at
`$fd76` with FIRQ masked/unmasked around the poll, and is interrupted regularly,
running a handler at `$febf`:

```
$febf  LDA <$0a / BNE $fec5 / BSR $fec8 / CLR <$0a / RTI
$fec8  LDA <$1c (=01) / BEQ / BMI / DEC <$1d / BNE ...
```

-- a periodic tick doing countdowns in DP page `$d0`. Meanwhile the main sits in
`$11xx` doing its own timer and music work. So this is not a hang on either
side: it is two healthy idle loops, each waiting for a state change the other
never produces.

**The sub's three interrupt sources, and why none of them wakes it.** From
`SCPU.v`: `nIRQ = SUBIRQn` (main's attention), `nFIRQ = KSTROBEn` (keyboard),
`nNMI = SCLKNMIn` (display). Checked all three against the references; **all
three are implemented correctly**, so the P1-6 hypothesis does not repeat here:

- **IRQ / attention.** `$fd05` latches `{MDATABUS_in[7:6], MDATABUS_in[0]}` into
  `m9`, giving bit 7 -> `SUBHALTREQn` and bit 6 -> `CANCELn`, which matches CSP
  (`sub_halt = val & 0x80`, `sub_cancel = val & 0x40`, `fm7_mainio.cpp:744`).
  Correct -- but **Ys only ever writes `$80` and `$00`**, so it never uses the
  attention bit at all. Nothing to fix; it simply is not the wake-up path.
- **FIRQ / keyboard.** `KSTROBEn = ~(m132 & ~m77[0])` and
  `KEYINn = ~(m132 & m77[0])` make the main and sub keyboard interrupts mutually
  exclusive on `$fd02` bit 0. CSP does exactly the same: bit 0 set enables the
  main IRQ (`irqmask_keyboard = false`) and the same write drives the sub with
  `SIG_FM7_SUB_KEY_MASK`, where `firq_mask = !flag` (`display.cpp:2134`). Since
  Ys takes the keyboard on the main side (P1-6), the sub's FIRQ is *correctly*
  masked.
- **NMI / display** is the one that does fire -- it is what runs the `$febf`
  handler.

So the sub is left waiting on `$d000`/`$d004` with only its NMI running, and
nothing in the hardware is wrong about that. The remaining question is a
software-flow one: what was supposed to give the sub work after the 120-byte
upload, and why the uploaded routine is not what ends up running. Start from the
sub's NMI handler at `$febf` and find what it does with `<$1c`/`<$1d` and
whether it ever dispatches to `$c000`.

**A trap this nearly caused, twice in one session:** the sub reads `$d380 = $14`
at frames 1074-1075 and Ys writes `$06` at frame **1076**. Comparing those two
directly "shows" a write that never landed. It is the same window mistake as the
truncated `--trace-max` runs -- always check the frame numbers line up before
concluding a value did not propagate.

The original measurement, kept because the method is the useful part -- bucketing
main-CPU execution by address page over frames 780-1600:

| frame | `$10xx` | `$11xx` | `$12xx` | `$13xx` | `$14xx` | `$15xx` |
|---|---|---|---|---|---|---|
| 700 | 134144 | -- | -- | -- | -- | -- |
| 800 | 139288 | 124910 | 44324 | 1810 | 141879 | 14112 |
| 900 | 6539 | 158684 | 53672 | 1923 | 178706 | 16556 |
| 1000 | 6183 | 151346 | 57772 | 1678 | 176165 | 19972 |
| 1500 | 6518 | 158102 | 54047 | 2104 | 178688 | 16610 |

Two things fall out:

1. It settles at **frame ~900** and the distribution is then identical bin after
   bin, to within a few percent. A fixed steady state, not slow progress.
2. **Execution never leaves `$1000-$15ff`.** Nothing runs in `$8000-$dfff` --
   the 24 KB the loader placed there through the `$fd0f` RAM window -- nor in
   `$6000`.

So Ys loads its program correctly and then never transfers control to it. That
is the whole bug, and it is a much narrower target than "blank screen": find the
jump into `$8000+` that should happen around frame 900 and does not. The
`$14xx` routine is the busiest caller and the obvious place to start.

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

### P0-2 [FIXED] `ROMS.v` boot-ROM select needed a reset *edge*, not a level

**Fixed** — the flip-flop is now an ordinary synchronous reset-and-load on
`CLKSYS`, with the `$fd0f` read and write strobes edge-detected in the same
block (read still wins over write, as before). That removes the dependency on a
Quartus power-up state entirely.

**This one cannot be proved by simulation, and that is the point of it.** `vsim`
manufactures the very edge the old code needed — `sim_main.cpp:986` holds reset
LOW for 64 cycles and only then asserts it — so the machine boots either way in
the simulator. What the regression can show is the absence of a *regression*,
which it does: all 8 rows unchanged. The actual failure mode only exists on
hardware, where `FM-7_MiSTer.sv` takes `reset = RESET | status[0] | buttons[1]`
and `sys/` asserts `RESET` from the first clock.

Original description below.

### P0-2-orig [verified] `ROMS.v` boot-ROM select needs a reset *edge*, not a level

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

### P2-1 [FIXED] Shift, Ctrl, Graph and Kana all work

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

**CTRL, GRAPH and KANA are now in too**, transcribed from
`refs/common-src-project/src/vm/fm7/keyboard_tables.h` (`ctrl_key`,
`ctrl_shift_key`, `graph_key`, `graph_shift_key`, `kana_key`,
`kana_shift_key`). MAME's `fm7_key_list` is *not* a usable reference here; its
own comment says the shift, ctrl, graph and kana columns are unfilled.

Three things about that transcription are worth knowing:

- **The CSP tables are keyed on the FM-7's own physical key number**, an index
  into `vk_matrix_106`, not on PS/2. Each entry has to be translated through the
  same PS/2 → physical-key correspondence the unshifted table already
  establishes. Keys the FM-7 has and a PS/2 keyboard does not — KANJI, the JIS
  `\_` key beside right shift, CONVERT/NONCONVERT and the numeric keypad — have
  no entry, which is why some physical numbers are missing.
- **Precedence is CTRL > GRAPH > KANA > plain**, with SHIFT selecting the
  `_shift` variant within each. That is CSP's order in `scan2fmkeycode`
  (`keyboard.cpp:157-183`) and it matters: with both CTRL and GRAPH down, a real
  machine sends the control code.
- **KANA is a LOCKING key, not a held modifier.** CSP toggles it on press and
  drives a keyboard LED from it, alongside CAPS (`keyboard.cpp:117-125`).
  Software expects kana mode to persist across keystrokes. GRAPH and CTRL are
  momentary.

`graph_shift_key` is byte-identical to `graph_key` except for the four cursor
keys and the function keys, so those differences are folded in inline rather
than duplicating a 50-entry table.

**Verified by reading the codes the sub CPU actually latches.** Note that
F-BASIC routes the keyboard to the *sub* at `$d401`, not to `$fd01` — so a
`--trace-mem fd01-fd01` here shows nothing at all and reads exactly like a dead
table:

```sh
cd vsim && ./obj_dir/Vemu --headless --bootrom 0 --key-hold 4 \
    --key '400:@CTRL+ac' --stop-at-frame 560 \
    --trace-mem-sub d401-d401 --trace-from 395
#   401 smem R $d401 -> $01   pc=$fdae      ctrl-a
#   409 smem R $d401 -> $03   pc=$fdae      ctrl-c
```

| | delivers |
|---|---|
| `@CTRL+ac` | `$01`, `$03` |
| `@GRAPH+ac` | `$95`, `$82` |
| `@KANA` then `ac` | `$c1`, `$bf`; pressing KANA again returns `$61`/`$63` |

and typing `aiueokakikukeko` in kana mode renders half-width katakana on screen.

**`vsim` gained modifier chords for this**: `--key '400:@CTRL+ac'` holds the
modifier down for the whole string. Without it the tables are untestable, since
CTRL and GRAPH are momentary and `--key 400:@CTRL --key 410:a` releases CTRL
long before the `a` arrives and simply types a lower-case `a`. `@KANA+abc` works
too, but leaves kana mode on afterwards — which is what a real machine does.

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

### P2-3 [FIXED] Break key

`KEYBOARD.v` hardcoded `assign BREAKn = 1;` with the `9'h114` (right ctrl →
break) case commented out. The key now drives `BREAKn`; `TIMER.v` already ANDs
it into `FIRQn` and reports it on `$fd04` bit 1, so wiring the key was the whole
fix. MAME asserts `M6809_FIRQ_LINE` and sets its break flag together
(`fm7.cpp:1183-1189`), which is what this does.

Break is in `is_modifier`, so it delivers no scancode — correct, a real MB88401
sends nothing for it.

```sh
cd vsim && ./obj_dir/Vemu --headless --bootrom 0 --key-hold 8 \
    --key '450:@BREAK' --stop-at-frame 560 --trace-mem fd04-fd04 --trace-from 440
# $fd04 -> $fd   (bit 1 low) while held
```

Note the *volume* of those reads — ~16000 over the 8 held frames, against 1 read
in the whole run before the key. That is the level-sensitive FIRQ firing
repeatedly while break is down and the handler reading the cause register each
time, which is correct behaviour and not a spin.

77AVEMU makes a point that is not yet modelled here: reading `$fd04` clears the
*attention* FIRQ but deliberately **not** the break FIRQ ("Probably break-key
FIRQ not", `fm77avio.cpp:668`). Ours matches, since break comes straight from
the key state rather than from a latch.

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

### P3-2 [FIXED] `$fd04`'s attention latch was held cleared except during its own read

An earlier version of this entry said the latch "exists and correctly drives
`FIRQn`, and its async clear does fire on the read, but its state is never
presented on the data bus". The second half was right; the first half was
**wrong, and backwards**. The asynchronous preset was

```verilog
wire m47_q11 = RESETBn & ~RFD04n;
wire s2 = ~m47_q11;
always @(posedge m76_q6, posedge s2) ...
```

`s2` is HIGH whenever `$fd04` is *not* being read, so the flag sat held cleared
at all times **except** inside the read window. An attention could only ever be
captured if the sub happened to read `$d404` during exactly the cycles the main
was reading `$fd04`, so in practice the main CPU never received an attention
FIRQ at all. Bit 0 then reported `m47_q11`, which is 1 throughout any read of
`$fd04` — a constant "no interrupt pending".

All three references agree on the intended behaviour, including the polarity:

| | |
|---|---|
| **MAME** | `attn_irq_r` sets `attn_irq` and asserts `M6809_FIRQ_LINE` (`fm7_v.cpp:77`); `fd04_r` returns `$ff` with bit 0 cleared, then zeroes the flag |
| **CSP** | `get_fd04`: `if(!firq_sub_attention) val |= 0x01;`, then `set_sub_attention(false)` (`fm7_mainio.cpp:661`) |
| **77AVEMU** | `MAIN_FIRQ_SOURCE_ATTENTION=0x01`, `byteData = ~firqSource`, and reading `$fd04` clears ATTENTION but not the break key |

Now set on the sub's read of `$d404` and cleared on the **trailing** edge of the
main's `$fd04` read, so the value is stable for the whole bus cycle — an
asynchronous clear asserted across the read is the P0-1 race in a different
costume. Set wins over clear, as with `KEYBOARD.v`'s `m132`.

**No title measured moves.** Thexder, Hydlide II, The Castle and OS-9 all make
**zero** `$d404` accesses over 700-900 frames, so nothing currently asks for an
attention interrupt. This is a correctness fix, not a fix for a visible symptom.

*(Measurement trap hit while establishing that: `grep -c d404` over a
`--trace-mem-sub` log returns a healthy-looking count of matches that are
**cycle counters** containing `d404` as a hex substring — `cycles 86d4041
reading D0`. Anchor on the trace format, `grep -cE 'smem .* \$d404'`, or the
answer is confidently wrong.)*

**Bit 2 is left alone, and no reference agrees with it.** `TIMER.v` returns
`{5'b11111, BUSY, BREAKn, m45_q8n}`, i.e. BUSY at bit 2. MAME's `fd04_r` leaves
that bit set; CSP ORs in `0x7c` for a plain FM-7 and puts sub-busy at **bit 7**;
77AVEMU returns `~firqSource`, so bits 2-7 all read 1. Two of three also
disagree with CSP about bit 7. This core is schematic-derived rather than
modelled on any of them, and nothing measured reads the bit, so it is recorded
here rather than churned on a disagreement between references.

### P3-3 [FIXED] Kanji ROM (`$fd20-$fd23`)

`MDECODE.v` did not decode `$fd20-$fd23` at all and `rtl/roms/` held no kanji
ROM. Both are now in: `rtl/KANJI.v`, with the decode alongside `WFD37n` in
`MDECODE.v`.

**It was never actually blocked, and an earlier version of this entry was
wrong to imply otherwise.** `refs/fm7.zip` — a MAME ROM set sitting in the repo
— contains `kanji.rom`, 131072 bytes, **crc32 `62402ac9`**, an exact match for
MAME's `ROM_LOAD_OPTIONAL("kanji.rom", 0x0000, 0x20000, CRC(62402ac9))`. Unlike
the four FM-7 ROMs this core already uses, MAME does **not** mark it
`BAD_DUMP`. It had simply never been extracted. Worth remembering when
something looks ROM-blocked: check `refs/*.zip` first.

The interface, on which MAME and CSP agree exactly:

| | |
|---|---|
| `$fd20` write | glyph address, high byte |
| `$fd21` write | glyph address, low byte |
| `$fd22` read | first byte of the 16x16 glyph |
| `$fd23` read | second byte |

with the ROM index being `(address << 1) | bytesel` — MAME `kanji_r`
(`fm7.cpp:1054`), CSP `data_table[(kanjiaddr.d << 1) & 0x1ffff]`
(`kanjirom.cpp:83`). `$fd20`/`$fd21` are write-only and `$fd22`/`$fd23`
read-only; the write-only pair is deliberately not decoded for reads, so it
falls through to `core.v`'s `~IOSn ? 8'hff` default, which is what MAME returns.

**Two traps avoided, both of which this project has already paid for once:**

- The address register latches on the **leading** edge of the write strobe. The
  `$fd37` register latched on the trailing edge and read back `$00` for ever
  (P1-4) — a 74LS374 captures there on the schematic and the 6809's data-hold
  window covers it, but in zero-delay RTL the CPU has already released the bus.
- The read strobes are qualified by `RDEn`, which `core.v` wires to `RDQEn` —
  the strobe that spans the edge `mc6809i` latches on. An `E`-qualified read
  strobe is P0-1, and it has cost three separate bugs (P0-1, P0-4, P4-1e).

**Verified end to end from F-BASIC**, `$fd20` = 64800 through `$fd23` = 64803:

```
poke64800,8:poke64801,5
print peek(64802);peek(64803)
 238   68              <- $ee $44, exactly kanji.rom[$0805 << 1]

poke64800,16:poke64801,0
print peek(64802);peek(64803)
 0   16                <- $00 $10, exactly kanji.rom[$1000 << 1]

print peek(64800)
 255                   <- $ff, write-only, as MAME returns
```

Two different addresses, so this is not a fixed value. `run_tests.sh` unchanged.

**Two things to know about the cost.** The ROM is 128 KB = **1 Mbit of block
RAM**, against roughly 5.5 Mbit of M10K on the DE10-Nano's Cyclone V — a real
fraction of the budget, and it wants watching after the flip-flop blowup that
`d5b09ca` had to fix in the FDC sector index. And the kanji ROM is *optional*
expansion hardware on a real FM-7 (MAME loads it `ROM_LOAD_OPTIONAL`, CSP gates
it behind `connect_kanjiroml1`), so **software probes for it** — making it
present can change what a title does. The 8-row regression is unchanged, but a
re-sweep against P4-14's numbers is the honest check and has not been run yet.

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

So `bootrom 1/2/3` selecting bank 2 is why disks looked unbootable.

**[FIXED]** `ROMS.v` now instantiates the whole 2 KB chip once and addresses it
as `{SW2, MADDRBUS[8:0]}`, so setting N selects bank N. The two loose 512-byte
images are no longer used.

That also retired a hack. The old mux read

```verilog
wire [7:0] m152_q = |SW2 || &MADDRBUS[15:4] ? m152_2_q : m152_1_q;
```

where `&MADDRBUS[15:4]` forced `$fff0-$ffff` from the DOS image whatever the
setting. The reason: **`boot_bas.rom` is a bad dump.** Its last two bytes are the
reset vector and they read `$ffff` instead of `$fe00`, so a machine booting from
it fetched a garbage RESET and the hack papered over it. Every bank of the real
chip carries `RESET=$fe00`, so nothing needs forcing. (Checked byte for byte:
bank 0 differs from `boot_bas.rom` in exactly those 2 bytes; bank 2 differs from
`boot_dos_a.rom` in 30, so they are the same revision family but not identical.)

**Payoff: OS-9 Level 1 now boots.** With `--bootrom 2` it prints

```
* OS-9 Kernel Started !
```

where before it fell back to cassette BASIC on every setting. It stops at the
kernel banner rather than reaching a shell, so there is more to do, but the
kernel runs. That is a second operating system on the core.

`run_tests.sh` after the change: `boot-basic`, `boot-dos2`, all three `basic-*`
and `disk-Thexder` are **unchanged**; `boot-dos1` (5795 -> 6571) and `boot-dos3`
(-> 6711, and 0 I/O cycles, since bank 3 is the empty one) now reach banks that
were previously unreachable.


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

### P4-4 [FIXED] The tape download dropped every second byte

**Fixed:** `$fd02` now matches MAME (bits 6-4 forced high, printer lines tied
high instead of read from the undriven `CN2`, and bit 7 reads high when the
motor is off). End-of-tape works — a run now stops at `$03a3b4 of $03a3b6`,
exactly the 238518-byte image size, where it used to run on to `$081392`.
`addr` powers up at `$16` instead of `$62`.

**Fixed, and it was none of the three remaining suspects.** Not sample
polarity, not the motor-on lead-in, not `LOAD""` vs `LOAD"`. **Every second
byte of the .t77 never reached SDRAM**, so each entry's level was right but its
duration read back as the high byte of the next entry's -- almost always 0.
The whole 238 KB image played out in about 3 seconds instead of 41.7, and
F-BASIC never saw a sync tone it could lock to.

The measurement this section asked for is the one that found it. `$fd02` was
being read hard (a tight loop at `pc=$f381`) and bit 7 *did* toggle, which by
the rule below puts it in the "pulse widths do not match" branch. `make
DEBUG_TAPE=1` (new, `rtl/t77_decode.v`) then printed the entries as they were
actually latched:

```
T77 entry 1 addr=$0000012 data=$0001 -> level=0 len=0      <- file has 01 1c
T77 entry 2 addr=$0000014 data=$00a0 -> level=1 len=8192   <- file has a0 8e
T77 entry 3 addr=$0000016 data=$0000 -> level=0 len=0      <- file has 00 19
```

Even bytes correct, odd bytes zero. `T77SUM` gave `summed_len=47360` against the
image's 4571863 ticks.

**Two separate causes, one per top level.**

*vsim:* `SimBus::BeforeEval` held `ioctl_wr` high for as long as `ioctl_wait`
was low, advancing to the next byte each cycle. Both SDRAM models EDGE-detect
`we`, so whenever `ready` stayed high for two cycles there was no new request
and that byte vanished. `ioctl_wr` is a one-shot now, with a forced gap between
bytes -- which is what `sys/hps_io.sv` already does on hardware
(`ioctl_wr <= wr; wr <= 0;`).

*FPGA:* `ioctl_wait` was **not connected at all** -- an input to `hps_io` with
no driver, so the HPS was told "never wait" while the SDRAM controller dropped
what it could not take. It is driven from `sdram_ready` now, the same
expression vsim uses. The tape path is also gated on `ioctl_index == 1` now
(`tape_download`) rather than raw `ioctl_download`, so the SDRAM write port and
the rewind pulse belong to the tape alone, as vsim has always had it.

**Verified on hardware** with `Space Warp.t77` mounted over MGL index 1:
`load"` at the F-BASIC prompt gives `Searching` -> `Found: STR` -> `Ready`, and
`LIST` shows the loaded program (lines 430-530, `PRINT`/`LINE`/`PSET`,
`INT(RND(1)*4+1)`). Note the FM-7 is a JIS layout: `"` is **Shift+2**, not
Shift+apostrophe, which types `*` and earns a `Syntax Error`.

Historical detail, kept because the reasoning below is still sound: the three
causes eliminated before this were the `$fd02` bits, the end-of-tape overrun,
and the CPU clock rate (P0-5), and none of them was it.

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

### P4-5b [read] Printer port

*(Numbered P4-5b because there are two P4-5 sections: this one and the fixed
`(int)main_time` overflow far above. Renumbering either would break the commit
messages and cross-references that already cite them, so they are left as they
are and disambiguated here.)*

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

Everything in the original list here is now done — P0-4, P2-1, P0-2's sibling
P3-6b, P1-3, P3-2 and P4-1 all closed — so this is the current one.

1. **P4-10** — OS-9's console. The kernel runs and a cursor now appears; input
   never lands. Start from "which keyboard route does its driver expect", since
   OS-9 never writes `$fd02` to choose one.
2. **P4-8 / P4-7** — Ys and CHAN.POP. Both are "the program is loaded correctly
   and control never reaches it", which is the same shape and may share a cause.
   Re-check both against the BUSY fix (P4-13) before digging: they were both
   diagnosed while the completion handshake was broken.
3. **P0-2** — decide the reset story so the FPGA build does not depend on a
   power-up flip-flop state. Still open, still cheap, and it is the one item
   here that only bites on real hardware.
4. **P3-3** — the kanji ROM. Nothing decodes `$fd20-$fd23` and there is no ROM
   image in `rtl/roms/`; needed for any real Japanese text.
5. **P4-1's remaining media work** — second drive, 2DD, multi-disk `.d88`.
6. **P1-2** — resolved as not applicable for the FM-7, but revisit if the core
   ever grows FM-77 support.
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
