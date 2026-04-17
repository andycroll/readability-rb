# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

- Add `max_attributes` kwarg to `Readability.parse` and `Readability.readerable?` for configuring the per-element attribute limit at parse time (default `1000`)

## 0.4.0 (2026-04-17)

- Handle JSON-LD objects with multiple `@type` values (#10)

## 0.3.1 (2026-04-16)

- Fix `bin/release` to check published RubyGems version before releasing
- Re-add `bundler/gem_tasks` to Rakefile (required by release workflow)
- Update Minitest to ~> 6.0

## 0.3.0 (2026-04-14)

- Performance: replace innerHTML retry with fresh document parse (fixes Nokogiri node cache memory leak)
- Performance: cache `get_inner_text` in hot paths to avoid repeated subtree walks
- Performance: batch CSS queries in `clean_conditionally` (4 queries down to 1 per candidate)
- Performance: merge br/hr CSS queries, short-circuit element count guard
- Performance: memoize parse results in test suite (6x faster, ~10s vs ~60s)
- Add benchmark harness with `rake benchmark`
- Add release workflow with trusted publishing via OIDC
- Add `bin/release` for version bumping
- Add `bin/console` for interactive development
- Add Dependabot configuration
- Add README

## 0.2.0 (2026-04-13)

- Initial release
- Feature-complete Ruby port of Mozilla Readability.js
- Pass all 130 Mozilla test fixtures (1051 tests)
- `Readability.parse(html)` extracts article content, title, byline, excerpt, and metadata
- `Readability.readerable?(html)` for quick readability check
- Lower-level `Readability::Document.new(doc).parse` API
- 97.6% line coverage, 90.8% branch coverage
