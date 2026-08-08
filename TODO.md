# TODO

Open work only. Fixed items leave this file — the conclusion goes in a code
comment, the journey stays in the commit message. See `CLAUDE.md`.

Reference material: `docs/REFERENCE.md` (read first), `docs/IO_MAP.md`,
`docs/TESTING.md`, `docs/FM77AV.md`.

---

## Awaiting hardware

Four commits are on `alanswx/fdc-d77-support` and have **not** been confirmed on
real hardware. Simulation cannot settle the glitch-domain classes.

| commit | what | hardware risk |
|---|---|---|
| `e699e9d` | `SOUND.v` `$fd0d` off its derived clock | **only hardware can validate this** — the sim test (joystick reads 238) passes, but the bug class is invisible in Verilator |
| `77c2780` | `$fd02` enable-bit polarity | changes interrupt delivery for every title |
| `b1aff78` | `$fd03` acknowledge | changes interrupt acknowledge for every title |
| `777d8d4` | `$fd04` attention acknowledge | as above |

Sharpest checks: **Ys** should reach its town map and be playable; **1942**
should reach its title menu. Both were completely dead before.

`m77` in `KEYBOARD.v` remains on an async decode strobe. Three hardware attempts
to convert it all failed (0/8) and a sim experiment showed all four candidate
designs capture identical values at identical times — see `docs/REFERENCE.md`.
Leave it async unless there is new evidence.

---

## Next: audit the rest of the read-acknowledge registers

`$fd03` and `$fd04` both had the same bug — a read-clear register acknowledged on
the wrong one of the two strobes every `$fdxx` read produces. The mechanism is in
`docs/REFERENCE.md` and it is not specific to those two addresses.

**Unaudited candidates:**

- `$fd00` / `$fd01` — keyboard acknowledge (`KACKNGn`, `RFD01n`).
- The **sub-side** `SRDQEn` decodes in `SDECODE.v`. `SRDQEn` is built the same
  way as `RDQEn`, so the sub's read-clear registers are exposed to the identical
  split-strobe problem. `$d404`/`$d40a` are the interesting ones.

Both were invisible until measured; neither shows up in the regression suite.
Probe the strobe shape first (`$display` on every transition with `EB`), then
fix — do not reason ahead of the waveform.

---

## Per-title work

### Re-triage the remaining blanks

The old "17 genuine blanks" list is stale — P4-19 moved 25 titles and
Penguin-kun Wars fell out of it. Rebuild the list from
`vsim/sweep/results-P4-19-f1500.tsv` using the exclusion rules in
`docs/TESTING.md` before chasing anything.

Known-broken, cause identified, not fixed:

- **Wizardry / II / III** — `RUNAWAY-INTO-IO` in every sweep, before and after
  the interrupt fixes. Main CPU leaves its program. Same class as P4-15 but not
  the same cause.
- **Daisenryaku FM** — main CPU runs into page zero and dies on an illegal
  opcode at frame 143 (`$009f FCB $05`). A/B-confirmed as pre-existing: identical
  before and after the interrupt fixes.
- **CHAN.POP** — loads further than it used to, then runs off into low memory.

### Ys

Playable, but only characterised as far as the town map. Nobody has played
further to see what breaks next.

---

## Media support

- **Second drive.** Only drive 0 is served. Many `(Disk 2)` images in the
  collection cannot be reached at all, which caps the sweep.
- **2DD media** and **multi-disk `.d88`**.

These three together gate a large fraction of the collection — probably the
highest title-count-per-effort item after the register audit.

---

## Smaller open items

- **PSG pitch** needs a human ear. `SOUND.v`'s select was fixed but nobody has
  confirmed the notes are right.
- **Keyboard layout is JIS-positional, not US** — a decision, not a bug. Shifted
  punctuation lands where a JIS keyboard puts it, which surprises US-layout
  users. Decide whether to offer a translation.
- **`$fd06`/`$fd07`** claim to be an 8251 UART and are a stub. Nothing observed
  needs them yet.

---

## Not started

**FM77AV** as an OSD option. Hardware research is in `docs/FM77AV.md`; no
implementation work has begun. Worth doing on a confirmed FM-7 interrupt path
rather than an unconfirmed one, so it sits behind the hardware results above.
