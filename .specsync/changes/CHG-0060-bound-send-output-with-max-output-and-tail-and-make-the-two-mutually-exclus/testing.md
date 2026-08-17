---
change: CHG-0060-bound-send-output-with-max-output-and-tail-and-make-the-two-mutually-exclus
artifact: testing
---

# Testing

Four tests in `spec/rune/session_spec.rb`, each run against broken code before
being trusted:

    control                                 result
    revert the bounding wiring only         2 of 4 fail
    revert the mutual-exclusion check only  1 of 1 fails

After the fix, against a live `python3 -q` session emitting real SGR:

    send (no flags)         clean=8047  raw=25468  truncated=nil   bare-CSI=74*
    send --max-output 400   clean=227   raw=454    omitted=25068   bare-CSI=0
    send --max-output 120   clean=66    raw=170    omitted=25352   bare-CSI=0
    send --tail 3           clean=1213  raw=1278   omitted=300     bare-CSI=0

*the 74 are the literal `[1;32m` text of the probe's own python source being
re-echoed by readline, not an escape leak — confirmed by locating them. Bounding
cannot cut mid-escape into a bare parameter run, which was the shape of an
earlier reported leak.
