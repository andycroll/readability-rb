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
  DEFAULT_MAX_ATTRIBUTES = 1000

  def self.parse(html, url: nil, max_attributes: DEFAULT_MAX_ATTRIBUTES, **options)
    doc = Nokogiri::HTML5(html, max_attributes: max_attributes)
    Document.new(doc, url: url, **options).parse
  end

  def self.readerable?(html, max_attributes: DEFAULT_MAX_ATTRIBUTES, **options)
    doc = Nokogiri::HTML5(html, max_attributes: max_attributes)
    Readerable.probably_readerable?(doc, **options)
  end
end
