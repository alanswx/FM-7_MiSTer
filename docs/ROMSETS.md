# System ROM sets

The FM-7's main ROM, boot ROM, character generator and sub-system monitor can
be replaced at run time from a file on the SD card, so one `.rbf` can be more
than one machine. This is how the Spanish **Secoinsa FM-7** is supported.

## The file

`boot1.rom`, in the core's directory next to the `.rbf`. MiSTer's main firmware
uploads `boot0.rom`..`boot3.rom` at core start with `ioctl_index = N << 6`
(`Main_MiSTer/user_io.cpp`, "check for multipart rom"), so:

| file | ioctl index | what this core does with it |
|---|---|---|
| `boot.rom` / `boot0.rom` | 0 | the 128 KB kanji ROM, as before |
| `boot1.rom` | 64 | the system ROM sets |

**It is optional.** With no `boot1.rom` the machine runs the ROMs built into
the `.rbf` and behaves exactly as it did before this existed. Nothing about an
existing install changes.

## Layout

Each set is 45056 bytes at a **65536-byte stride**. Set 0 is selected by the
`System ROM` OSD row's first entry, set 1 by its second.

| offset | size | ROM | what |
|---|---|---|---|
| `$00000` | 32768 | `m151` | main ROM / F-BASIC, `$8000-$FBFF` (31744 used) |
| `$08000` | 2048 | `m152` | boot ROM, 4 banks of 512 |
| `$08800` | 2048 | `m153` | character generator |
| `$09000` | 8192 | `m154` | sub-system monitor |
| `$0B000` | — | | pad to `$10000`, next set follows |

`rtl/ROMLOAD.v` and `tools/make-romset.py` both encode this table. Changing one
means changing all three.

Build a file with:

```sh
tools/make-romset.py -o releases/boot1.rom \
  --set fbasic300.rom,TL11_11_M152.rom.mem,subsys_m153.rom.mem,subsys_m154.rom.mem \
  --set secoinsa_fbasic.rom,TL11_11_M152.rom.mem,secoinsa_cg.rom,subsys_m154.rom.mem
```

Paths resolve against `rtl/roms/`; raw binaries and `$readmemh` `.mem` text are
both accepted, because some of these ROMs only exist in the repo as `.mem`.

## How it is applied

`ROMLOAD.v` copies the selected set out of SDRAM into the four block RAMs while
the machine is held in reset, then releases it. Changing the OSD row resets the
machine — swapping the BASIC ROM under a running interpreter is not a thing.

A file too short to hold a full set is ignored entirely (the baked ROMs stay);
a file holding only set 0 makes the set-1 selection fall back to set 0 rather
than page in whatever else is in SDRAM.

**Why SDRAM and not a second set of block RAMs.** `m151` is 32768 deep and
costs 32 M10K blocks on its own; a duplicate plus a duplicate character
generator is 34 of the 37 free blocks recorded in `TODO.md`'s FPGA fit section.
Staging in SDRAM costs **zero** blocks — measured, see that section — and the
SDRAM sets live at `$420000`, just above the kanji ROM, with ~30 MB spare.

The CPU cannot execute from SDRAM: it fetches every bus cycle, and the kanji
ROM was the only ROM that could move off-chip because it is read through a slow
I/O window that prefetches. So this is a copy into block RAM, not a redirect.

## The Secoinsa FM-7

The Spanish licensee's machine. Measured against the Japanese set, byte for
byte — **only two of the four ROMs actually differ**:

| ROM | Secoinsa vs Japanese |
|---|---|
| `m151` F-BASIC | **differs** — 430 bytes of 31744, in 24 clusters |
| `m153` character generator | **differs** — Latin glyphs where Japanese has katakana: `$A1` is `Ñ`, `$A2` is `Ç`, `$BF` is `¿` |
| `m152` boot ROM | identical |
| `m154` sub monitor | identical |

Derived from a three-file dump, kept for provenance as
`rtl/roms/FM7SecoinsaROMs.zip` (`FM7Secoinsa_8435.BIN`, `_8449.BIN`,
`_GPU.BIN`):

- `_8449.BIN` is a 32 KB EPROM holding F-BASIC at `$8000` (`$0000-$7BFF` of the
  file) and a 512-byte boot ROM image at `$FE00`.
- `_8435.BIN` is a 32 KB EPROM whose **top 10240 bytes are byte-identical to
  `subsys_c.rom`** (the Japanese `m153`+`m154`), with character-generator banks
  below. The bank at file offset `$0000` is the Spanish font; the bank at
  `$4000` is byte-identical to the Japanese `m153`.
- `_GPU.BIN` is **byte-identical to the Japanese boot ROM** `TL11_11_M152`,
  despite the name. It is not a GPU and not Spanish.

**Unresolved, and deliberately not guessed at:** `_GPU.BIN` says the Secoinsa
used the stock Japanese boot ROM, while `_8449.BIN` carries a diverged Spanish
one at `$FE00` (same code lineage, 56% agreement after correcting a 6-byte
insertion at offset 11). The set built above uses the Japanese `m152`. The
Spanish variant is extracted to `rtl/roms/secoinsa_bootbas.rom` and is not
wired to anything pending an answer from whoever dumped these.

**Not addressed:** the Secoinsa had a Spanish keyboard. This core's keyboard is
JIS-positional by decision (see `TODO.md`), and a ROM set does not change that.
