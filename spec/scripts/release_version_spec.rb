# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'date'

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

  def with_release_files
    with_version("module DangerPrComment\n  VERSION = '1.2.3'\nend\n") do |directory, path|
      %w[README.md scripts/install-workflows.sh spec/scripts/install_workflows_spec.rb].each do |file|
        FileUtils.mkdir_p(File.dirname("#{directory}/#{file}"))
        FileUtils.cp(File.expand_path("../../#{file}", __dir__), "#{directory}/#{file}")
      end
      File.write("#{directory}/CHANGELOG.md", "# Changelog\n\n## [Unreleased]\n\n### Fixed\n\n- A fix.\n\n## [0.1.0] - 2024-01-01\n")
      yield directory, path
    end
  end

  def release_files(directory)
    Dir.glob("#{directory}/**/*").select { |file| File.file?(file) }.to_h { |file| [file, File.read(file)] }
  end

  it 'prepares the changelog, documentation, installer and its specs without bumping the version' do
    with_release_files do |directory, path|
      original_version = File.read(path)
      output, error, status = Open3.capture3(RbConfig.ruby, script, 'prepare', chdir: directory)
      expect(status.success?).to be(true), error
      expect(output).to eq("1.2.3\n")
      expect(File.read(path)).to eq(original_version)
      expect(File.read("#{directory}/CHANGELOG.md")).to include("## [Unreleased]\n\n## [1.2.3] - #{Time.now.utc.to_date.iso8601}\n\n### Fixed\n\n- A fix.\n\n## [0.1.0] - 2024-01-01\n")
      %w[README.md scripts/install-workflows.sh spec/scripts/install_workflows_spec.rb].each do |file|
        content = File.read("#{directory}/#{file}")
        %w[run comment].each do |workflow|
          expect(content).to include("danger-#{workflow}.yml@v1.2.3")
        end
      end
      _output, error, status = Open3.capture3('bash', 'scripts/install-workflows.sh', '--root', "#{directory}/installed", chdir: directory)
      expect(status.success?).to be(true), error
      expect(File.read("#{directory}/installed/.github/workflows/danger.yml")).to include('danger-run.yml@v1.2.3')
      expect(File.read("#{directory}/installed/.github/workflows/danger-comment.yml")).to include('danger-comment.yml@v1.2.3')
    end
  end

  it 'can retry preparation without duplicating the release or changing its date' do
    with_release_files do |directory|
      changelog = "#{directory}/CHANGELOG.md"
      File.write(changelog, "# Changelog\n\n## [Unreleased]\n\n## [1.2.3] - 2025-01-01\n\n- A fix.\n")
      _output, error, status = Open3.capture3(RbConfig.ruby, script, 'prepare', chdir: directory)
      expect(status.success?).to be(true), error
      prepared = release_files(directory)
      _output, error, status = Open3.capture3(RbConfig.ruby, script, 'prepare', chdir: directory)
      expect(status.success?).to be(true), error
      expect(release_files(directory)).to eq(prepared)
      expect(File.read(changelog)).to include('## [1.2.3] - 2025-01-01')
    end
  end

  it 'rejects missing or duplicate workflow references before writing any files' do
    with_release_files do |directory|
      file = "#{directory}/spec/scripts/install_workflows_spec.rb"
      content = File.read(file)
      [content.gsub('danger-comment.yml', 'other.yml'), "#{content}\n#{content}"].each do |invalid|
        File.write(file, invalid)
        original = release_files(directory)
        _output, error, status = Open3.capture3(RbConfig.ruby, script, 'prepare', chdir: directory)
        expect(status.success?).to be(false)
        expect(error).to include('Expected exactly one')
        expect(release_files(directory)).to eq(original)
      end
    end
  end

  it 'rejects malformed changelogs and existing releases with new unreleased changes without writing files' do
    with_release_files do |directory|
      [
        "# Changelog\n",
        "## [Unreleased]\n\n## [Unreleased]\n",
        "## [Unreleased]\n\n- New change.\n\n## [1.2.3] - 2025-01-01\n"
      ].each do |invalid|
        File.write("#{directory}/CHANGELOG.md", invalid)
        original = release_files(directory)
        _output, error, status = Open3.capture3(RbConfig.ruby, script, 'prepare', chdir: directory)
        expect(status.success?).to be(false)
        expect(error).to match(/Unreleased changelog heading|unprepared changes/)
        expect(release_files(directory)).to eq(original)
      end
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
