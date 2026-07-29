#!/usr/bin/env bash
# Print the commit range the trust gate should inspect, and fail if it is empty.
#
# Both `fledge trust verify` and the Augur/Attest GitHub Actions default to
# `origin/main..HEAD`. On a feature branch that is correct. On `main`, where
# HEAD *is* origin/main, it resolves to zero commits and every gate reports
# success without inspecting anything:
#
#   augur verdict: proceed - risk 0/100
#   attest verify - [ok] PASS (0 commits checked)
#
# A gate that examines nothing must not report green. Push-event callers provide
# the exact before/after SHAs so every landed commit is covered; local callers
# fall back to the single landed commit and refuse outright rather than emitting
# an empty range.
set -euo pipefail

base_ref="${TRUST_BASE_REF:-origin/main}"
push_before_sha="${TRUST_PUSH_BEFORE_SHA:-}"
push_after_sha="${TRUST_PUSH_AFTER_SHA:-}"
zero_sha='0000000000000000000000000000000000000000'
range=""

if [ -n "${push_before_sha}" ] || [ -n "${push_after_sha}" ]; then
  if [ -z "${push_before_sha}" ] || [ -z "${push_after_sha}" ]; then
    echo "trust_range: TRUST_PUSH_BEFORE_SHA and TRUST_PUSH_AFTER_SHA must be provided together." >&2
    exit 1
  fi
  if [ "${push_before_sha}" = "${zero_sha}" ]; then
    echo "trust_range: push before SHA is all zeroes; refusing an unbounded initial-push range." >&2
    exit 1
  fi
  if ! git rev-parse --verify --quiet "${push_before_sha}^{commit}" >/dev/null; then
    echo "trust_range: push before commit '${push_before_sha}' is unavailable." >&2
    exit 1
  fi
  if ! git rev-parse --verify --quiet "${push_after_sha}^{commit}" >/dev/null; then
    echo "trust_range: push after commit '${push_after_sha}' is unavailable." >&2
    exit 1
  fi
  range="${push_before_sha}..${push_after_sha}"
elif git rev-parse --verify --quiet "${base_ref}" >/dev/null &&
   [ "$(git rev-list --count "${base_ref}..HEAD" 2>/dev/null || echo 0)" -gt 0 ]; then
  range="${base_ref}..HEAD"
elif git rev-parse --verify --quiet 'HEAD~1' >/dev/null; then
  range='HEAD~1..HEAD'
else
  echo "trust_range: HEAD has no parent and no commits ahead of ${base_ref}; nothing to gate." >&2
  exit 1
fi

count="$(git rev-list --count "${range}")"
if [ "${count}" -eq 0 ]; then
  echo "trust_range: resolved range '${range}' contains 0 commits — the risk and provenance" >&2
  echo "             gates would pass vacuously. Refusing to emit an empty range." >&2
  exit 1
fi

echo "${range}"
