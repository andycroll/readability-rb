# frozen_string_literal: true

require "nokogiri"
require "json"
require "uri"

require_relative "readability/version"
require_relative "readability/result"

module Readability
  def self.parse(html, url: nil, **options)
    # Stub — will be implemented in later tasks
    nil
  end

  def self.readerable?(html, **options)
    # Stub — will be implemented in later tasks
    false
  end
end
