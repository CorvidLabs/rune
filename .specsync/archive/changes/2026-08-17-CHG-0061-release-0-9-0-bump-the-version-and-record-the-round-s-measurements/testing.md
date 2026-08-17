---
change: CHG-0061-release-0-9-0-bump-the-version-and-record-the-round-s-measurements
artifact: testing
---

# Testing

The gates: 526 examples, 0 failures; rubocop clean across 72 files; `docs-check`
reports "Guides are current with 0.9.0"; `specsync check` 5/5 specs, 100% file and
LOC coverage.

Beyond the gates, this round was measured against live children rather than
fixtures — `python3 -q` as a control, and `grok` and `kimi` as the real thing:

    every field-report item re-run against grok        16/16 pass
    the same against kimi                              16/16 pass
    boundary probes (--since, names, grep, dup start)  22/22 pass
    three attachers + one deliberately stalled, 4.1MB  no wedge
    41.7MB through one session                         rotation observed
    a real task driven end to end through grok         matched in 5811ms

Three of this session's findings turned out to be harness errors, not defects:
`--json` appended after the `--` separator and forwarded to the child exactly as
documented; a liveness helper that ignored `status` and read a correct refusal as
a dead session; and a UNIX socket path over the 104-byte `sun_path` limit, which
rune itself handles by binding a basename from the session directory.
