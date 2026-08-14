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

### Staging the ROM directory

Mutsu wants **upper-case** file names, and the AV boot ROMs are not in the same
shape as the ones this core loads. Neither fact is obvious, and getting either
wrong makes the reference emulator fail in ways that look like a bad disk image:

```sh
R=/tmp/fm77av-roms
mkdir -p $R && unzip -o -q refs/fm77av.zip -d $R
( cd $R && for f in *.rom; do mv "$f" "$(echo $f | tr 'a-z' 'A-Z')"; done )

# BOOT_BAS.ROM / BOOT_DOS.ROM are 512 bytes. This repo carries them only as the
# 480-byte loaders AVMEM.v copies out of initiate.rom, as .mem text, so convert
# and pad. The AV boots from INITIATE.ROM, so the padding does not matter to an
# AV run -- it matters only that the files exist.
python3 - <<'EOF'
import os
R='/tmp/fm77av-roms'
for src, dst in (('rtl/roms/fm77av_boot_basic.rom.mem', 'BOOT_BAS.ROM'),
                 ('rtl/roms/fm77av_boot_dos.rom.mem',   'BOOT_DOS.ROM')):
    b = bytes(int(l, 16) for l in open(src) if l.strip())
    open(os.path.join(R, dst), 'wb').write(b + bytes(512 - len(b)))
EOF
```

Everything under `/tmp` is disposable, so expect to redo this and the build
after a reboot. Neither takes long.

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
