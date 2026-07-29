---
change: CHG-0007-document-homebrew-as-the-primary-rune-installation-channel-and-synchronize-the-c
artifact: context
---

# Context

Rune 0.2.1 is released and published to GitHub Packages, but the repository still tells users to
clone the source. CorvidLabs already maintains a public Homebrew tap with a Rune formula, although
that formula is pinned to 0.1.3 and is omitted from the tap's install and style gates.

This change makes the existing Homebrew channel accurate and discoverable. Runtime code and public
library behavior remain unchanged.
