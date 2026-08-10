# 77AVEMU reference runner

`77AVEMU`/Mutsu is the independent FM77AV reference used for differential
triage. The checked-in driver runs a fixed number of 6809 instructions without
opening a window, prints periodic machine-state checkpoints, and can save a
PNG at the final state. It accepts the same `.d77`/`.d88`/`.t77` media used by
the Vemu sweep.

The reference sources and build tree are local inputs, not vendored into this
repository. Build Mutsu normally first, then build the driver:

```sh
tools/build_77avemu_headless.sh /tmp/fm7-77avemu-build
```

Run an FM77AV disk checkpoint:

```sh
/tmp/fm7-77avemu-build/fm77av_headless \
  /tmp/fm77av-roms \
  '/tmp/fm7-sweep-fresh/disks/Thexder [b].d77' \
  2000000 /tmp/thexder-77av.png
```

For an FM-7 disk or tape, add `--fm7`. Tapes automatically use Mutsu's
`TypeCommandForStartingTapeProgram()` after the initial ROM setup; pass
`--no-autostart` when comparing the raw boot/search path.

The `REF` lines are deliberately simple key/value records so a later sweep
wrapper can write TSV/JSON without parsing human-oriented CUI output. The first
cut reports instruction/time/PC, motor and tape pointer, plus an optional final
screenshot. It does not pretend to synchronize FM77AV's internal instruction
count with Verilator frames; comparisons should align on observable milestones
first, then on machine time where the two models expose it.
