# frozen_string_literal: true

require 'spec_helper'
require_relative '../../harnesses/session_fault_recovery'

# Fault and recovery cases the existing session examples do not pin down
# together. The harness owns the fixtures; these examples only assert the
# problem list. A non-empty list is the failure, and the observation is the
# message, so a broken predicate is visible without a second run.
RSpec.describe SessionFaultRecovery do
  it 'agrees on a clean child exit across read, list, and meta' do
    observation = described_class.observe_exit(0)
    expect(described_class.exit_problems(observation)).to eq([]), observation.inspect
  end

  it 'agrees on a nonzero child exit across read, list, and meta' do
    observation = described_class.observe_exit(3)
    expect(described_class.exit_problems(observation)).to eq([]), observation.inspect
  end

  it 'reads running, then after release reads the exact exit' do
    observation = described_class.observe_read_exit
    expect(described_class.read_problems(observation)).to eq([]), observation.inspect
  end

  it 'reports child_exited for a send that is in flight when the child exits' do
    observation = described_class.observe_send_exit
    expect(described_class.send_problems(observation)).to eq([]), observation.inspect
  end

  it 'accepts a late marker only after the nonce was already visible' do
    observation = described_class.observe_late
    expect(described_class.late_problems(observation)).to eq([]), observation.inspect
  end

  it 'restarts a name after the supervisor disappears without signalling the orphan' do
    observation = described_class.observe_reconnect
    expect(described_class.reconnect_problems(observation)).to eq([]), observation.inspect
  end

  it 'does not signal an unrelated process-group leader on stop' do
    observation = described_class.observe_bystander
    expect(described_class.bystander_problems(observation)).to eq([]), observation.inspect
  end

  it 'fails closed when a copied rune implementation breaks the assertion' do
    described_class.broken_controls.each do |control|
      expect(control[:setup_ok]).to be(true), control.inspect
      expect(control[:problems]).to include(control[:tag]), control.inspect
    end
  end

  it 'does not call Process.kill when the recorded identity is missing' do
    result = described_class.probe_missing_recorded_identity
    expect(result[:kill_calls]).to eq([]), result.inspect
    expect(result[:refused]).to be(true), result.inspect
    expect(result[:survived]).to be(true), result.inspect
  end

  it 'does not call Process.kill when the current identity is missing' do
    result = described_class.probe_missing_current_identity
    expect(result[:kill_calls]).to eq([]), result.inspect
    expect(result[:refused]).to be(true), result.inspect
    expect(result[:survived]).to be(true), result.inspect
  end

  it 'does not call Process.kill when the start time does not match' do
    result = described_class.probe_mismatched_identity
    expect(result[:kill_calls]).to eq([]), result.inspect
    expect(result[:refused]).to be(true), result.inspect
    expect(result[:survived]).to be(true), result.inspect
  end

  it 'does not signal a fixture pid again after this process reaped it' do
    result = described_class.probe_confirmed_dead
    expect(result[:kill_calls]).to eq([]), result.inspect
    expect(result[:noop]).to be(true), result.inspect
  end

  it 'resolves a missing default home from a synthetic directory without creating it' do
    Dir.mktmpdir('rune-synthetic-home') do |home|
      resolved = SessionFaultLoadPath.default_home_for(home)
      expect(resolved).to eq(File.expand_path('.rune', home))
      expect(File.exist?(resolved)).to be(false)
      expect(SessionFaultLoadPath.refuses_default?(resolved, home)).to be(true)
      expect(File.exist?(resolved)).to be(false)
      fixture = File.join(home, 'fixture')
      expect(SessionFaultLoadPath.refuses_default?(fixture, home)).to be(false)
    end
  end

  it 'fails and preserves the fixture when an injected pid stays present' do
    result = described_class.probe_unresolved_still_present
    expect(result[:raised]).to include('cleanup failed closed'), result.inspect
    expect(result[:still_present].map { |row| row[:pid] }).to eq([result[:pid]])
    expect(result[:reaped]).to eq([])
    expect(result[:absent]).to eq([])
    expect(result[:kill_calls]).to eq([result[:pid]])
    expect(result[:real_kills]).to eq([])
    expect(result[:exists_calls].size).to eq(described_class.disappear_checks)
    expect(result[:wait_calls]).to eq([result[:pid]])
    expect(result[:home_restored]).to be(true), result.inspect
    expect(result[:inside]).to be(false)
    expect(result[:tracked_cleared]).to be(true)
    preserved = result[:preserved]
    expect(preserved).not_to be_nil, result.inspect
    expect(File.exist?(File.join(preserved, 'cleanup-refusal.json'))).to be(true) if preserved
  end

  it 'preserves a refused pid and does not signal it' do
    result = described_class.probe_cleanup_refusal
    expect(result[:raised]).to include('cleanup failed closed'), result.inspect
    expect(result[:kill_calls]).to eq([])
    expect(result[:real_kills]).to eq([])
    expect(result[:wait_calls]).to eq([])
    expect(result[:refused_alive].map { |row| row[:pid] }).to eq([result[:pid]])
    expect(result[:still_present]).to eq([])
    expect(result[:reaped]).to eq([])
    expect(result[:home_restored]).to be(true), result.inspect
    expect(result[:inside]).to be(false)
    expect(result[:tracked_cleared]).to be(true)
    preserved = result[:preserved]
    expect(preserved).not_to be_nil, result.inspect
    expect(File.exist?(File.join(preserved, 'cleanup-refusal.json'))).to be(true) if preserved
  end

  it 'restores the environment when presence checking fails and does not signal' do
    result = described_class.probe_cleanup_error
    expect(result[:raised]).to include('injected existence failure'), result.inspect
    expect(result[:raised]).to include('cleanup failed closed'), result.inspect
    expect(result[:kill_calls]).to eq([])
    expect(result[:real_kills]).to eq([])
    expect(result[:wait_calls]).to eq([])
    expect(result[:home_restored]).to be(true), result.inspect
    expect(result[:inside]).to be(false)
    expect(result[:tracked_cleared]).to be(true)
    preserved = result[:preserved]
    expect(preserved).not_to be_nil, result.inspect
    expect(File.exist?(File.join(preserved, 'cleanup-refusal.json'))).to be(true) if preserved
  end
end
