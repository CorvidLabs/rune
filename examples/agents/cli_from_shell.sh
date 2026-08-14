#!/usr/bin/env bash
# Driving rune from a shell, with no Ruby in sight.
#
#   bash examples/agents/cli_from_shell.sh
#
# Everything rune's library can do is reachable from the CLI, because every
# command returns the same JSON envelope on stdout. This is the integration
# path for an agent that shells out rather than requiring the gem.
set -uo pipefail

RUNE="${RUNE:-$(cd "$(dirname "$0")/../.." && pwd)/bin/rune}"
command -v jq >/dev/null || { echo "this example needs jq"; exit 1; }

# Sessions are keyed by RUNE_HOME; a temp one keeps this from touching real work.
export RUNE_HOME="$(mktemp -d)"
trap 'rm -rf "$RUNE_HOME"' EXIT

heading() { printf '\n\033[1m%s\033[0m\n' "$1"; }

heading '1. the envelope is the API'
# --json is not required when stdout is a pipe: rune detects the non-TTY and
# emits the structured form automatically. It is passed here for clarity.
"$RUNE" run --json -- git log --oneline -1 | jq '{exit_code: .data.exit_code, out: .data.clean_output}'

heading '2. --  is what protects the wrapped command'
# Without the separator rune would eat --json itself and git would never see it.
"$RUNE" run --json -- git log --pretty=format:%H -1 | jq -r '.data.clean_output' | cut -c1-12

heading '3. exit codes compose with the shell'
# The Result is a success even when the wrapped command fails; the *process*
# exit status mirrors the child, so `&&`/`||`/`set -e` still work.
if "$RUNE" run --json -- false >/dev/null; then
  echo "  unexpected: rune reported success"
else
  echo "  rune exited non-zero for 'false', so shell control flow still works"
fi

heading '4. bound output you did not write'
"$RUNE" run --json --tail=2 -- seq 1 500 \
  | jq '{truncated: .data.truncated, omitted: .data.omitted_lines, kept: .data.clean_output}'

heading '5. discover the surface without scraping help text'
"$RUNE" session --help --json | jq -r '.data.flags[] | "  \(.flag)"' | head -5

heading '6. a whole session conversation, in shell'
name=$("$RUNE" session start --json -- bash --norc -i | jq -r '.data.name')
echo "  started session: $name"
answer=$("$RUNE" session send --name "$name" --settle-ms 400 --timeout-ms 20000 --json -- 'X=41; echo $((X+1))' \
  | jq -r '.data.clean_output' | grep -E '^[0-9]+$' | tail -1)
echo "  answer: $answer"
"$RUNE" session list --json | jq -r '.data.sessions[] | "  \(.name)  \(.state)  idle=\(.idle_ms)ms"'
"$RUNE" session stop --name "$name" --json | jq -r '"  stopped: " + .data.state'

heading '7. failures are structured too'
"$RUNE" session send --name no-such-session --json -- hello | jq -r '"  status=" + .status + " error=" + .error'
