# readability-rb Design Spec

Ruby port of [Mozilla Readability.js](https://github.com/mozilla/readability) — extracts readable article content from HTML pages.

## Goals

- Feature-complete port of Mozilla Readability.js
- Pass all 130 Mozilla test fixtures
- Idiomatic Ruby API with Nokogiri as the DOM layer
- Single runtime dependency: Nokogiri (already present in Rails projects)
- Minitest test suite

## Public API

### Convenience entry point

```ruby
result = Readability.parse(html_string, url: "https://example.com")
Readability.readerable?(html_string)
```

### Lower-level API

```ruby
doc = Nokogiri::HTML5(html_string)
result = Readability::Document.new(doc, url: "https://example.com").parse
```

### Result object

A value object with attributes: `title`, `byline`, `content` (HTML string), `text_content`, `excerpt`, `site_name`, `published_time`, `dir`, `lang`, `length`.

### Options

| Option | Default | Description |
|---|---|---|
| `max_elems_to_parse` | `0` | Abort if doc exceeds this (0 = no limit) |
| `nb_top_candidates` | `5` | Top scoring candidates to consider |
| `char_threshold` | `500` | Minimum chars for successful parse |
| `classes_to_preserve` | `["page"]` | Classes to keep when stripping |
| `keep_classes` | `false` | Preserve all classes |
| `disable_json_ld` | `false` | Skip JSON-LD metadata extraction |
| `allowed_video_regex` | youtube/vimeo pattern | Video URLs to preserve |
| `link_density_modifier` | `0` | Adjust link density threshold |

## Architecture

### Module decomposition

```
Readability (top-level namespace + convenience methods)
├── Document      — orchestrator, owns parse flow and flag/retry logic
├── Scoring       — module mixed into Document; node scoring, candidate selection
├── Metadata      — module mixed into Document; JSON-LD, meta tags, title extraction
├── Cleaner       — module mixed into Document; DOM prep, cleanup, post-processing
├── Readerable    — standalone; quick readability check
├── Regexps       — constants module; all regex patterns
└── Result        — value object for parse output
```

### Readability::Document (orchestrator)

Owns the `parse` method which runs this sequence:

1. Clone input Nokogiri document (never mutate caller's doc)
2. `unwrap_noscript_images` — replace lazy-load placeholders
3. `extract_json_ld` — Schema.org metadata from LD+JSON scripts
4. `remove_scripts` — strip script/noscript elements
5. `prep_document` — remove styles, fix br chains, font-to-span
6. `extract_metadata` — meta tags (OG, Twitter, DC) merged with JSON-LD
7. `extract_title` — title heuristics with separator handling
8. `grab_article` — **core scoring loop** with retry flags
9. `post_process` — absolutify URLs, simplify nesting, strip classes
10. Return `Result`

Flag-based retry: if extracted text < `char_threshold`, retries up to 3 times, disabling one flag per attempt in order: (1) `strip_unlikelys`, (2) `weight_classes`, (3) `clean_conditionally`. Each retry clones the document fresh and clears the scores hash. If all retries fail, returns the longest result found, or nil.

### Readability::Scoring (mixed into Document)

- `initialize_node(node)` — base score from tag name (+5 div, +3 pre/td/blockquote, -3 address/ol/ul/form, -5 h1-h6/th)
- `class_weight(node)` — +25/-25 per node (not per match) from class/ID regex matches against POSITIVE/NEGATIVE patterns
- `link_density(node)` — ratio of link text length to total text length
- `score_node(node)` — score paragraphs, propagate to ancestors (parent full, grandparent half, further 1/(level*3))
- `select_top_candidate(candidates)` — adjust by link density, pick top N, check common ancestor

**Score storage:** Node scores are stored in a `Hash` on the Document instance (`@candidates = {}`), keyed by Nokogiri node objects. Nokogiri nodes are stable hash keys (identity-based `eql?`/`hash`). Scores hash is cleared on each retry attempt.

### Readability::Metadata (mixed into Document)

- `extract_json_ld(doc)` — parse `<script type="application/ld+json">` for Article types
- `extract_meta_tags(doc)` — OpenGraph, Twitter Cards, Dublin Core, Parsely, Weibo
- `extract_title(doc)` — from `<title>`, handle separators, h1 fallback
- Returns structured metadata; JSON-LD takes precedence over meta tags

### Readability::Cleaner (mixed into Document)

- `prep_document(doc)` — remove styles, replace consecutive br chains with p, font-to-span
- `prep_article(node, doc)` — conditionally remove forms, tables, divs, headers, footers, iframes, inputs, buttons, share elements
- `clean_conditionally(node, tag)` — heuristic removal based on paragraph/image/embed count, link density, text density
- `post_process(node, url)` — relative-to-absolute URLs (via `URI.join`, rescuing `URI::InvalidURIError` to preserve original), simplify nested elements, strip classes

### Readability::Readerable (standalone)

- Walks visible `<p>`, `<pre>`, `<article>` nodes
- Visibility check parses inline `style` attribute as a string (Nokogiri has no style object model) — checks for `display:none`, `visibility:hidden`, plus `node['hidden']` and `node['aria-hidden']`
- Scores by text length and tag/ancestor bonuses
- Returns true if any node score exceeds threshold (default 20)
- Options: `min_content_length` (140), `min_score` (20), `visibility_checker` (proc)

### Readability::Regexps (constants)

All regex patterns from the JS REGEXPS object, ported to Ruby:
- `UNLIKELY_CANDIDATES`, `OK_MAYBE_CANDIDATE`
- `POSITIVE`, `NEGATIVE`, `EXTRANEOUS`
- `BYLINE`, `NORMALIZE_WHITESPACE`, `HAS_CONTENT`
- `VIDEOS`, `SHARE_ELEMENTS`, `JSONLD_ARTICLE_TYPES`
- etc.

### Readability::Result (value object)

Simple Struct or Data.define with: `title`, `byline`, `content`, `text_content`, `excerpt`, `site_name`, `published_time`, `dir`, `lang`, `length`.

## File Structure

```
readability-rb/
├── lib/
│   ├── readability.rb
│   └── readability/
│       ├── version.rb
│       ├── document.rb
│       ├── scoring.rb
│       ├── metadata.rb
│       ├── cleaner.rb
│       ├── readerable.rb
│       ├── regexps.rb
│       └── result.rb
├── test/
│   ├── test_helper.rb
│   ├── test_readability.rb
│   ├── test_readerable.rb
│   ├── test_metadata.rb
│   ├── test_scoring.rb
│   ├── test_cleaner.rb
│   └── test-pages/          (130 vendored Mozilla fixtures)
├── readability-rb.gemspec
├── Gemfile
├── Rakefile
└── LICENSE
```

## Testing Strategy

### Integration tests (primary correctness guarantee)

- All 130 Mozilla test fixtures: parse `source.html`, compare against `expected.html` and `expected-metadata.json`
- HTML comparison normalizes both DOMs via Nokogiri and compares node-by-node (not string equality)
- Metadata comparison checks each field individually
- Each fixture is a separate test method for granular failure reporting

### Readerable tests

- Each fixture's `expected-metadata.json` includes a `readerable` boolean (this is a test-only field, not part of the Result object — it tests the separate `Readability.readerable?` method)
- Test `Readability.readerable?` against all 130 fixtures

### Unit tests

- Scoring: known DOM fragments, class weight, link density
- Metadata: JSON-LD parsing, meta tag extraction, title edge cases
- Cleaner: br chain fixing, conditional cleaning, URL absolutification

### Red-green approach

1. Set up gem skeleton and fixture test harness (all 130 tests red)
2. Implement module by module, watching fixtures turn green
3. Unit tests written alongside each module

## Dependencies

### Runtime
- `nokogiri` — DOM parsing and manipulation (ships with Rails)

### Test
- `minitest` — ships with Ruby stdlib
- `json` — ships with Ruby stdlib

## Nokogiri-Specific Implementation Notes

- **HTML parsing:** Use `Nokogiri::HTML5` for the convenience API (matches modern browser parsing behavior, closer to what Mozilla fixtures expect). Accept pre-parsed documents in the lower-level API.
- **Tag renaming:** JS `_setNodeTag` creates a replacement node. In Nokogiri, `node.name = "new_tag"` mutates in-place — children, attributes, parent, and hash-key identity are all preserved. Simpler and correct; do not create replacement nodes.
- **NodeSets are snapshots:** Unlike browser live NodeLists, Nokogiri `css()`/`xpath()` returns a frozen snapshot. Safe to iterate forward while removing nodes. No need for backward-iteration guards from the JS. Re-query after bulk removal if current state is needed.
- **Text node merging:** Nokogiri auto-merges adjacent text nodes on `add_child`. Does not affect correctness for readability (text content is preserved), but child counts may differ from browser DOM.
- **Method lists are illustrative:** The JS has ~55 prototype methods. This spec names ~20 key ones. The remaining helpers (`is_whitespace?`, `phrasing_content?`, `has_child_block_element?`, `mark_data_tables`, `fix_lazy_images`, `text_similarity`, etc.) are implicit in the "feature-complete port" goal. Use `Readability.js` as the authoritative method reference.

## Performance Notes

- Clone document fresh for each retry attempt (avoids stale node references in scores hash)
- Avoid repeated full-document traversals — cache node lists where the JS does
- Use Nokogiri's CSS/XPath selectors efficiently (prefer `css` over manual walks when equivalent)
- No premature optimization — match JS behavior first, optimize later

## License

Apache 2.0 (matching Mozilla Readability.js)
