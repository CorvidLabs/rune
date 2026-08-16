# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'spec_helper'
require 'tmpdir'

RSpec.describe 'release version check' do
  let(:check_script) { File.expand_path('../scripts/check_release_version.rb', __dir__) }
  let(:set_script) { File.expand_path('../scripts/set_release_version.rb', __dir__) }
  let(:publish_workflow) { File.read(File.expand_path('../.github/workflows/publish-package.yml', __dir__)) }
  let(:release_docs) { File.read(File.expand_path('../docs/releasing.md', __dir__)) }
  let(:sdd_policy) { JSON.parse(File.read(File.expand_path('../.specsync/sdd.json', __dir__))) }

  it 'accepts matching repository versions and a v-prefixed release tag' do
    output, status = Open3.capture2e(RbConfig.ruby, check_script, "v#{Rune::VERSION}")

    expect(status).to be_success
    expect(output).to include("Release versions agree at #{Rune::VERSION}")
  end

  it 'rejects a tag that does not match the packaged version' do
    output, status = Open3.capture2e(RbConfig.ruby, check_script, 'v99.0.0')

    expect(status).not_to be_success
    expect(output).to include("lib/rune/version.rb is #{Rune::VERSION}, expected 99.0.0")
  end

  it 'rejects invalid input before the version setter changes files' do
    output, status = Open3.capture2e(RbConfig.ruby, set_script, 'not-a-version')

    expect(status).not_to be_success
    expect(output).to include('Usage: fledge run set-version -- MAJOR.MINOR.PATCH')
  end

  it 'repairs either stale version source when the other source already matches' do
    [
      ['0.2.1', '0.2.0'],
      ['0.2.0', '0.2.1']
    ].each do |rune_version, plugin_version|
      Dir.mktmpdir do |root|
        fixture_script = write_setter_fixture(
          root,
          rune_version: rune_version,
          plugin_version: plugin_version
        )
        output, status = Open3.capture2e(RbConfig.ruby, fixture_script, '0.2.1')

        expect(status).to be_success
        expect(output).to include('Updated release versions to 0.2.1')
        expect(File.read(File.join(root, 'lib/rune/version.rb'))).to include("VERSION = '0.2.1'")
        expect(File.read(File.join(root, 'plugin.toml'))).to include('version = "0.2.1"')
      end
    end
  end

  it 'validates every version pattern before writing either source' do
    Dir.mktmpdir do |root|
      fixture_script = write_setter_fixture(root, rune_version: '0.2.0', plugin_version: nil)
      _output, status = Open3.capture2e(RbConfig.ruby, fixture_script, '0.2.1')

      expect(status).not_to be_success
      expect(File.read(File.join(root, 'lib/rune/version.rb'))).to include("VERSION = '0.2.0'")
    end
  end

  it 'rejects a version from a TOML table after a malformed plugin table' do
    Dir.mktmpdir do |root|
      fixture_script = write_setter_fixture(
        root,
        rune_version: '0.2.0',
        plugin_version: nil,
        later_version: '0.2.0'
      )
      check_fixture = File.join(root, 'scripts/check_release_version.rb')
      check_output, check_status = Open3.capture2e(RbConfig.ruby, check_fixture, 'v0.2.0')
      _set_output, set_status = Open3.capture2e(RbConfig.ruby, fixture_script, '0.2.1')

      expect(check_status).not_to be_success
      expect(check_output).to include('[plugin] table must contain exactly one version')
      expect(set_status).not_to be_success
      expect(File.read(File.join(root, 'lib/rune/version.rb'))).to include("VERSION = '0.2.0'")
      expect(File.read(File.join(root, 'plugin.toml'))).to include('version = "0.2.0"')
    end
  end

  it 'requires both publish jobs to validate an exact tag on origin main' do
    release_tag_format_check = '[[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]'
    exact_tag_check = 'git show-ref --verify --quiet "refs/tags/${RELEASE_TAG}"'
    checked_out_tag_check = 'git rev-parse "refs/tags/${RELEASE_TAG}^{commit}"'
    mainline_check = 'git merge-base --is-ancestor "$tag_commit" origin/main'

    expect(publish_workflow.scan(release_tag_format_check).length).to eq(2)
    expect(publish_workflow.scan(exact_tag_check).length).to eq(2)
    expect(publish_workflow.scan(checked_out_tag_check).length).to eq(2)
    expect(publish_workflow.scan(mainline_check).length).to eq(2)
  end

  it 'restricts both provenance ranges to exact semantic release tags' do
    strict_tag_filter = "grep -E '^v[0-9]+\\.[0-9]+\\.[0-9]+$'"
    restricted_describe = 'git describe --tags "${release_tag_args[@]}" --abbrev=0 "${RELEASE_TAG}^"'

    expect(publish_workflow.scan(strict_tag_filter).length).to eq(2)
    expect(publish_workflow.scan(restricted_describe).length).to eq(2)
    expect(publish_workflow).not_to include('git describe --tags --abbrev=0')
  end

  it 'keeps SpecSync policy files meaningful while ignoring generated state' do
    expect(sdd_policy.fetch('meaningful_paths')).to include('.specsync/sdd.json', '.specsync/config.toml')
    expect(sdd_policy.fetch('ignored_paths')).not_to include('.specsync/')
    expect(sdd_policy.fetch('ignored_paths')).to include('.specsync/changes/', '.specsync/hashes.json')
  end

  # CI no longer gates on Augur/Attest, so the release guide records provenance
  # by hand and the release lane verifies it. The ordering is the whole point:
  # a squash merge produces a commit that has never been attested, so signing
  # has to come before the lane rather than after it. The guide used to say the
  # opposite, which would fail `provenance-check` on the first step.
  it 'documents recording merge-commit attestation before running the lane that verifies it' do
    post_merge_steps = release_docs.split('## Tag and publish after merge').last
    sign_position = post_merge_steps.index('fledge attest sign')
    push_position = post_merge_steps.index('git push origin refs/notes/attest')
    lane_position = post_merge_steps.index('fledge lanes run release')

    expect(sign_position).to be < push_position
    expect(push_position).to be < lane_position
  end

  def write_setter_fixture(root, rune_version:, plugin_version:, later_version: nil)
    scripts = File.join(root, 'scripts')
    version_file = File.join(root, 'lib/rune/version.rb')
    plugin_file = File.join(root, 'plugin.toml')
    FileUtils.mkdir_p(scripts)
    FileUtils.mkdir_p(File.dirname(version_file))
    FileUtils.cp(set_script, scripts)
    FileUtils.cp(check_script, scripts)
    File.write(version_file, "module Rune\n  VERSION = '#{rune_version}'\nend\n")
    plugin_content = plugin_version ? "[plugin]\nversion = \"#{plugin_version}\"\n" : "[plugin]\nname = \"rune\"\n"
    plugin_content += "\n[command.rune]\nversion = \"#{later_version}\"\n" if later_version
    File.write(plugin_file, plugin_content)
    File.join(scripts, 'set_release_version.rb')
  end
end
