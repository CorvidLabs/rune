#!/usr/bin/env bash
# Emit squash-merge attestation forward pairs for every commit in a push range.
#
# For each landed commit SHA in BEFORE..AFTER, look up a pull request whose
# merge_commit_sha equals that commit (the GitHub API's view of a squash
# merge). Print one TSV row per match:
#
#   <pr-head-sha>\t<landed-sha>\t<pr-number>
#
# The CI trust gate fetches each PR head and runs `attest forward` so the
# reviewed provenance on the PR tip applies to the differently-hashed squash
# commit on main. A push with no associated PRs (direct push) emits nothing
# and is verified strictly on its own merits.
#
# Requires: git, gh (authenticated), network access to the GitHub API.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <before-sha> <after-sha>" >&2
  exit 2
fi

before_sha="$1"
after_sha="$2"
repo="${GITHUB_REPOSITORY:-}"

if [ -z "${repo}" ]; then
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  # Support both https://github.com/org/repo(.git) and git@github.com:org/repo(.git)
  if [[ "${origin_url}" =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
    repo="${BASH_REMATCH[1]}"
  else
    echo "squash_attest_forwards: set GITHUB_REPOSITORY or use a github.com origin remote." >&2
    exit 1
  fi
fi

if ! git rev-parse --verify --quiet "${before_sha}^{commit}" >/dev/null; then
  echo "squash_attest_forwards: before commit '${before_sha}' is unavailable." >&2
  exit 1
fi
if ! git rev-parse --verify --quiet "${after_sha}^{commit}" >/dev/null; then
  echo "squash_attest_forwards: after commit '${after_sha}' is unavailable." >&2
  exit 1
fi

# Walk landed commits oldest-first so stacked multi-PR pushes forward in order.
while IFS= read -r landed_sha; do
  [ -z "${landed_sha}" ] && continue
  row="$(
    gh api "repos/${repo}/commits/${landed_sha}/pulls" \
      --jq "map(select(.merge_commit_sha == \"${landed_sha}\"))
            | .[0]
            | select(.)
            | [.head.sha, \"${landed_sha}\", (.number | tostring)]
            | @tsv" 2>/dev/null || true
  )"
  if [ -n "${row}" ]; then
    printf '%s\n' "${row}"
  fi
done < <(git rev-list --reverse "${before_sha}..${after_sha}")
