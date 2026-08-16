---
change: CHG-0055-turn-the-provenance-gate-off-and-record-why-instead-of-leaving-it-to-fail
artifact: context
---

# Context

The provenance gate has never worked as intended in this repository, in two opposite ways within the
same week.

For three releases it was **skipped without consequence**: v0.4.0, v0.5.0 and v0.6.0 each failed the
check inside `Publish Gem Package`, after the tag existed and the release was announced, and
nobody noticed — because the only thing gated on it is a GitHub Packages gem that nothing installs.
The Homebrew formula builds from the tag tarball and the rubygems.org job is disabled.

CHG-0053 then moved the same check earlier, into the release lane, so it could not fail silently.
That worked exactly as designed, and the result was that it **blocked the release** instead: cutting
0.8.0 required a human to sign three commits by hand first.

So the gate was either invisible or in the way, and never in between. That is the argument for
turning it off.
