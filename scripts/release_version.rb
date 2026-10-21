# frozen_string_literal: true

require 'date'

def unreleased_notes(content)
  content.split(/^## \[Unreleased\]$/, 2).last.split(/^## \[/, 2).first.to_s
end

def prepare_changelog(content, version)
  abort 'Expected exactly one Unreleased changelog heading' unless content.scan(/^## \[Unreleased\]$/).length == 1

  heading = Regexp.escape("## [#{version}]")
  if content.match?(/^#{heading}(?: |$)/)
    abort 'Release already appears in changelog with unprepared changes' unless content.match?(/^## \[Unreleased\]\n\n+#{heading} - \d{4}-\d{2}-\d{2}$/)

    return content
  end

  abort 'Cannot prepare a release with an empty Unreleased section' if unreleased_notes(content).strip.empty?

  content.sub(/^## \[Unreleased\]$/, "## [Unreleased]\n\n## [#{version}] - #{Time.now.utc.to_date.iso8601}")
end

def prepare_workflow_references(content, version, path)
  %w[run comment].reduce(content) do |text, workflow|
    pattern = %r{(numbata/danger-pr-comment/\.github/workflows/danger-#{workflow}\.yml@)(?:v\d+\.\d+\.\d+|main)(?=['"\s]|$)}
    abort "Expected exactly one danger-#{workflow} workflow reference in #{path}" unless text.scan(pattern).length == 1

    text.sub(pattern) { "#{Regexp.last_match(1)}v#{version}" }
  end
end

command = ARGV.first
abort 'Usage: ruby scripts/release_version.rb read|prepare|bump' unless ARGV.length == 1 && %w[read prepare bump].include?(command)

path = 'lib/danger-pr-comment/version.rb'
content = File.read(path)
pattern = /^([ \t]*VERSION = ')([^'\n]+)('[ \t]*)$/
matches = content.scan(pattern)
abort 'Expected exactly one VERSION assignment in version.rb' unless matches.length == 1

version = matches.first[1]
abort "Expected MAJOR.MINOR.PATCH, got #{version.inspect}" unless version.match?(/\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/)

case command
when 'read'
  puts version
when 'prepare'
  updates = { 'CHANGELOG.md' => prepare_changelog(File.read('CHANGELOG.md'), version) }
  %w[README.md scripts/install-workflows.sh spec/scripts/install_workflows_spec.rb].each do |file|
    updates[file] = prepare_workflow_references(File.read(file), version, file)
  end
  updates.each { |file, text| File.write(file, text) }
  puts version
when 'bump'
  parts = version.split('.').map(&:to_i)
  parts[2] += 1
  next_version = parts.join('.')
  File.write(path, content.sub(pattern) { "#{Regexp.last_match(1)}#{next_version}#{Regexp.last_match(3)}" })
  puts next_version
end
