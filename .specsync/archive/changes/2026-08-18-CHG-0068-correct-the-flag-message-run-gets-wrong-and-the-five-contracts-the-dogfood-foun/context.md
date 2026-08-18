---
change: CHG-0068-correct-the-flag-message-run-gets-wrong-and-the-five-contracts-the-dogfood-foun
artifact: context
---

# Context

The last five findings from the nine-language translation dogfood. Each was
re-verified independently before anything was touched, and the question asked of
every one was code-or-documentation.

That question is the whole point. A sibling finding claimed `--settle-ms` was
broken because it is inert under `--wait-for-regex`; the code was right and a
comment recorded why, and "fixing" it would have reintroduced a measured bug.
So: all five confirmed, and **four are documentation**.

    rank4  run bounds clean_output and raw_output into different windows   DOCS
    rank6  --grep help names a match surface it does not have              DOCS
    rank7  the unknown-flag message misdiagnoses a space-separated value   CODE
    rank9  omitted_bytes reconciles only on ASCII                          DOCS
    rank10 --max-output does not bound screen                             DOCS

I predicted rank4 would need code and was wrong. The per-field budget is a
stated contract in four places — the flag itself says "BYTES each" — and a
caller sizing a context window wants both fields under the cap. What is missing
is any statement of the consequence: a pty turns `\n` into `\r\n` and raw keeps
its escapes, so the same budget lands at different points and `clean_output` is
not `strip_ansi(raw_output)`. Measured at `--max-output=200` on a 5,200-byte
fixture: metadata says 5000, raw`s own marker says 5070, and with colour a whole
line of the child`s output was in one field and absent from the other.
