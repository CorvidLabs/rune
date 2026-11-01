---
change: run-the-specsync-archive-gate-before-every-ci-job
artifact: testing
---

# Testing

- Both edited workflows parse with `Psych.safe_load`, and printing each job's
  `needs` shows `archive-gate` with no needs and every other job
  (`verify`, `spec-sync`, `intent` in `ci.yml`; `trust` in `trust.yml`) needing it.
- `bash .github/scripts/archive-readiness.sh .` from CorvidLabs/spec-sync at
  `106aaa43` run against this checkout reports the open changes under
  `.specsync/changes/`, which is what the Archive job will do in CI. It passes
  only once every change, including this one, is archived.
- `spec/release_version_check_spec.rb`, the only spec that reads a workflow
  file, reads `publish-package.yml`, which is unchanged.
- `specsync change audit --strict` no longer reports the workflow paths as
  uncovered.
