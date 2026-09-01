# Program Pochette 1984 03 — transcription handoff

Date: 2026-08-31

## Current state

The durable work is under:

`magazines/Program Pochette 1984 03 (J OCR)/`

The six titles that were previously short text adaptations now have page-checked
source-derived `program.bas` files and regenerated `program.t77` cassette images:

| directory | printed pages | listing range |
|---|---:|---:|
| `kuruma-geemu` | 6–11 | 10–710 |
| `snake-apple` | 30–31 | 10–1000 |
| `kaminari-kozou` | 32–33 | 10–750 |
| `fukugan-test` | 37 | 100–310 |
| `star-7` | 38 | 10–110 |
| `fukushu-teki` | 39 | 10–200 |

`down-down` already had the largest best-effort transcription. It also has
`program-runnable.bas/.t77` and `program-77avemu.bas/.t77`; the latter replaces
only the initial `LINE(...,BF)` fill because 77AVEMU stalled there.

Each title directory has bilingual README documentation and a
`transcription-notes.md` file. The six new source-derived runs and captures are
named `*-faithful.log` and `*-faithful-gameplay-77av.*.png`.

## Validation

All six new `program.t77` files were generated with the tape builder and
exercised with the headless reference. **The builder is `tools/make_fm7_basic_t77.cpp`
and it has no build rule** -- it was built into `/tmp` and lost. Rebuild it into
the gitignored-but-persistent `refs/local/`, against the vendored 77AVEMU
sources, and it reproduces the shipped tapes byte for byte:

```sh
c++ -std=c++17 -O2 -o refs/local/make_fm7_basic_t77 \
  tools/make_fm7_basic_t77.cpp \
  refs/77AVEMU/src/t77lib/t77.cpp \
  refs/77AVEMU/src/fm7lib/cpplib.cpp refs/77AVEMU/src/fm7lib/fm7lib.cpp \
  -Irefs/77AVEMU/src/t77lib -Irefs/77AVEMU/src/fm7lib
```

The tape name argument is the **Japanese title**, truncated by the encoder to
the first 8 UTF-8 bytes -- `"カミナリこぞう"` for kaminari-kozou, `"Star 7"` for
star-7. Passing a different name changes the image, so recover it from the
existing `.t77` before regenerating one.

Run:

```sh
refs/local/fm77av_headless refs/local/fm77av-roms \
  'magazines/Program Pochette 1984 03 (J OCR)/TITLE/program.t77' \
  120000000 'magazines/Program Pochette 1984 03 (J OCR)/TITLE/faithful-gameplay-77av.png' \
  --fm7 --shot-every 1200
```

Five titles reached their listing-derived screens without a reported BASIC
error. `kaminari-kozou` reaches the original demo, but 77AVEMU reports
`Illegal Function Call In 660` for the printed line-660 `PLAY` string. The
faithful source intentionally retains that printed line; any emulator-specific
replacement belongs in a separate runnable variant.

The faithful capture names are:

- `fukugan-test/fukugan-faithful-gameplay-77av.png`
- `snake-apple/snake-faithful-gameplay-77av.png`
- `kaminari-kozou/kaminari-faithful-gameplay-77av.png`
- `kuruma-geemu/kuruma-faithful-gameplay-77av.png`
- `star-7/star-faithful-gameplay-77av.png`
- `fukushu-teki/fukushu-faithful-gameplay-77av.png`

## Fidelity boundary

These are manual, page-checked best-effort transcriptions, not certified
byte-identical dumps. Japanese text, FM-7 special glyphs, and some dense DATA
values were normalized to ASCII or `CHR$` forms so the cassette builder could
carry them. The per-title notes identify those judgments. The original page
snapshots in each directory remain authoritative.

## Next recommended work

1. Re-read the dense Kuruma, Snake, and Kaminari DATA rows against original
   FM-7 media or a higher-resolution source.
2. Make a separate `kaminari-kozou/program-runnable.bas/.t77` with a safe
   77AVEMU-compatible replacement for line 660, leaving `program.bas` faithful.
3. If exact byte identity is required, compare the generated BASIC token stream
   and glyph bytes against an original cassette rather than relying on OCR.

The page snapshots in each title directory are **150 dpi, one quarter of what
the PDF holds**. The scan is 600 dpi grayscale, so re-read any doubtful
character from the PDF rather than from those PNGs:

```sh
pdftoppm -f <page> -l <page> -r 1200 -x <x> -y <y> -W <w> -H <h> -png \
  "magazines/Program Pochette 1984 03 (J OCR).pdf" /tmp/crop
```

At that magnification the listing font's **slashed zero** separates `0` from
`O`, and `B` from `8` by its straight left stem -- both distinctions the 150 dpi
PNGs cannot carry, and both of which the first pass got wrong on kaminari's line
660.
