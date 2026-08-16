#!/usr/bin/env ruby
# frozen_string_literal: true

# Fails the release lane when any commit since the previous release tag lacks an
# attestation satisfying `.attest.json`.
#
# The releases for v0.4.0, v0.5.0 and v0.6.0 all failed to publish at exactly
# this check, run inside `Publish Gem Package` — after the tag existed and the
# GitHub release was announced. Nothing downstream noticed, because the Homebrew
# formula builds from the tag tarball and the rubygems.org job is disabled, so
# the only casualty was a package nobody installs.
#
# The mechanism was never the problem. `docs/releasing.md` documents recording
# provenance by hand, and that step was simply skipped three times running. This
# moves the same check to where skipping it is impossible to miss: before the
# tag, not after it.
module ProvenanceCheck
  RELEASE_TAG_PATTERN = 'v[0-9]*.[0-9]*.[0-9]*'
  POLICY = '.attest.json'

  # An attest that is absent must fail, never pass. A provenance gate that goes
  # quiet when its tool is missing is worse than no gate: it reports success for
  # a check it did not run, which is the failure this whole script exists to
  # stop happening again.
  CANDIDATE_COMMANDS = [%w[fledge attest], %w[attest]].freeze

  module_function

  # Returns nil for both "ran and failed" and "could not be run at all". The
  # second case has to be caught rather than raised: an absent command raises
  # ENOENT out of Open3, and an unhandled exception here would abort the lane
  # with a backtrace instead of the message that names the remedy.
  def capture(*command)
    require 'open3'
    stdout, _stderr, status = Open3.capture3(*command)
    status.success? ? stdout.strip : nil
  rescue Errno::ENOENT, Errno::EACCES
    nil
  end

  def attest_command
    CANDIDATE_COMMANDS.find { |command| capture(*command, '--help') }
  end

  # The tag reachable from HEAD, excluding one that points at HEAD itself: after
  # a release is tagged the range would otherwise be empty and every commit
  # would pass by not being looked at.
  def previous_release_tag
    tag = capture('git', 'describe', '--tags', '--abbrev=0', '--match', RELEASE_TAG_PATTERN, 'HEAD')
    return nil unless tag

    at_head = capture('git', 'rev-parse', "#{tag}^{commit}") == capture('git', 'rev-parse', 'HEAD')
    at_head ? capture('git', 'describe', '--tags', '--abbrev=0', '--match', RELEASE_TAG_PATTERN, 'HEAD^') : tag
  end

  # Best effort: notes live on a ref that a fresh clone does not fetch, so a
  # check that skipped this would report missing provenance that is merely
  # absent locally. Not forced, so it cannot discard notes recorded and not yet
  # pushed.
  def fetch_notes
    capture('git', 'fetch', 'origin', 'refs/notes/attest:refs/notes/attest')
  end

  def failure(message, remedy)
    warn message
    warn ''
    warn remedy
    exit 1
  end
end

command = ProvenanceCheck.attest_command
unless command
  ProvenanceCheck.failure(
    'Cannot verify release provenance: neither `fledge attest` nor `attest` is installed.',
    "Install it with `brew install corvidlabs/tap/attest`.\n" \
    'Refusing to pass a check that was not run.'
  )
end

ProvenanceCheck.fetch_notes
previous = ProvenanceCheck.previous_release_tag
unless previous
  ProvenanceCheck.failure(
    'Cannot verify release provenance: no previous release tag is reachable from HEAD.',
    'Expected a tag matching vMAJOR.MINOR.PATCH. If this is the first release, record provenance ' \
    'for every commit and remove this step for the initial tag only.'
  )
end

range = "#{previous}..HEAD"
report = ProvenanceCheck.capture(*command, 'verify', '--range', range, '--policy', ProvenanceCheck::POLICY)

if report
  puts "Release provenance verified across #{range}"
else
  # Re-run so the caller sees which commits violate which rule, rather than a
  # bare exit code they then have to reproduce by hand.
  system(*command, 'verify', '--range', range, '--policy', ProvenanceCheck::POLICY)
  ProvenanceCheck.failure(
    "Release provenance is incomplete across #{range}.",
    "Record it, as docs/releasing.md describes, then push the notes:\n\n  " \
    "#{command.join(' ')} sign --commit HEAD --reviewer human:YOU \\\n    " \
    "--confidence 1.0 --verdict proceed --tests-passed --human-approved \\\n    " \
    "--note \"Release commit verified on main\"\n  " \
    "git push origin refs/notes/attest\n\n" \
    'Every commit in the range needs a record, not only HEAD.'
  )
end
