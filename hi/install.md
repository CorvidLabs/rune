---
hi: 1
families: [INSTALL]
---

# Getting the tool

## Intent

rune is only useful once it is on the machine, and the first thing a newcomer does should not be the hardest. Getting it should be one step, with no toolchain to set up first, and that step has to be unambiguous about which rune it fetches, because the obvious name belongs to something else entirely. Upgrading later should be the same step again. Nothing about installing it should require reading the repository.

## Criteria

- **INSTALL-1**  I can install rune in one step, without cloning a repository or setting up a Ruby toolchain first.
- **INSTALL-2**  Following rune's own install instructions gets me this rune rather than an unrelated package that happens to hold the name.
  - **INSTALL-2.a**  What I install is pinned to something I can check, so I can tell it is what the maintainer published.
- **INSTALL-3**  I can move to a later release the same way I installed the first one.
- **INSTALL-4**  I can install rune into my task runner and call its verbs there the way I would at a prompt.
