# Working notes for Claude

Read `docs/REFERENCE.md` before touching anything. Its measurement-traps section
is a list of mistakes that each produced a confident wrong answer at least once
in this project. **More bugs here were mis-diagnosed than were hard to fix.**

## Documentation philosophy

Documentation in this repo is **reference, not narrative**. A doc file earns its
place by being true next month and useful to someone who wasn't here.

**Git already stores history. Code comments already store why a fix is shaped
the way it is. Docs must not duplicate either.**

### Keep

- **Facts about the machine.** Register layouts, bit meanings, memory maps,
  timings — with citations to `refs/` as `file:line`.
- **Where the references disagree**, which one we follow, and why. This is the
  most reusable knowledge in the project.
- **Measurement traps.** Anything that produced a confident wrong answer. Keep
  the *specifics* — the exact grep pattern, the exact byte count, the exact
  flag. A trap summarised into generality is useless.
- **Build and tooling gotchas** that will bite again: CRLF-mandatory files,
  which file list is canonical, which directory a tool must run from, which
  flags silently don't apply.
- **Verification method.** How to tell a real regression from a measurement
  artifact.

### Delete

- **Per-bug investigation logs** once fixed. The conclusion belongs in a code
  comment next to the code; the journey belongs in the commit message.
- **Superseded sections.** Do not keep `X-orig`, `X-old`, `X-superseded`
  alongside `X`. If a claim was wrong, state the corrected fact and add one
  parenthetical line — *"(superseded claim: the vectors are ROM — disproven,
  poke/peek round-trips)"* — so nobody re-derives the wrong version. Then delete
  the rest.
- **Phase plans, task breakdowns, effort estimates, milestones.** These go stale
  faster than anything else and read as authoritative long after they aren't.
  Keep the *research* a plan was built on; drop the plan.
- **Status narratives.** "Fixes this session", "Done", "Suggested order".
- **Sweep prose.** Keep the result `.tsv` files as data; drop the write-up.

### Shape

- **One `TODO.md`, open work only.** If it's fixed, it leaves. No status tags as
  section headings.
- **One `Readme.md`** that orients a newcomer: what this is, current state, how
  to build and run, repo layout, where the docs are.
- **Reference files in `docs/`**, one per durable topic, each under ~300 lines.
- When a doc passes ~500 lines, that is a signal it has started accumulating
  narrative. Split the reference out and delete the rest.

### When you change behaviour

- If a regression reference changes, **say why in the same commit**. A blessed
  reference with no explanation is indistinguishable from an unnoticed
  regression later — that is exactly how `shots-ref/` rotted three months behind
  the core while the suite compared nothing and still exited 0.
- If you were wrong earlier, **correct the doc in place and say so plainly**.
  Leaving a wrong claim next to the right one costs the next person a day.

## Engineering practice specific to this core

- **Measure before you fix.** Four attempts were spent on one register acting on
  plausible mechanisms that were never observed; each produced byte-identical
  output. Printing the actual waveform settled it in one attempt.
- **Byte-identical output after a change means suspect the build first.** That is
  what a patch which never reached the binary looks like.
- **A null result from one title says nothing about a register**, only about that
  title. Check a workload that actually exercises the path.
- **A grep returning nothing is a claim about your pattern**, not about the
  machine. Print raw lines first, then narrow. Never pipe a trace through
  `head`/`tail` — trace lines and the run summary live at opposite ends.
- **An inherited flag in a repro command becomes an unexamined premise.** Run the
  no-flag case once before characterising behaviour.
- Sim proves "behaviour unchanged". Only hardware proves the glitch-domain
  classes. Say which one you have.
