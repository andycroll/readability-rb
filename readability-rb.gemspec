# frozen_string_literal: true

require_relative "lib/readability/version"

Gem::Specification.new do |spec|
  spec.name = "readability-rb"
  spec.version = Readability::VERSION
  spec.authors = ["Andy Croll"]
  spec.email = ["andy@goodscary.com"]
  spec.summary = "Extract readable article content from HTML pages"
  spec.description = "Ruby port of Mozilla Readability.js - extracts the main content from web pages, like Firefox Reader View"
  spec.homepage = "https://github.com/andycroll/readability-rb"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/andycroll/readability-rb",
    "changelog_uri" => "https://github.com/andycroll/readability-rb/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/andycroll/readability-rb/issues",
  }

  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "nokogiri", "~> 1.14"
end
