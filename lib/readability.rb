# frozen_string_literal: true

require "nokogiri"
require "json"
require "uri"

require_relative "readability/version"
require_relative "readability/result"
require_relative "readability/regexps"
require_relative "readability/utils"
require_relative "readability/scoring"
require_relative "readability/metadata"
require_relative "readability/cleaner"
require_relative "readability/document"
require_relative "readability/readerable"

module Readability
  def self.parse(html, url: nil, **options)
    doc = Nokogiri::HTML5(html)
    Document.new(doc, url: url, **options).parse
  end

  def self.readerable?(html, **options)
    doc = Nokogiri::HTML5(html)
    Readerable.probably_readerable?(doc, **options)
  end
end
