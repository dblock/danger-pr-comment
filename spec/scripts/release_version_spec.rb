# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

RSpec.describe 'Release version script' do
  let(:script) { File.expand_path('../../scripts/release_version.rb', __dir__) }

  def with_version(content)
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p("#{directory}/lib/danger-pr-comment")
      path = "#{directory}/lib/danger-pr-comment/version.rb"
      File.write(path, content)
      yield directory, path
    end
  end

  it 'reads and bumps only the assignment' do
    content = "# VERSION = '9.9.9'\nmodule DangerPrComment\n  VERSION = '0.1.9'\nend\n"
    with_version(content) do |directory, path|
      output, error, status = Open3.capture3(RbConfig.ruby, script, 'read', chdir: directory)
      expect(status.success?).to be(true), error
      expect(output).to eq("0.1.9\n")
      output, error, status = Open3.capture3(RbConfig.ruby, script, 'bump', chdir: directory)
      expect(status.success?).to be(true), error
      expect(output).to eq("0.1.10\n")
      expect(File.read(path)).to eq(content.sub("  VERSION = '0.1.9'", "  VERSION = '0.1.10'"))
    end
  end

  it 'rejects invalid versions without modifying the file' do
    %w[0.1 0.1.0.1 0.1.beta 0.1.0.pre 01.2.3].each do |version|
      content = "  VERSION = '#{version}'\n"
      with_version(content) do |directory, path|
        _output, error, status = Open3.capture3(RbConfig.ruby, script, 'bump', chdir: directory)
        expect(status.success?).to be(false)
        expect(error).to include('Expected MAJOR.MINOR.PATCH')
        expect(File.read(path)).to eq(content)
      end
    end
  end

  it 'rejects missing or ambiguous assignments' do
    ["# VERSION = '0.1.0'\n", "VERSION = '0.1.0'\nVERSION = '0.2.0'\n"].each do |content|
      with_version(content) do |directory, path|
        _output, error, status = Open3.capture3(RbConfig.ruby, script, 'bump', chdir: directory)
        expect(status.success?).to be(false)
        expect(error).to include('Expected exactly one VERSION assignment')
        expect(File.read(path)).to eq(content)
      end
    end
  end

  it 'rejects invalid commands without modifying the file' do
    with_version("VERSION = '0.1.0'\n") do |directory, path|
      [[], ['unknown'], %w[bump extra]].each do |arguments|
        _output, error, status = Open3.capture3(RbConfig.ruby, script, *arguments, chdir: directory)
        expect(status.success?).to be(false)
        expect(error).to include('Usage:')
        expect(File.read(path)).to eq("VERSION = '0.1.0'\n")
      end
    end
  end
end
