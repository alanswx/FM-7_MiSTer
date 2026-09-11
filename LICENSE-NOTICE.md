# Licence

**This core ships as GPL version 3.**

The core's own files carry the MiSTer framework's grant — "version 2 ... or (at
your option) any later version". `rtl/jt12/` is jotego's jt12/jt49 under
**GPLv3-or-later**. Combining them is permitted by that grant, and the combined
work is therefore GPLv3. `LICENSE` is the GPLv3 text.

`jt03` is the FM77AV's YM2203 and also supplies the FM-7's PSG, so removing it
is not an option that leaves a working core. This is a one-way door and it is
already through.

`LICENSE-GPLv2` is kept because the per-file "version 2 or later" notices in
the core's own sources refer to it. It is not the licence of the combined work.

## Third-party contents

| path | origin | licence |
|---|---|---|
| `sys/` | MiSTer-devel `Template_MiSTer` | GPLv2-or-later |
| `rtl/jt12/` | jotego, jt12/jt49 | **GPLv3-or-later** |
| `rtl/mc6809*` | see file headers | per file |

## ROM images

`rtl/roms/` contains Fujitsu FM-7 and FM77AV ROM images, and `rtl/roms/secoinsa_*`
contains Secoinsa FM-7 images. These are **not** covered by the GPL — they are
included for the core to be usable, and their copyright rests with their
respective owners. They are baked into the `.rbf` at synthesis time unless a
`boot1.rom` ROM set overrides them; see [docs/ROMSETS.md](docs/ROMSETS.md).
