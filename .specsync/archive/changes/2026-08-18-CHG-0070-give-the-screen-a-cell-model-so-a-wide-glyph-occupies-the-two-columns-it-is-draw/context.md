---
change: CHG-0070-give-the-screen-a-cell-model-so-a-wide-glyph-occupies-the-two-columns-it-is-draw
artifact: context
---

# Context

The last of the five renderer gaps, and a correction of my own earlier conclusion
about it.

A cell model was built once before and reverted, and this spec recorded that it
had been "measured worse than the gap". **That was wrong.** The A/B compared two
working trees and misattributed which output came from which side. Re-measured
against three explicit revisions on the same 56,928-byte grok capture that had
emitted a CJK table:

    cc8bb3c  (one column)   "東h京   Tokyo"    "大 阪   Osaka"
    ad76e22  (one column)   "東h京   Tokyo"    "大 阪   Osaka"
    cell model             "東京  Tokyo"     "大阪  Osaka"

The one-column model corrupts real agent output and always did. An agent
positions its columns assuming two per CJK glyph; a renderer counting one puts
every later write in the wrong place. I had it backwards, reverted a correct fix,
and then wrote the mistake into the contract.

I also checked whether the four renderer fixes shipped since could be the cause,
by disabling each on top of `main` in turn — alt screen, DECAWM, IRM, charsets.
None of them changes the corrupted rows. It is the column arithmetic.
