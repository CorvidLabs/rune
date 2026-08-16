# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'spec_helper'
require 'tmpdir'

# The releases for v0.4.0, v0.5.0 and v0.6.0 all failed at a provenance check
# run inside `Publish Gem Package` — after the tag existed and the release was
# announced. Nothing downstream noticed, so the failure was invisible three
# times running. These tests pin the two properties that make the same check
# useful when it runs before the tag instead: it fails loudly, and it never
# passes without having actually looked.
RSpec.describe 'release provenance check' do
  let(:script) { File.expand_path('../scripts/check_provenance.rb', __dir__) }
  let(:fledge_config) { File.read(File.expand_path('../fledge.toml', __dir__)) }
  let(:release_docs) { File.read(File.expand_path('../docs/releasing.md', __dir__)) }

  # A gate that goes quiet when its tool is missing is worse than no gate: it
  # reports success for a check it did not run. This is the failure mode the
  # whole script exists to prevent, so it is the first thing tested.
  it 'fails instead of passing when no attest command is installed' do
    Dir.mktmpdir do |root|
      empty_bin = File.join(root, 'bin')
      FileUtils.mkdir_p(empty_bin)
      output, status = Open3.capture2e({ 'PATH' => empty_bin }, RbConfig.ruby, script)

      expect(status).not_to be_success
      expect(output).to include('neither `fledge attest` nor `attest` is installed')
      expect(output).to include('Refusing to pass a check that was not run')
    end
  end

  it 'names the remedy rather than only reporting the failure' do
    Dir.mktmpdir do |root|
      empty_bin = File.join(root, 'bin')
      FileUtils.mkdir_p(empty_bin)
      output, = Open3.capture2e({ 'PATH' => empty_bin }, RbConfig.ruby, script)

      expect(output).to include('brew install corvidlabs/tap/attest')
    end
  end

  it 'runs in the release lane, before the expensive steps' do
    steps = fledge_config[/^steps = \[(.+)\]$/m, 1].to_s
    release_lane = fledge_config.split('[lanes.release]').last.to_s
    lane_steps = release_lane[/steps = \[(.+?)\]/m, 1].to_s

    expect(lane_steps).to include('provenance-check')
    expect(lane_steps.index('provenance-check')).to be < lane_steps.index('test')
    expect(steps).not_to be_empty
  end

  it 'is wired to a task the lane can actually run' do
    expect(fledge_config).to include('provenance-check = "ruby scripts/check_provenance.rb"')
  end

  # The range must exclude a tag pointing at HEAD. Otherwise re-running the gate
  # on an already-tagged release inspects nothing and passes — which is exactly
  # how the old CI gates reported "PASS (0 commits checked)".
  it 'excludes a release tag that points at HEAD, so the range is never empty' do
    source = File.read(script)

    expect(source).to include("'HEAD^'")
    expect(source).to match(/at_head\s*\?/)
  end

  it 'documents the same recording step the failure message points at' do
    expect(release_docs).to include('fledge attest sign')
    expect(release_docs).to include('git push origin refs/notes/attest')
  end
end
