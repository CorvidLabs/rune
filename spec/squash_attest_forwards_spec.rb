# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

RSpec.describe 'scripts/squash_attest_forwards.sh' do
  let(:script) { File.expand_path('../scripts/squash_attest_forwards.sh', __dir__) }

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

  it 'requires before and after SHAs' do
    output, status = Open3.capture2e(script)

    expect(status).not_to be_success
    expect(output).to include('usage:')
  end

  it 'rejects unavailable commit SHAs' do
    Dir.mktmpdir do |repo|
      git(repo, 'init', '--quiet')
      git(repo, 'config', 'user.name', 'Rune Tests')
      git(repo, 'config', 'user.email', 'rune-tests@example.invalid')
      before = commit(repo, 'base')
      missing = 'a' * 40

      output, status = Open3.capture2e(
        { 'GITHUB_REPOSITORY' => 'CorvidLabs/rune' },
        script, before, missing,
        chdir: repo
      )

      expect(status).not_to be_success
      expect(output).to include('after commit')
      expect(output).to include('unavailable')
    end
  end

  it 'emits nothing for a range when gh reports no matching squash PR' do
    Dir.mktmpdir do |repo|
      git(repo, 'init', '--quiet')
      git(repo, 'config', 'user.name', 'Rune Tests')
      git(repo, 'config', 'user.email', 'rune-tests@example.invalid')
      before = commit(repo, 'base')
      after = commit(repo, 'landed')

      # Stub `gh` so the script stays offline and unit-testable.
      bin = File.join(repo, 'bin')
      Dir.mkdir(bin)
      File.write(File.join(bin, 'gh'), "#!/usr/bin/env bash\nexit 0\n")
      File.chmod(0o755, File.join(bin, 'gh'))

      output, status = Open3.capture2e(
        { 'GITHUB_REPOSITORY' => 'CorvidLabs/rune', 'PATH' => "#{bin}:#{ENV.fetch('PATH')}" },
        script, before, after,
        chdir: repo
      )

      expect(status).to be_success
      expect(output).to eq('')
    end
  end

  it 'emits a TSV row for each landed commit whose merge_commit_sha matches a PR' do
    Dir.mktmpdir do |repo|
      git(repo, 'init', '--quiet')
      git(repo, 'config', 'user.name', 'Rune Tests')
      git(repo, 'config', 'user.email', 'rune-tests@example.invalid')
      before = commit(repo, 'base')
      first = commit(repo, 'first')
      second = commit(repo, 'second')

      bin = File.join(repo, 'bin')
      Dir.mkdir(bin)
      # Echo a matching PR for each requested commit SHA, shaped like the
      # GitHub "list PRs for a commit" payload after our jq filter.
      File.write(File.join(bin, 'gh'), <<~'BASH')
        #!/usr/bin/env bash
        # argv looks like: api repos/org/repo/commits/<sha>/pulls --jq ...
        path=""
        for argument in "$@"; do
          case "${argument}" in
            repos/*/commits/*/pulls) path="${argument}" ;;
          esac
        done
        sha="${path##*/commits/}"
        sha="${sha%/pulls}"
        case "${sha}" in
          FIRST)
            printf '%s\n' $'abc111\tFIRST\t10'
            ;;
          SECOND)
            printf '%s\n' $'def222\tSECOND\t11'
            ;;
        esac
        exit 0
      BASH
      File.chmod(0o755, File.join(bin, 'gh'))
      # Replace real SHAs in the stub by rewriting the script to match.
      File.write(File.join(bin, 'gh'), <<~BASH)
        #!/usr/bin/env bash
        path=""
        for argument in "$@"; do
          case "${argument}" in
            repos/*/commits/*/pulls) path="${argument}" ;;
          esac
        done
        sha="${path##*/commits/}"
        sha="${sha%/pulls}"
        case "${sha}" in
          #{first})
            printf '%s\\n' $'abc111\\t#{first}\\t10'
            ;;
          #{second})
            printf '%s\\n' $'def222\\t#{second}\\t11'
            ;;
        esac
        exit 0
      BASH
      File.chmod(0o755, File.join(bin, 'gh'))

      output, status = Open3.capture2e(
        { 'GITHUB_REPOSITORY' => 'CorvidLabs/rune', 'PATH' => "#{bin}:#{ENV.fetch('PATH')}" },
        script, before, second,
        chdir: repo
      )

      expect(status).to be_success
      expect(output.lines.map(&:chomp)).to eq(
        [
          "abc111\t#{first}\t10",
          "def222\t#{second}\t11"
        ]
      )
    end
  end
end
