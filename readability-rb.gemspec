# frozen_string_literal: true

require_relative "lib/readability/version"

Gem::Specification.new do |spec|
  spec.name = "readability-rb"
  spec.version = Readability::VERSION
  spec.authors = ["Andy"]
  spec.summary = "Extract readable article content from HTML pages"
  spec.description = "Ruby port of Mozilla Readability.js - extracts the main content from web pages"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "nokogiri", "~> 1.14"
end
