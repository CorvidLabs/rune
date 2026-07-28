# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'spec_helper'

RSpec.describe 'release version check' do
  let(:check_script) { File.expand_path('../scripts/check_release_version.rb', __dir__) }

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
    set_script = File.expand_path('../scripts/set_release_version.rb', __dir__)
    output, status = Open3.capture2e(RbConfig.ruby, set_script, 'not-a-version')

    expect(status).not_to be_success
    expect(output).to include('Usage: fledge run set-version -- MAJOR.MINOR.PATCH')
  end
end
