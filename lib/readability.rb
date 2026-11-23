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
  DEFAULT_MAX_TREE_DEPTH = 1000

  def self.parse(html, url: nil, max_attributes: DEFAULT_MAX_ATTRIBUTES, max_tree_depth: DEFAULT_MAX_TREE_DEPTH, **options)
    doc = parse_html(html, max_attributes: max_attributes, max_tree_depth: max_tree_depth)
    Document.new(doc, url: url, **options).parse
  end

  def self.readerable?(html, max_attributes: DEFAULT_MAX_ATTRIBUTES, max_tree_depth: DEFAULT_MAX_TREE_DEPTH, **options)
    doc = parse_html(html, max_attributes: max_attributes, max_tree_depth: max_tree_depth)
    Readerable.probably_readerable?(doc, **options)
  end

  # Nokogiri's HTML5 parser converts the page to UTF-8 strictly, so a byte the page's
  # charset doesn't define raises. Browsers replace such bytes with U+FFFD, so convert
  # the page that way, in the charset Nokogiri chose, and parse it again.
  def self.parse_html(html, **limits)
    Nokogiri::HTML5(html, **limits)
  rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError => e
    utf8 = html.dup.force_encoding(e.source_encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    Nokogiri::HTML5(utf8, **limits)
  end
  private_class_method :parse_html
end
