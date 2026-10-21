# frozen_string_literal: true

require 'English'
require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'Workflow installation script', type: :integration do
  subject(:script_path) { File.expand_path('../../scripts/install-workflows.sh', __dir__) }

  let(:tmpdir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def run_script?(*args)
    Dir.chdir(tmpdir) do
      system(script_path, *args, out: File::NULL, err: File::NULL)
    end
    $CHILD_STATUS.success?
  end

  def danger_yml_path
    File.join(tmpdir, '.github/workflows/danger.yml')
  end

  def danger_comment_yml_path
    File.join(tmpdir, '.github/workflows/danger-comment.yml')
  end

  describe 'basic installation' do
    it 'creates both workflow files' do
      run_script?('--root', tmpdir)

      expect(File.exist?(danger_yml_path)).to be true
      expect(File.exist?(danger_comment_yml_path)).to be true
    end

    it 'creates .github/workflows directory if it does not exist' do
      run_script?('--root', tmpdir)

      expect(Dir.exist?(File.join(tmpdir, '.github/workflows'))).to be true
    end

    it 'exits successfully when files are created' do
      expect(run_script?('--root', tmpdir)).to be true
    end
  end

  describe 'danger.yml content' do
    before do
      run_script?('--root', tmpdir)
    end

    it 'contains correct workflow name' do
      content = File.read(danger_yml_path)
      expect(content).to include('name: Danger')
    end

    it 'triggers on pull request events' do
      content = File.read(danger_yml_path)
      expect(content).to include('pull_request:')
      expect(content).to include('types: [opened, reopened, edited, synchronize]')
    end

    it 'uses the reusable workflow' do
      content = File.read(danger_yml_path)
      expect(content).to include('uses: numbata/danger-pr-comment/.github/workflows/danger-run.yml@v0.1.1')
    end

    it 'inherits secrets' do
      content = File.read(danger_yml_path)
      expect(content).to include('secrets: inherit')
    end
  end

  describe 'danger-comment.yml content' do
    before do
      run_script?('--root', tmpdir)
    end

    it 'contains correct workflow name' do
      content = File.read(danger_comment_yml_path)
      expect(content).to include('name: Danger Comment')
    end

    it 'triggers on workflow_run completion' do
      content = File.read(danger_comment_yml_path)
      expect(content).to include('workflow_run:')
      expect(content).to include('workflows: [Danger]')
      expect(content).to include('types: [completed]')
    end

    it 'uses the reusable workflow' do
      content = File.read(danger_comment_yml_path)
      expect(content).to include('uses: numbata/danger-pr-comment/.github/workflows/danger-comment.yml@v0.1.1')
    end

    it 'inherits secrets' do
      content = File.read(danger_comment_yml_path)
      expect(content).to include('secrets: inherit')
    end

    it 'includes required permissions' do
      content = File.read(danger_comment_yml_path)
      expect(content).to include('permissions:')
      expect(content).to include('actions: read')
      expect(content).to include('issues: write')
      expect(content).to include('pull-requests: write')
    end
  end

  describe '--force option' do
    context 'when files already exist' do
      before do
        FileUtils.mkdir_p(File.join(tmpdir, '.github/workflows'))
        File.write(danger_yml_path, 'existing content')
        File.write(danger_comment_yml_path, 'existing content')
      end

      it 'fails without --force flag' do
        expect(run_script?('--root', tmpdir)).to be false
      end

      it 'succeeds with --force flag' do
        expect(run_script?('--root', tmpdir, '--force')).to be true
      end

      it 'overwrites existing files with --force flag' do
        run_script?('--root', tmpdir, '--force')

        danger_content = File.read(danger_yml_path)
        expect(danger_content).not_to eq('existing content')
        expect(danger_content).to include('name: Danger')
      end
    end
  end

  describe '--root option' do
    it 'creates files in the specified root directory' do
      custom_root = File.join(tmpdir, 'custom')
      FileUtils.mkdir_p(custom_root)

      run_script?('--root', custom_root)

      expect(File.exist?(File.join(custom_root, '.github/workflows/danger.yml'))).to be true
      expect(File.exist?(File.join(custom_root, '.github/workflows/danger-comment.yml'))).to be true
    end
  end

  describe '--help option' do
    it 'exits successfully with -h' do
      expect(run_script?('-h')).to be true
    end

    it 'exits successfully with --help' do
      expect(run_script?('--help')).to be true
    end
  end

  describe 'error handling' do
    it 'fails with unknown option' do
      expect(run_script?('--unknown')).to be false
    end
  end

  describe 'file permissions' do
    before do
      run_script?('--root', tmpdir)
    end

    it 'creates readable workflow files' do
      expect(File.readable?(danger_yml_path)).to be true
      expect(File.readable?(danger_comment_yml_path)).to be true
    end
  end
end
