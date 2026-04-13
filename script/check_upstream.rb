#!/usr/bin/env ruby
# frozen_string_literal: true

# Check if Mozilla Readability.js has changed since our last port.
# Usage: ruby script/check_upstream.rb

require "net/http"
require "json"

REPO = "mozilla/readability"
PINNED_COMMIT = "08be6b4bdb204dd333c9b7a0cfbc0e730b257252"
TRACKED_FILES = %w[
  Readability.js
  Readability-readerable.js
].freeze

def github_get(path)
  uri = URI("https://api.github.com#{path}")
  req = Net::HTTP::Get.new(uri)
  req["Accept"] = "application/vnd.github.v3+json"
  req["User-Agent"] = "readability-rb-upstream-check"

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  JSON.parse(response.body)
end

puts "Checking upstream mozilla/readability for changes..."
puts "Pinned to: #{PINNED_COMMIT[0..11]}"
puts

# Get current main HEAD
main_ref = github_get("/repos/#{REPO}/git/ref/heads/main")
current_sha = main_ref.dig("object", "sha")
puts "Current main: #{current_sha[0..11]}"

if current_sha == PINNED_COMMIT
  puts "\n=> Up to date. No changes since pinned commit."
  exit 0
end

# Compare pinned commit to current main
comparison = github_get("/repos/#{REPO}/compare/#{PINNED_COMMIT}...#{current_sha}")
total_commits = comparison["total_commits"] || comparison.dig("ahead_by") || 0
puts "#{total_commits} commits ahead of pinned version\n\n"

changed_files = (comparison["files"] || []).map { |f| f["filename"] }

# Check source files
source_changes = changed_files.select { |f| TRACKED_FILES.include?(f) }
if source_changes.any?
  puts "SOURCE FILES CHANGED:"
  source_changes.each { |f| puts "  - #{f}" }
  puts
  puts "  Run `ruby script/diff_upstream.rb` to see the full diff."
else
  puts "No source file changes."
end

# Check test fixtures
fixture_changes = changed_files.select { |f| f.start_with?("test/test-pages/") }
if fixture_changes.any?
  puts "\nTEST FIXTURES CHANGED (#{fixture_changes.size} files):"
  dirs = fixture_changes.map { |f| f.split("/")[2] }.uniq.sort
  dirs.each { |d| puts "  - #{d}" }
  puts
  puts "  Run `ruby script/download_fixtures.rb` to update fixtures."
else
  puts "No test fixture changes."
end

# Check test infrastructure
test_changes = changed_files.select { |f| f.start_with?("test/") && !f.start_with?("test/test-pages/") }
if test_changes.any?
  puts "\nTEST INFRASTRUCTURE CHANGED:"
  test_changes.each { |f| puts "  - #{f}" }
end

puts "\n=> Update needed." if source_changes.any? || fixture_changes.any?
