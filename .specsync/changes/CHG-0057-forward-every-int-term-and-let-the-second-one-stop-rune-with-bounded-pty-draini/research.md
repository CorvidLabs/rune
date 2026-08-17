---
change: CHG-0057-forward-every-int-term-and-let-the-second-one-stop-rune-with-bounded-pty-draini
artifact: research
---

# Research

Comparable wrappers — `timeout`, `docker run`, `ssh` — all forward the signal and let a
*second* one terminate the wrapper itself. That is the model adopted here.

Two constraints pull against each other and had to be reconciled rather than traded off:

- A human pressing Ctrl-C twice must get their terminal back.
- A child that needs a second Ctrl-C (an agent CLI interrupting a turn) must still receive it.

They reconcile because the second signal is forwarded to the child *before* rune begins its own
teardown, and because the escalation counter is scoped to a burst rather than to the whole run: two
lone interrupts ten minutes apart are two independent first signals, not an escalation.

The interactive case turned out not to depend on this path at all, which was worth confirming rather
than assuming. Under `rune watch` the terminal is in raw mode, which clears `ISIG`, so a human's
Ctrl-C never becomes a SIGINT for rune — it travels to the child as a `0x03` byte through the
input-forwarding thread and the child's own pty line discipline. Verified against a real controlling
terminal: three Ctrl-Cs, three interrupts delivered to the child, session still running. The ladder
only ever sees signals sent to rune from outside (an init system, another process).

A second, unrelated defect surfaced while verifying the fix against the real CLI, and it dictated
the shape of the reaper. On macOS, a pty child SIGKILLed while bytes it wrote are still unread in
the pty buffer wedges permanently in the kernel's exit path — `ps` reports `?Es`. Measured
directly: a blocking `Process.wait2` never returns, `WNOHANG` polling never succeeds, waiting three
minutes does not help, and reading the pty master clears it instantly. This is the ordinary shape of
an abort, because the last thing a child does on its way out is usually to print something.
