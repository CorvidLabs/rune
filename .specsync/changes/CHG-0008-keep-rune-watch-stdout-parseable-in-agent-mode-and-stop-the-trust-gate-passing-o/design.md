---
change: CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o
artifact: design
---

# Design

## Watch display routing

`WatchCommand#call` starts honoring the `options` hash it already receives and picks the display
stream before constructing the watcher:

```ruby
def call(args, options)
  ...
  PTYWatcher.new(clean_args, log: log, output: display_stream(options)).watch
end

# Agent mode is the renderer's rule (Renderer#agent_mode?) applied one layer earlier: the live
# passthrough is a side effect of #call, so it has to be routed before the renderer ever sees the
# Result. stdout is reserved for the structured envelope whenever anything machine-readable is
# being produced; stderr keeps the live view for whoever is actually driving the session.
def display_stream(options)
  agent_mode?(options) ? $stderr : $stdout
end

def agent_mode?(options)
  options[:json] || options[:ndjson] || !$stdout.tty?
end
```

`PTYWatcher` is untouched. Its `output:` parameter already existed and was already injectable; the
bug was purely that the one production caller never used it. Keeping the fix in `WatchCommand`
means the watcher's contract, its specs, and its 363-line spec file stay valid.

`agent_mode?` deliberately reads `$stdout` rather than an injected io. The live passthrough writes
to the real process stdout by nature — there is no meaningful "watch a TUI into a StringIO" — so
consulting the real stream is both correct and testable by stubbing `$stdout.tty?`, which the
existing suite already does for `$stdin`.

## End-to-end stdout purity

A new example group in `spec/rune/e2e_spec.rb` runs the real `bin/rune` and parses complete stdout.
For `watch`, stdin must be a TTY, so the spec allocates a pty with `PTY.spawn` and runs rune inside
it via `sh -c` with stdout redirected to a file — the pty satisfies `$stdin.tty?` while the
redirect makes stdout non-TTY, which is exactly the agent-mode path under test. This works on Linux
and macOS runners; the group is skipped when `PTYRunner.pty_available?` is false.

The assertion is `JSON.parse(File.read(out))` over the whole file. A substring match would have
passed against the buggy output and is explicitly not used.

## Trust range resolution

A `Resolve trust range` step runs before the Augur and Attest steps and writes three outputs:

| Event | `range` | `forward_from` |
|---|---|---|
| `pull_request` | `origin/main..HEAD` | empty |
| `push` | `HEAD~1..HEAD` | reviewed head SHA of the pull request whose `merge_commit_sha` is this commit, if any |

A following `Reject a vacuous trust range` step fails the job when `git rev-list --count` over the
resolved range is zero. This is the load-bearing part: it converts a silent false green into a loud
failure for any future event type or checkout shape that produces an empty range, including ones
not anticipated here.

The job gains `pull-requests: read` so the commit-to-pull-request lookup is permitted. The lookup
is best-effort — if no pull request is found, `forward_from` stays empty and Attest verifies the
landed commit on its own merits, which is the correct strict behavior for a direct push.

## Local parity

`scripts/trust_range.sh` implements the same selection for developers and is wired into the
existing `trust` task in `fledge.toml`. It is a shell script rather than inline TOML because the
conditional is long enough that quoting it inside a TOML string obscures it, and because CI and
local logic staying visibly identical is the point.

## Rejected alternatives

- **Passing the renderer or its io into `Command#call`.** A larger signature change across every
  command to solve a problem only `watch` has.
- **Making `PTYWatcher` default `output:` to stderr.** Moves the decision away from where output
  mode is known and silently changes the library API for existing direct callers.
- **Failing CI whenever the landed commit lacks its own attestation, with no forwarding.** Correct
  in principle, but it discards a real review that did happen and would leave `main` permanently red
  until every merge is manually re-attested.

## A note on the spec's Public API table

`display_stream` and `agent_mode?` are deliberately *not* added to `specs/watch/watch.spec.md`'s
Public API table. spec-sync 5.2.0 does not detect them as exports of
`lib/rune/commands/watch_command.rb`, and documenting a name it cannot see is a hard error:

```
error: effective contract `watch`: Spec documents 'display_stream' but no matching export found in source
```

This is not specific to the new methods. The pre-existing private `format_duration` in the same
file is undetected and undocumented too, which is why the module has always reported a clean
`21/21 exports documented`. Detection is positional rather than name-based: an identical probe
method is undetected when placed immediately after `private`, and detected when placed a few
methods further down, in the same file, with the same signature.

Removing `format_duration`, removing its comment block, and removing the new comment blocks each
failed to change the outcome, so the cause is inside spec-sync's Ruby extractor rather than
anything about how this file is written. The practical consequence is worth stating plainly: the
repository's "100% export coverage" gate is 100% of what spec-sync detects, and it silently omits
some private methods. That is reported upstream separately; it does not block this change, and the
new methods are covered by unit tests regardless.
