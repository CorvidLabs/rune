## MODIFIED

### SPEC SECTION Invariants

22. `data[:prompt_detected]` reflects only the *last* non-blank line of the finished output
    buffer (ANSI stripped), not whether any line anywhere in the run ever matched a prompt
    pattern. `rune run`'s result is only ever read after the wrapped process has already exited or
    been killed by `--timeout`, so this is the question that's actually useful: "was the last
    thing on screen a prompt, with nothing after it" — the signature of a process genuinely stuck
    waiting for input, since by definition nothing else arrives after that line. A prompt-shaped
    line that appears mid-run as ordinary TUI chrome, followed by further real output, does not
    set `prompt_detected` (found via real dogfooding driving a long-running third-party TUI
    sub-agent, where the old "any line ever" semantics made the field `true` on every run and
    therefore useless — issue #30). This holds identically across a natural exit, a
    `PTY::ChildExited` short-circuit, and a `--timeout` kill: the last-line check runs against
    whatever `raw_output` was captured up to the point execution stopped, in every case.
23. No output at all, or output consisting only of blank/whitespace lines, yields
    `data[:prompt_detected]: false` — never a crash from an absent "last line".
24. No trapped signal is ever swallowed. Every INT/TERM caught while a child is running is
    forwarded to that child, in arrival order, for as long as the run lasts. The forward callable
    used to latch after its first successful forward, so signals two onward reached neither the
    child nor `rune` itself: measured as a `rune run` absorbing 4x SIGINT + 2x SIGTERM over three
    seconds and leaving only when its own `--timeout` fired 15s later, and as a `rune watch`
    (which has no default timeout) surviving 5x SIGINT + 5x SIGTERM and needing SIGKILL. Signals
    are queued rather than held in a single slot, so two arriving inside one 0.2s poll interval
    are both delivered instead of overwriting each other.
25. The second INT/TERM within `SignalHandler::BURST_WINDOW_SECONDS` ends the run, the same
    escalation `timeout`, `docker run`, and `ssh` use: it is forwarded to the child *first* — a
    child whose second Ctrl-C interrupts a turn still receives it — and only then is
    `SignalHandler::Aborted` raised out of the polling loop. `rune` unwinds to a well-formed
    result rather than dying mid-render: the child is reaped, the capture keeps everything it
    printed on the way out, `[rune] Interrupted by SIG<NAME>` is appended, and the reported exit
    code is the conventional `128 + signo` (130 for INT, 143 for TERM). A single signal is still
    the child's alone — it is forwarded and `rune` keeps waiting, so the traps continue to do what
    they were installed for instead of `rune` dying instantly and orphaning the child. Signals
    further apart than the burst window are independent first signals, so a long-lived session
    legitimately interrupted once now and once ten minutes later is not torn down by the second.
    Once `rune` has aborted, INT/TERM are restored to their default dispositions, so a third
    signal during teardown kills `rune` outright — deliberately, as the last escape hatch.
26. Every wait on a signalled child is bounded, and the child's pty is drained while it dies.
    Both are load-bearing on macOS rather than defensive: a pty child SIGKILLed while bytes it
    wrote are still sitting unread in the pty buffer wedges *permanently* in the kernel's exit
    path (`ps` reports `?Es`), and from there it is never reapable again — a blocking
    `Process.wait2` never returns, `WNOHANG` polling never succeeds, and waiting minutes does not
    help; only reading the pty master clears it. This is the ordinary shape of an abort, because
    the last thing a child does on its way out is usually to print something, and it hung the real
    CLI for over three minutes on a 20-second `--timeout` before the drain existed. The abort path
    therefore reaps from inside the read loop, where the reader is still open. `--timeout`'s kill
    path is bounded for the same reason but cannot drain — Ruby's internal timeout exception is
    not a `StandardError`, so it cannot be caught while the reader is still in scope — so it gives
    up on a wedged child rather than blocking forever.

