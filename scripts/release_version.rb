# frozen_string_literal: true

command = ARGV.first
abort 'Usage: ruby scripts/release_version.rb read|bump' unless ARGV.length == 1 && %w[read bump].include?(command)

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
when 'bump'
  parts = version.split('.').map(&:to_i)
  parts[2] += 1
  next_version = parts.join('.')
  File.write(path, content.sub(pattern) { "#{Regexp.last_match(1)}#{next_version}#{Regexp.last_match(3)}" })
  puts next_version
end
