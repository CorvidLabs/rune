# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::Parsers::PromptDetector do
  describe '.detect?' do
    it 'returns false for nil, empty, and whitespace-only lines' do
      expect(described_class.detect?(nil)).to be false
      expect(described_class.detect?('')).to be false
      expect(described_class.detect?('   ')).to be false
    end

    it 'detects [y/n]-style confirmations' do
      expect(described_class.detect?('Overwrite file? [y/N] ')).to be true
      expect(described_class.detect?('Delete? [Y/n]')).to be true
    end

    it 'detects (y/n)-style confirmations, case-insensitively' do
      expect(described_class.detect?('Continue? (y/n) ')).to be true
      expect(described_class.detect?('proceed (Y/N)?')).to be true
    end

    it 'detects labeled prompts (Password/Passphrase/Select/Choice/Confirm)' do
      expect(described_class.detect?('Password: ')).to be true
      expect(described_class.detect?('Passphrase: ')).to be true
      expect(described_class.detect?('Select: ')).to be true
      expect(described_class.detect?('Choice: ')).to be true
      expect(described_class.detect?('Confirm: ')).to be true
    end

    it 'detects anchored interactive-wizard markers with a supported action' do
      expect(described_class.detect?('? Select target environment: ')).to be true
      expect(described_class.detect?('? Pick a number 1-5')).to be true
    end

    it 'detects modern arrow-style prompt indicators at the start of a line' do
      expect(described_class.detect?('➜  rune git:(main) ')).to be true
      expect(described_class.detect?('❯ ')).to be true
      expect(described_class.detect?('› next step')).to be true
    end

    it 'detects a full shell prompt (user@host:path$) ending in a shell terminator' do
      expect(described_class.detect?('user@hostname:~$ ')).to be true
      expect(described_class.detect?('bash-5.2# ')).to be true
      expect(described_class.detect?('zsh-5.9%')).to be true
      expect(described_class.detect?('root@box:/var/log# ')).to be true
    end

    it 'detects common macOS zsh and virtualenv-prefixed shell prompts' do
      expect(described_class.detect?('leif@MacBook-Pro rune % ')).to be true
      expect(described_class.detect?('(venv) user@host:~$ ')).to be true
      expect(described_class.detect?('(my-env) alice@dev /tmp $')).to be true
    end

    it 'strips ANSI escape codes before matching' do
      expect(described_class.detect?("\e[1muser@host\e[0m:~$ ")).to be true
      expect(described_class.detect?("\e[32mPassword:\e[0m ")).to be true
    end

    it 'ignores blockquote-style lines starting with >' do
      expect(described_class.detect?('  > This is a blockquote')).to be false
      expect(described_class.detect?('> some quoted output <tag>')).to be false
    end

    it 'ignores code containing if/comparison operators' do
      expect(described_class.detect?('if (x > 5) { return true; }')).to be false
      expect(described_class.detect?('if x > 5:')).to be false
    end

    it 'ignores shell variable assignments referencing other variables' do
      expect(described_class.detect?('export PATH=$PATH:/usr/bin')).to be false
    end

    it 'ignores markdown/code comment headers' do
      expect(described_class.detect?('# Section 1 Header')).to be false
      expect(described_class.detect?('# Config file')).to be false
    end

    it 'ignores digit-percent progress output (no longer matches any positive shell pattern)' do
      expect(described_class.detect?('Building... 45%')).to be false
      expect(described_class.detect?('Downloading 100%')).to be false
      expect(described_class.detect?('Progress: 3.5%')).to be false
    end

    it 'ignores a line ending in a <placeholder> example, not a real shell prompt terminator ' \
       '(found via real dogfooding: `rune run --json -- fledge plugins search rune` misreported ' \
       'prompt_detected: true on a command that had already exited cleanly)' do
      expect(described_class.detect?('  Install with: fledge plugins install <owner/repo>')).to be false
      expect(described_class.detect?('Usage: mycli <command>')).to be false
    end

    it 'ignores ordinary prose and log lines' do
      expect(described_class.detect?('just plain output text')).to be false
      expect(described_class.detect?('npm WARN deprecated foo@1.0')).to be false
      expect(described_class.detect?('Server started on port 3000')).to be false
    end

    it 'ignores ordinary output ending in shell punctuation or containing a prose question' do
      expect(described_class.detect?('##')).to be false
      expect(described_class.detect?('TODO: fix #')).to be false
      expect(described_class.detect?('comparison result >')).to be false
      expect(described_class.detect?('price is $')).to be false
      expect(described_class.detect?('coverage pending %')).to be false
      expect(described_class.detect?('Is it ok? Yes')).to be false
    end
  end
end
