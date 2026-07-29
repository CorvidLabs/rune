---
change: CHG-0014-clarify-mixed-help-aliases-and-invocation-local-cli-modes-in-the-exact-cli-contr
artifact: context
---

# Context

The implementation and tests already guarantee that all pre-separator help aliases are consumed
and that a reused `CLI` object resets rendering modes. The canonical spec described both but did
not state the resulting mixed-alias error-case behavior or explicitly prohibit earlier output
flags from affecting a later invocation.

This exact semantic clarification is based on commit `e3b9064`, which contains the complete
accepted predecessor lifecycle.
