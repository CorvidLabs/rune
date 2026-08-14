---
change: CHG-0023-bump-json-to-2-21-2-resolving-dependabot-alert-1
artifact: plan
---

# Plan

1. `bundle update json --conservative` to bump only `json`, keeping every other resolved version
   unchanged.
2. Drop the incidental `BUNDLED WITH` line the local bundler version would otherwise add to
   `Gemfile.lock` (out of scope; would pin a bundler version CI's Ruby 3.0-3.4 matrix doesn't use).
3. `bundle check`, `fledge run lint`, `fledge run test`.
