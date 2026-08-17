# Harnesses

Measurement harnesses kept as evidence, not as maintained source. They are
excluded from rubocop deliberately: reformatting them would edit the thing that
produced the numbers quoted in `CHANGELOG.md`.

- `echo_children.rb` — every child shape the settle rule has to be right about,
  in one place. This corpus is the reason three separate candidate rules were
  caught before shipping. Its own header records the mistake that was made once
  while building it: a probe whose marker appears in the input scores green for
  free, because the echo alone satisfies the check.
- `bench.rb`, `blaster.rb`, `drain.rb`, `multiturn.rb` — throughput and
  turn-accounting measurement for the send path.
- `adversarial.rb`, `veto.rb`, `mutants.rb` — the shapes a fix has to keep
  working, and mutation checks that a guard is load-bearing rather than dead.
- `transcript_gaps.rb` — every shape a dropped region can take (none, a
  rotation's prefix, one mid-stream hole, several, a rotation over one) with a
  cursor before, inside and after each, measured against an oracle built from
  the layout rather than from the code under test, and the rotation accounting
  measured against the bytes the child produced. Prints a before/after table and
  exits non-zero on any disagreement, so it doubles as a check.

These are run by hand against a scratch `RUNE_HOME`. They are not part of the
test suite and are not expected to pass lint.
