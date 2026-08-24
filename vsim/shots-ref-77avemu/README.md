# 77AVEMU renders of the gate, at the same instant as `shots-ref/`

One PNG per `run_tests.sh` row, rendered on CaptainYS's 77AVEMU
(`tools/77avemu_headless.cpp`) from the same media, in the same machine mode, at
the same point in machine time as the core's blessed screenshot in
`../shots-ref/`. File names match `shots-ref/` exactly, so the two sets join on
filename.

Regenerate with `vsim/sweep/ref-gate.py`, which holds the media list, the key
sequences and the frame conversion in one place.

It needs a harness built from the **current** `tools/77avemu_headless.cpp` —
`--stop-at-frame` and the `SHIFT+` key prefix are both new. Rebuild with
`tools/build_77avemu_headless.sh <77avemu-build-dir>` and either replace
`refs/local/fm77av_headless` or point `FM77AV_HEADLESS` at the new binary. An
older binary does not silently misbehave: it reads `--stop-at-frame` as a
positional, prints its usage and exits 2, and `ref-gate.py` reports the row
FAIL.

And per trap 51, whenever that binary is rebuilt, prove it reproduces the old
one before trusting a number from it — render a title you already have a shot
for at a fixed step count and `cmp` the PNG. It was byte-identical on the AV
demo across this rebuild.

## These are NOT a gate

`run_tests.sh` does not look at this directory and must not. The two renderers
disagree on output geometry — 77AVEMU line-doubles 640x200 to 640x400 and emits
320x200 for the 320 modes (trap 32) — and on the DAC: `PAL.v` expands a 4-bit
gun level as `{n,$F}` where 77AVEMU replicates the nibble, so every non-black
pixel differs and a byte comparison reports 100% mismatch while carrying no
information (trap 27). `vsim/sweep/compare-ref.py` is the tool that scores core
against reference; these images are what it scores against.

## Scoring against them

`compare-ref.py` and `score.py` both expect a sweep directory laid out as
`<dir>/shots` and `<dir>/ref-shots`, so point one at these two:

```sh
cd vsim
mkdir -p /tmp/gate-vs-ref
ln -sfn "$PWD/shots"              /tmp/gate-vs-ref/shots
ln -sfn "$PWD/shots-ref-77avemu"  /tmp/gate-vs-ref/ref-shots
sweep/compare-ref.py /tmp/gate-vs-ref
```

`shots/` is `run_tests.sh`'s own output from the last run, which is the same
image as `shots-ref/` whenever the gate is green. `score.py` wants a
`results.tsv` it will not find here, so `compare-ref.py` is the one to reach for.

## The frame these were taken at, and why it is not 620

**620** is `FRAMES`, where the core's *run* stops. **600** is `SHOT_AT`
(`FRAMES - 20`), where the core's *picture* is taken. Only the picture matters
here, so the instant to reproduce is vsim frame 600.

The two machines do not agree on what a frame is:

| | a "frame" is | rate |
|---|---|---|
| vsim | a real raster frame off the core's video timing, 16 MHz over a 1024 x 262 raster (`sim_main.cpp:73`) | 59.63740 Hz |
| 77AVEMU | exactly 1/60 s of `vm->state.fm77avTime` (`tools/77avemu_headless.cpp`, `FRAME_NS`) | 60.00000 Hz |

so

    reference_frame = vsim_frame * 60 * 1024 * 262 / 16000000
                    = vsim_frame * 1.00608

which is exact, not a rounded constant — 60 * 1024 * 262 = 16,097,280 over
16,000,000. It is +6 frames per 1000: 3.8 frames at the gate's 600 (**604**, and
that is what these were rendered at), 12 at the sweep's 2000, 22 at 3700.
Nothing in the tree corrected for this before; the harness's own header comment
used to claim the two frame numbers "mean the same thing here and in vsim",
which was wrong by 0.61 % and is now corrected in place.

The `--stop-at-frame N` option added to the harness for this ends the run when
`vm->state.fm77avTime / FRAME_NS >= N`, so the final screenshot is at a known
instant rather than after an arbitrary instruction count. The positional `steps`
argument still caps the run so a wedged one cannot spin forever; if the cap is
hit first the harness prints `WARNING: step backstop ... hit at frame N` and
`ref-gate.py` fails that row rather than saving a picture from the wrong moment.

## Rows

| row | media | mode | notes |
|---|---|---|---|
| `boot-basic` | none | `--fm7` | F-BASIC 3.0 banner and `Ready` |
| `basic-print` | none | `--fm7` | types `print 12-3`, prints ` 9` |
| `basic-keys` | none | `--fm7` | types `list` on an empty program |
| `basic-shift` | none | `--fm7` | `print 12+34` -> ` 46`, `print "HI!"` -> `HI!` |
| `disk-Thexder [b]` | `software/D77/Thexder [b].d77` | `--fm7` | title screen |
| `av-demo` | `software/FM77AV/2019_FM77AVDEMO_CaptainYS_V2.D77` | FM77AV | colour grid plus its banner |
| `av-kohakuiro` | `software/D77/Kohakuiro no Yuigon (FM77AV) (Disk 1).d77` | FM77AV | **black, and that is correct** |
| `av-wizardry4` | `software/D77/Wizardry IV (FM77AV) (Disk A).d77` | FM77AV | title screen and credits |

`av-kohakuiro` renders black on the reference from its own frame 500 onward, and
`shots-ref/av-kohakuiro.png` is black too, so the two agree. That is trap 29:
the row entered the gate on a rich-looking 18-colour picture that was an
artifact of a palette stuck at the identity ramp, and the corrected core matches
the reference's black screen instead. Keep the caveat with it — a black
reference scores 100% against a black core (trap 38), so agreement on this row
is not evidence of anything. It is here to catch the day one of them stops being
black.

## Rows deliberately absent

`boot-dos1`, `boot-dos2`, `boot-dos3`. They select one of the MiSTer core's
three DOS boot ROM images through `status[11:10]`. 77AVEMU has a single
BASIC-or-DOS switch (`FM77AVParam::DOSMode`) and the harness does not expose even
that — and the `BOOT_DOS.ROM` in `refs/local/fm77av-roms` is the 480-byte AV
loader from `rtl/roms/fm77av_boot_dos.rom.mem` padded to 512 bytes
(`tools/README-77AVEMU.md`), not the FM-7 DOS boot ROM. A render from it would
be a picture of the ROM staging, not of the machine, which is worse than no
render.

The tape rows are absent for the same reason `run_tests.sh` keeps them out of
the default sweep: a tape plays in real time.

## Reproducing a `--key` row

vsim's `--key` takes a whole string and expands it; 77AVEMU's takes one physical
key per option, so `ref-gate.py` expands the string with the same
character-to-key choice `sim_main.cpp:ascii_to_ps2` makes (JIS: `+` is
shift-`;`, `"` is shift-`2`, `!` is shift-`1`, an upper-case letter is
shift-letter) and the same press/release schedule `schedule_key_action` lays
down, then converts every frame number individually.

**Modifiers are a prefix, not a key.** `FM77AVKeyboard::Press` takes the
modifier state as its first argument; pressing `LEFT_SHIFT` as an ordinary key
sets `heldDown[]` and produces nothing. Scheduling a shift key around a
character therefore types the *unshifted* one — it turned `print 12+34` into
`print 12;34` and `print "HI!"` into `print 2hi12`, which reads as a keyboard
bug in the thing under test rather than as a harness limitation. `--key
F:SHIFT+2` is the working form.
