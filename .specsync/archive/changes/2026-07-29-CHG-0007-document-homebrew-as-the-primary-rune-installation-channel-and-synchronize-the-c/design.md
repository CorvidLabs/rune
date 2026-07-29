---
change: CHG-0007-document-homebrew-as-the-primary-rune-installation-channel-and-synchronize-the-c
artifact: design
---

# Design

Use `brew install corvidlabs/tap/rune` as the primary installation path and retain source checkout
instructions for contributors. Document GitHub Packages as a release artifact rather than the
recommended end-user installation path because it requires package-registry authentication.

The external `CorvidLabs/homebrew-tap` repository owns formula checks and automated release
discovery. Rune's release guide owns the requirement that a published release is followed by a
reviewed, checksum-pinned tap update.
