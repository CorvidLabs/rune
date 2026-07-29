# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

RSpec.describe 'scripts/trust_range.sh' do
  let(:script) { File.expand_path('../scripts/trust_range.sh', __dir__) }

  def git(repo, *arguments)
    output, status = Open3.capture2e('git', '-C', repo, *arguments)
    raise "git #{arguments.join(' ')} failed: #{output}" unless status.success?

    output.strip
  end

  def commit(repo, message)
    path = File.join(repo, 'fixture.txt')
    File.write(path, "#{message}\n", mode: 'a')
    git(repo, 'add', 'fixture.txt')
    git(repo, 'commit', '--quiet', '-m', message)
    git(repo, 'rev-parse', 'HEAD')
  end

  def with_repository
    Dir.mktmpdir do |repo|
      git(repo, 'init', '--quiet')
      git(repo, 'config', 'user.name', 'Rune Tests')
      git(repo, 'config', 'user.email', 'rune-tests@example.invalid')
      yield repo
    end
  end

  def resolve_range(repo, environment = {})
    Open3.capture2e(environment, script, chdir: repo)
  end

  it 'covers every commit introduced by a multi-commit push' do
    with_repository do |repo|
      before_sha = commit(repo, 'base')
      3.times { |index| commit(repo, "pushed-#{index + 1}") }
      after_sha = git(repo, 'rev-parse', 'HEAD')

      output, status = resolve_range(
        repo,
        'TRUST_PUSH_BEFORE_SHA' => before_sha,
        'TRUST_PUSH_AFTER_SHA' => after_sha
      )

      expect(status).to be_success
      expect(output.strip).to eq("#{before_sha}..#{after_sha}")
      expect(git(repo, 'rev-list', '--count', output.strip)).to eq('3')
    end
  end

  it 'rejects a partially specified push range instead of falling back' do
    with_repository do |repo|
      before_sha = commit(repo, 'base')

      output, status = resolve_range(repo, 'TRUST_PUSH_BEFORE_SHA' => before_sha)

      expect(status).not_to be_success
      expect(output).to include('must be provided together')
    end
  end

  it 'rejects the all-zero before SHA used by an initial branch push' do
    with_repository do |repo|
      after_sha = commit(repo, 'initial')

      output, status = resolve_range(
        repo,
        'TRUST_PUSH_BEFORE_SHA' => '0' * 40,
        'TRUST_PUSH_AFTER_SHA' => after_sha
      )

      expect(status).not_to be_success
      expect(output).to include('before SHA is all zeroes')
    end
  end

  it 'rejects an empty push range' do
    with_repository do |repo|
      sha = commit(repo, 'base')

      output, status = resolve_range(
        repo,
        'TRUST_PUSH_BEFORE_SHA' => sha,
        'TRUST_PUSH_AFTER_SHA' => sha
      )

      expect(status).not_to be_success
      expect(output).to include('contains 0 commits')
    end
  end
end
