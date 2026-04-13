#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "fileutils"
require "uri"

BASE_DIR = File.expand_path("../test/test-pages", __dir__)
API_URL = "https://api.github.com/repos/mozilla/readability/contents/test/test-pages"
RAW_BASE = "https://raw.githubusercontent.com/mozilla/readability/main/test/test-pages"
FILES = %w[source.html expected.html expected-metadata.json].freeze

def fetch(url, limit = 5)
  raise "Too many redirects" if limit == 0

  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 30
  http.open_timeout = 10

  request = Net::HTTP::Get.new(uri.request_uri)
  request["User-Agent"] = "ruby-readability-fixture-downloader"
  request["Accept"] = "application/vnd.github.v3+json" if url.include?("api.github.com")

  response = http.request(request)

  case response.code.to_i
  when 200
    response.body
  when 301, 302, 307, 308
    fetch(response["location"], limit - 1)
  when 403, 429
    puts "Rate limited! Status: #{response.code}"
    puts response.body
    exit 1
  else
    raise "HTTP #{response.code} for #{url}"
  end
end

puts "Fetching directory listing from GitHub API..."
body = fetch(API_URL)
dirs = JSON.parse(body)
      .select { |entry| entry["type"] == "dir" }
      .map { |entry| entry["name"] }
      .sort

puts "Found #{dirs.length} fixture directories"

dirs.each_with_index do |dir, i|
  dest_dir = File.join(BASE_DIR, dir)
  FileUtils.mkdir_p(dest_dir)

  FILES.each do |file|
    dest_path = File.join(dest_dir, file)
    next if File.exist?(dest_path)

    url = "#{RAW_BASE}/#{dir}/#{file}"
    begin
      content = fetch(url)
      File.write(dest_path, content)
    rescue => e
      puts "  WARNING: Failed to download #{dir}/#{file}: #{e.message}"
    end
  end

  print "\r[#{i + 1}/#{dirs.length}] #{dir.ljust(60)}"
  $stdout.flush
end

puts "\n\nDone!"

# Verify
downloaded = Dir.glob(File.join(BASE_DIR, "*")).select { |d| File.directory?(d) }.length
puts "Downloaded #{downloaded} fixture directories to #{BASE_DIR}"
