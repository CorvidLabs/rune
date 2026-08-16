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

  # The provenance gate is off (`.trust.toml` records why), so the range
  # resolution that fed it is gone with it. What must not go is the tag/version
  # validation, which is the part that actually stops a wrong release.
  it 'no longer gates publication on provenance' do
    expect(publish_workflow).not_to include('CorvidLabs/attest')
    expect(publish_workflow).not_to include('refs/notes/attest')
    expect(File.read(File.expand_path('../.trust.toml', __dir__))).to include('mode = "off"')
  end

  it 'keeps SpecSync policy files meaningful while ignoring generated state' do
    expect(sdd_policy.fetch('meaningful_paths')).to include('.specsync/sdd.json', '.specsync/config.toml')
    expect(sdd_policy.fetch('ignored_paths')).not_to include('.specsync/')
    expect(sdd_policy.fetch('ignored_paths')).to include('.specsync/changes/', '.specsync/hashes.json')
  end

  # The guide has twice drifted from what the tooling actually does — first
  # describing a CI gate that had been removed, then an ordering that the
  # release lane would have failed on. Pin the shape rather than the prose.
  it 'documents running the release lane before tagging, and no signing step' do
    post_merge_steps = release_docs.split('## Tag and publish after merge').last

    expect(post_merge_steps).not_to include('attest')
    expect(post_merge_steps.index('fledge lanes run release')).to be < post_merge_steps.index('fledge release')
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
