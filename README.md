# Readability

Ruby port of [Mozilla Readability.js](https://github.com/mozilla/readability) -- extract readable article content from HTML pages, like Firefox Reader View.

[![Gem Version](https://img.shields.io/gem/v/readability-rb)](https://rubygems.org/gems/readability-rb)
[![Build Status](https://github.com/andycroll/readability-rb/actions/workflows/ci.yml/badge.svg)](https://github.com/andycroll/readability-rb/actions)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

Passes all 130 Mozilla test fixtures.

## Installation

Add this line to your application's **Gemfile**:

```ruby
gem "readability-rb"
```

## Quick Start

```ruby
result = Readability.parse(html, url: "https://example.com/article")

result.title        # article title
result.byline       # author name
result.content      # cleaned HTML content
result.text_content # plain text content
result.excerpt      # short summary
result.length       # text content length
result.site_name    # site name
result.published_time # publication date
result.dir          # text direction
result.lang         # language
```

## Usage

### Parse an article

```ruby
html = Net::HTTP.get(URI("https://example.com/article"))
result = Readability.parse(html, url: "https://example.com/article")

puts result.title
puts result.content
```

Returns a `Readability::Result` or `nil` if parsing fails.

### Check if a page is readable

```ruby
if Readability.readerable?(html)
  result = Readability.parse(html)
end
```

Accepts `min_score` and `min_content_length` options.

```ruby
Readability.readerable?(html, min_score: 30, min_content_length: 200)
```

### Use the lower-level API

Pass a Nokogiri document directly.

```ruby
doc = Nokogiri::HTML5(html)
result = Readability::Document.new(doc, url: "https://example.com").parse
```

### Custom serializer

Replace the default HTML serializer.

```ruby
result = Readability.parse(html, serializer: ->(el) { el.to_html })
```

## Options

| Option | Description | Default |
| --- | --- | --- |
| `url` | Base URL for resolving relative links | `nil` |
| `max_elems_to_parse` | Max elements before aborting (0 = no limit) | `0` |
| `nb_top_candidates` | Number of top candidates to consider | `5` |
| `char_threshold` | Min characters for a successful parse | `500` |
| `classes_to_preserve` | CSS classes to keep on elements | `[]` |
| `keep_classes` | Preserve all CSS classes | `false` |
| `disable_json_ld` | Skip JSON-LD metadata extraction | `false` |
| `allowed_video_regex` | Regex for allowed video embed URLs | built-in |
| `link_density_modifier` | Adjust link density calculation | `0` |
| `serializer` | Lambda to serialize the content element | `inner_html` |

## Contributing

Everyone is encouraged to help improve this project. Here are a few ways you can help:

- [Report bugs](https://github.com/andycroll/readability-rb/issues)
- Fix bugs and [submit pull requests](https://github.com/andycroll/readability-rb/pulls)
- Write, clarify, or fix documentation
- Suggest or add new features

## License

Apache 2.0
