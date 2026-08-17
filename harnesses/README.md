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
- `rotation_eacces.rb` — a rotation that cannot be written, on a real EACCES
  session directory. Reads FAIL against the ordering `rotate_output` used to
  have, which closed the caller's handle before it had a replacement.
- `whole_record_sweep.rb` — tears a record at every byte offset in every record
  shape and checks that `Store#whole_record?` and `Transcript.load` agree
  exactly. They feed rotation's head event and the stream reconstruction
  respectively, so any disagreement is a permanent, silent cursor skew.
- `orphan_report.rb` — SIGKILLs a real supervisor and checks what `list` and
  `archive` say about the child it leaves behind. Its header records two harness
  mistakes made while building it: `--json` placed after `--` goes to the child,
  and a child killed before its interpreter has installed a HUP trap dies with
  the pty hangup, which reads exactly like "orphans do not happen".

These are run by hand against a scratch `RUNE_HOME`. They are not part of the
test suite and are not expected to pass lint.
