# Cohort sweep results

Raw per-disk agreement data from the cohort campaign (cohorts 03-06), kept as
data per the documentation rules. Cohort membership and retirement state live in
`../cohorts/`; this is what the sweeps measured.

`cNN-fm7` / `cNN-av` are the two machine routings of the same cohort — roughly a
quarter of the collection is AV software and must be swept as `fm77av`, so a
cohort is swept twice and each disk judged on its own machine. See
`docs/TESTING.md` for the screening step and `docs/HANDOFF.md` for what the
campaign has established.

These were regenerated from a scratch directory at the end of the session that
fixed the 6809 NMI recognition bug, so they predate that fix: they are the
"before" for cohorts 03-06, not a current measurement.
