#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require "readability"

FIXTURES = {
  small: "001",           # ~12KB blog post
  medium: "mozilla-1",    # ~95KB article
  large: "yahoo-2",       # ~1.6MB heavy page
  retry: "hukumusume",    # ~24KB page triggering 3 grabArticle retries
}.freeze

fixture_data = FIXTURES.transform_values do |dir|
  File.read(File.join(__dir__, "../test/test-pages/#{dir}/source.html"))
end

puts "readability-rb benchmark (#{Time.now.strftime('%Y-%m-%d')})"
puts "Ruby #{RUBY_VERSION}, Nokogiri #{Nokogiri::VERSION}"
puts "-" * 60

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  fixture_data.each do |label, html|
    x.report("parse:#{label} (#{FIXTURES[label]})") do
      Readability.parse(html, url: "http://fakehost/test/page.html")
    end
  end

  x.compare!
end
