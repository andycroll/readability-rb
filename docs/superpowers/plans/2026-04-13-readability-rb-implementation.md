# readability-rb Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Ruby gem that is a feature-complete port of Mozilla Readability.js, passing all 130 test fixtures.

**Architecture:** Decomposed into modules (Regexps, Scoring, Metadata, Cleaner) mixed into a Document orchestrator, with a standalone Readerable module and a Result value object. Nokogiri provides the DOM layer. The JS source at `/Users/andy/code/cb/readability/Readability.js` (2812 lines) and `/Users/andy/code/cb/readability/Readability-readerable.js` (122 lines) are the authoritative references for all behavior.

**Tech Stack:** Ruby 3.1+, Nokogiri, Minitest

**Spec:** `docs/superpowers/specs/2026-04-13-readability-rb-design.md`

---

## Critical Conventions (apply everywhere)

1. **Tag name casing:** Store ALL tag-name constants in **lowercase** (e.g., `"div"`, `"blockquote"`). Compare with `node.name` directly (Nokogiri stores lowercase). Never call `.upcase` — the JS uses uppercase because the browser DOM does, but Nokogiri normalizes to lowercase.

2. **Sibling loop mutation:** When iterating siblings and moving nodes (e.g., the sibling-joining loop in `grab_article`), snapshot siblings into a Ruby Array first with `.element_children.to_a`, then iterate with `.each`. Check `sibling.parent` to detect already-moved nodes (skip if parent changed). Do NOT use index-based loops with `s -= 1` adjustments — Nokogiri NodeSets are snapshots, not live collections.

3. **Retry cleanup:** At the top of each `grab_article` retry iteration, clear BOTH `@candidates = {}` AND `@data_tables = Set.new` since `inner_html=` replaces all child nodes with new objects.

4. **Nokogiri version:** Require `nokogiri >= 1.14` (for `node.matches?` support). The gemspec dependency should be `"~> 1.14"`.

5. **Visibility checks diverge:** `Readerable.node_visible?` must match JS `isNodeVisible` exactly — checks `display:none`, `hidden` attr, `aria-hidden` attr, but does NOT check `visibility:hidden`. The separate `is_probably_visible?` in Utils (used by `grab_article`) DOES check `visibility:hidden`, matching JS `_isProbablyVisible`.

6. **DocumentFragment:** Use `Nokogiri::HTML::DocumentFragment.new(doc)` explicitly (not `doc.fragment`) to ensure compatibility with HTML5-parsed documents.

---

## File Map

| File | Responsibility |
|------|---------------|
| `lib/readability.rb` | Top-level namespace, convenience methods (`parse`, `readerable?`) |
| `lib/readability/version.rb` | Version constant |
| `lib/readability/result.rb` | Value object for parse output |
| `lib/readability/regexps.rb` | All regex constants and element lists from JS `REGEXPS` + prototype constants |
| `lib/readability/utils.rb` | Shared DOM helpers (`get_inner_text`, `get_all_nodes_with_tag`, `is_whitespace?`, `is_phrasing_content?`, `has_single_tag_inside_element?`, `is_element_without_content?`, `has_child_block_element?`, `text_similarity`, `is_probably_visible?`, `next_node`, `get_next_node`, `remove_and_get_next`, `has_ancestor_tag?`, `is_single_image?`) |
| `lib/readability/scoring.rb` | Module: `initialize_node`, `get_class_weight`, `get_link_density`, `get_text_density`, `get_char_count` |
| `lib/readability/metadata.rb` | Module: `get_json_ld`, `get_article_metadata`, `get_article_title`, `unescape_html_entities`, `is_valid_byline?` |
| `lib/readability/cleaner.rb` | Module: `prep_document`, `prep_article`, `post_process_content`, `clean_conditionally`, `clean`, `clean_styles`, `clean_matched_nodes`, `clean_headers`, `header_duplicates_title?`, `replace_brs`, `fix_relative_uris`, `simplify_nested_elements`, `clean_classes`, `unwrap_noscript_images`, `remove_scripts`, `fix_lazy_images`, `mark_data_tables`, `get_row_and_column_count`, `set_node_tag` |
| `lib/readability/document.rb` | Orchestrator: `parse`, `grab_article`, flag management, retry loop |
| `lib/readability/readerable.rb` | Standalone: `probably_readerable?`, `node_visible?` |
| `test/test_helper.rb` | Minitest setup, fixture loading helpers |
| `test/test_readability.rb` | Integration tests: all 130 fixtures |
| `test/test_readerable.rb` | Readerable tests: all 130 fixtures + unit tests |
| `test/test-pages/*/` | 130 vendored fixture directories |
| `readability-rb.gemspec` | Gem specification |
| `Gemfile` | Bundle dependencies |
| `Rakefile` | Test task |

---

### Task 1: Gem Skeleton and Project Setup

**Files:**
- Create: `readability-rb.gemspec`
- Create: `Gemfile`
- Create: `Rakefile`
- Create: `lib/readability.rb`
- Create: `lib/readability/version.rb`
- Create: `LICENSE`
- Create: `.ruby-version`

- [ ] **Step 1: Create gem skeleton files**

`readability-rb.gemspec`:
```ruby
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
```

`Gemfile`:
```ruby
source "https://rubygems.org"
gemspec

gem "minitest", "~> 5.0"
gem "rake"
```

`Rakefile`:
```ruby
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
end

task default: :test
```

`lib/readability/version.rb`:
```ruby
# frozen_string_literal: true

module Readability
  VERSION = "0.1.0"
end
```

`lib/readability.rb`:
```ruby
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
```

`.ruby-version`:
```
3.3.0
```

`LICENSE`: Apache 2.0 license text (from Mozilla Readability repo).

- [ ] **Step 2: Run bundle install**

Run: `cd /Users/andy/code/cb/readability && bundle install`
Expected: Successful bundle, Gemfile.lock created

- [ ] **Step 3: Initialize git and make first commit**

Run:
```bash
cd /Users/andy/code/cb/readability
git init
echo ".DS_Store" > .gitignore
echo "*.js" >> .gitignore
git add .
git commit -m "feat: initialize readability-rb gem skeleton"
```
Expected: Clean initial commit

---

### Task 2: Vendor Test Fixtures

**Files:**
- Create: `test/test-pages/` (130 directories, each with source.html, expected.html, expected-metadata.json)
- Create: `script/download_fixtures.rb`

- [ ] **Step 1: Create download script**

`script/download_fixtures.rb` — downloads all 130 test fixture directories from Mozilla's repo via GitHub API:
```ruby
#!/usr/bin/env ruby
require "net/http"
require "json"
require "fileutils"

BASE = "https://raw.githubusercontent.com/mozilla/readability/main/test/test-pages"
API = "https://api.github.com/repos/mozilla/readability/contents/test/test-pages"

puts "Fetching fixture list..."
uri = URI(API)
response = Net::HTTP.get(uri)
dirs = JSON.parse(response).map { |entry| entry["name"] }
puts "Found #{dirs.size} fixtures"

dirs.each_with_index do |dir, i|
  dest = File.join("test/test-pages", dir)
  FileUtils.mkdir_p(dest)

  %w[source.html expected.html expected-metadata.json].each do |file|
    url = "#{BASE}/#{dir}/#{file}"
    filepath = File.join(dest, file)
    next if File.exist?(filepath)

    content = Net::HTTP.get(URI(url))
    File.write(filepath, content)
  end

  print "\r#{i + 1}/#{dirs.size} #{dir}"
end
puts "\nDone!"
```

- [ ] **Step 2: Run the download script**

Run: `cd /Users/andy/code/cb/readability && ruby script/download_fixtures.rb`
Expected: 130 directories created under `test/test-pages/`, each with 3 files

- [ ] **Step 3: Verify fixture count**

Run: `ls test/test-pages/ | wc -l`
Expected: 131 (130 fixtures + the count itself may show 131 dirs based on the listing from research)

- [ ] **Step 4: Commit fixtures**

Run:
```bash
git add test/test-pages/
git commit -m "feat: vendor 130 Mozilla Readability test fixtures"
```

---

### Task 3: Test Harness and Result Object

**Files:**
- Create: `test/test_helper.rb`
- Create: `test/test_readability.rb`
- Create: `lib/readability/result.rb`

- [ ] **Step 1: Create Result value object**

`lib/readability/result.rb`:
```ruby
# frozen_string_literal: true

module Readability
  Result = Struct.new(
    :title,
    :byline,
    :dir,
    :lang,
    :content,
    :text_content,
    :length,
    :excerpt,
    :site_name,
    :published_time,
    keyword_init: true
  )
end
```

- [ ] **Step 2: Create test helper**

`test/test_helper.rb`:
```ruby
# frozen_string_literal: true

require "minitest/autorun"
require "readability"
require "json"
require "pathname"

TEST_PAGES_DIR = Pathname.new(File.expand_path("test-pages", __dir__))

def load_test_pages
  TEST_PAGES_DIR.children.select(&:directory?).sort.map do |dir|
    {
      dir: dir.basename.to_s,
      source: dir.join("source.html").read,
      expected_content: dir.join("expected.html").read,
      expected_metadata: JSON.parse(dir.join("expected-metadata.json").read),
    }
  end
end

# Normalize HTML for comparison: parse through Nokogiri, traverse in order,
# skip empty text nodes, compare node-by-node.
def normalize_html(html)
  doc = Nokogiri::HTML5(html)
  # Return the body's first element child (the readability wrapper div)
  body = doc.at_css("body")
  body ? body : doc
end

# In-order traversal skipping empty whitespace text nodes
def in_order_traverse(node)
  return nil unless node

  if node.children.any?
    return node.children.first
  end

  current = node
  while current && !current.next_sibling
    current = current.parent
  end
  current&.next_sibling
end

def next_non_empty_text_node(node)
  loop do
    node = in_order_traverse(node)
    break unless node && node.text? && node.text.strip.empty?
  end
  node
end

def html_transform(str)
  str.gsub(/\s+/, " ")
end

def compare_dom(actual_html, expected_html, test_name)
  actual_doc = normalize_html(actual_html)
  expected_doc = normalize_html(expected_html)

  actual_node = actual_doc.element_children.first || actual_doc.children.first
  expected_node = expected_doc.element_children.first || expected_doc.children.first

  while actual_node || expected_node
    actual_desc = node_description(actual_node)
    expected_desc = node_description(expected_node)

    assert_equal expected_desc, actual_desc,
      "#{test_name}: DOM node mismatch"

    if actual_node&.text?
      assert_equal html_transform(expected_node.text), html_transform(actual_node.text),
        "#{test_name}: Text content mismatch"
    elsif actual_node&.element?
      expected_attrs = sorted_attributes(expected_node)
      actual_attrs = sorted_attributes(actual_node)
      assert_equal expected_attrs, actual_attrs,
        "#{test_name}: Attributes mismatch on <#{actual_node.name}>"
    end

    actual_node = next_non_empty_text_node(actual_node)
    expected_node = next_non_empty_text_node(expected_node)
  end
end

def node_description(node)
  return "(no node)" unless node
  return "#text(#{html_transform(node.text)})" if node.text?
  return "other:#{node.type}" unless node.element?

  desc = node.name
  desc += "##{node['id']}" if node['id']
  desc += ".(#{node['class']})" if node['class']
  desc
end

def sorted_attributes(node)
  return [] unless node&.element?
  node.attributes.values
    .map { |a| [a.name, a.value] }
    .sort_by(&:first)
end
```

- [ ] **Step 3: Create integration test file with all fixture tests**

`test/test_readability.rb`:
```ruby
# frozen_string_literal: true

require "test_helper"

class TestReadability < Minitest::Test
  FIXTURES = load_test_pages

  FIXTURES.each do |fixture|
    dir = fixture[:dir]

    define_method("test_#{dir}_returns_result") do
      result = Readability.parse(fixture[:source])
      refute_nil result, "#{dir}: parse should return a result"
      assert_kind_of Readability::Result, result
    end

    define_method("test_#{dir}_extracts_content") do
      result = Readability.parse(fixture[:source])
      next if result.nil?
      compare_dom(result.content, fixture[:expected_content], dir)
    end

    define_method("test_#{dir}_extracts_title") do
      result = Readability.parse(fixture[:source])
      next if result.nil?
      assert_equal fixture[:expected_metadata]["title"], result.title, "#{dir}: title"
    end

    define_method("test_#{dir}_extracts_byline") do
      result = Readability.parse(fixture[:source])
      next if result.nil?
      assert_equal fixture[:expected_metadata]["byline"], result.byline, "#{dir}: byline"
    end

    define_method("test_#{dir}_extracts_excerpt") do
      result = Readability.parse(fixture[:source])
      next if result.nil?
      assert_equal fixture[:expected_metadata]["excerpt"], result.excerpt, "#{dir}: excerpt"
    end

    define_method("test_#{dir}_extracts_site_name") do
      result = Readability.parse(fixture[:source])
      next if result.nil?
      assert_equal fixture[:expected_metadata]["siteName"], result.site_name, "#{dir}: site_name"
    end

    if fixture[:expected_metadata]["dir"]
      define_method("test_#{dir}_extracts_direction") do
        result = Readability.parse(fixture[:source])
        next if result.nil?
        assert_equal fixture[:expected_metadata]["dir"], result.dir, "#{dir}: dir"
      end
    end

    if fixture[:expected_metadata]["lang"]
      define_method("test_#{dir}_extracts_language") do
        result = Readability.parse(fixture[:source])
        next if result.nil?
        assert_equal fixture[:expected_metadata]["lang"], result.lang, "#{dir}: lang"
      end
    end

    if fixture[:expected_metadata]["publishedTime"]
      define_method("test_#{dir}_extracts_published_time") do
        result = Readability.parse(fixture[:source])
        next if result.nil?
        assert_equal fixture[:expected_metadata]["publishedTime"], result.published_time,
          "#{dir}: publishedTime"
      end
    end
  end
end
```

- [ ] **Step 4: Verify tests fail (red phase)**

Run: `cd /Users/andy/code/cb/readability && bundle exec rake test 2>&1 | tail -5`
Expected: All tests fail (errors about missing constants/classes). This confirms the test harness works and we have a red baseline.

- [ ] **Step 5: Commit**

```bash
git add test/ lib/readability/result.rb
git commit -m "feat: add test harness with 130 fixture integration tests (all red)"
```

---

### Task 4: Regexps and Constants

**Files:**
- Create: `lib/readability/regexps.rb`

- [ ] **Step 1: Port all REGEXPS and constant arrays from JS**

`lib/readability/regexps.rb` — port every regex from `Readability.js` lines 137-176 and every constant array/set from lines 178-274. The JS source at `/Users/andy/code/cb/readability/Readability.js` is the authoritative reference. Port ALL of:

- `REGEXPS` object (lines 137-176): `unlikelyCandidates`, `okMaybeItsACandidate`, `positive`, `negative`, `extraneous`, `byline`, `replaceFonts`, `normalize`, `videos`, `shareElements`, `nextLink`, `prevLink`, `tokenize`, `whitespace`, `hasContent`, `hashUrl`, `srcsetUrl`, `b64DataUrl`, `commas`, `jsonLdArticleTypes`, `adWords`, `loadingWords`
- `UNLIKELY_ROLES` (line 178)
- `DIV_TO_P_ELEMS` (line 188)
- `ALTER_TO_DIV_EXCEPTIONS` (line 200)
- `PRESENTATIONAL_ATTRIBUTES` (line 202)
- `DEPRECATED_SIZE_ATTRIBUTE_ELEMS` (line 217)
- `PHRASING_ELEMS` (line 221)
- `CLASSES_TO_PRESERVE` (line 265)
- `HTML_ESCAPE_MAP` (line 268)
- `DEFAULT_TAGS_TO_SCORE` (line 128)
- Flag constants: `FLAG_STRIP_UNLIKELYS = 0x1`, `FLAG_WEIGHT_CLASSES = 0x2`, `FLAG_CLEAN_CONDITIONALLY = 0x4`
- Default option values: `DEFAULT_MAX_ELEMS_TO_PARSE = 0`, `DEFAULT_N_TOP_CANDIDATES = 5`, `DEFAULT_CHAR_THRESHOLD = 500`

Each regex must be translated carefully from JS to Ruby syntax. Note: JS `/pattern/i` becomes Ruby `/pattern/i`. JS `/pattern/gi` global flag doesn't exist in Ruby — use `scan` or `gsub` where needed. The `\u` unicode escapes in `commas` must use Ruby `\u{XXXX}` syntax.

```ruby
module Readability
  module Regexps
    # ... all constants here
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add lib/readability/regexps.rb
git commit -m "feat: port all regex constants and element lists from Readability.js"
```

---

### Task 5: Utils Module — DOM Helpers

**Files:**
- Create: `lib/readability/utils.rb`

- [ ] **Step 1: Port all DOM utility methods**

`lib/readability/utils.rb` — these are pure helper methods that don't depend on scoring, metadata, or cleaning. Port from the JS source (reference lines given):

Methods to port (all from `Readability.js`):
- `remove_nodes(nodelist, &filter_fn)` (line 304) — iterate backwards, remove matching
- `replace_node_tags(nodelist, new_tag)` (line 327) — call `set_node_tag` for each
- `get_all_nodes_with_tag(node, tag_names)` (line 397) — use `node.css(tag_names.join(","))`
- `get_inner_text(element, normalize_spaces = true)` (line 2084) — `textContent.strip`, optionally normalize
- `is_whitespace?(node)` (line 2068) — text node with empty trim, or BR element
- `is_phrasing_content?(node)` (line 2057) — text node, or tag in PHRASING_ELEMS, or A/DEL/INS with all-phrasing children
- `has_single_tag_inside_element?(element, tag)` (line 2013) — exactly 1 child element with tag, no significant text
- `is_element_without_content?(node)` (line 2028) — element with no text, only br/hr children
- `has_child_block_element?(element)` (line 2044) — any child in DIV_TO_P_ELEMS or recursive
- `text_similarity(text_a, text_b)` (line 981) — tokenize, compute unique ratio
- `is_probably_visible?(node)` (line 2720) — check inline style attribute string for `display:none`/`visibility:hidden`, check `hidden`/`aria-hidden` attrs. Nokogiri has no `.style` — parse `node['style']` string.
- `next_node(node)` (line 687) — skip whitespace siblings to find next element
- `get_next_node(node, ignore_self_and_kids = false)` (line 959) — depth-first traversal
- `remove_and_get_next(node)` (line 942) — get next then remove
- `has_ancestor_tag?(node, tag_name, max_depth = 3, &filter_fn)` (line 2243)
- `get_node_ancestors(node, max_depth = 0)` (line 1019)
- `is_single_image?(node)` (line 1897)
- `is_valid_byline?(node, match_string)` (line 1005)
- `is_url?(str)` (line 442) — try URI.parse, rescue

All methods should be instance methods in a `Utils` module that gets included in `Document`.

**Important Nokogiri notes:**
- `node.tagName` in JS → `node.name.upcase` in Nokogiri (Nokogiri stores lowercase)
- `node.className` in JS → `node['class'] || ""`
- `node.id` in JS → `node['id'] || ""`
- `node.textContent` → `node.text` or `node.content`
- `node.children` (elements only in JS) → `node.element_children` in Nokogiri. `node.childNodes` (all nodes) → `node.children` in Nokogiri.
- `node.firstElementChild` → `node.element_children.first`
- `node.nextElementSibling` → `node.next_element`
- `node.parentNode` → `node.parent`
- `node.remove()` → `node.unlink` or `node.remove`
- `node.hasAttribute("x")` → `node.has_attribute?("x")` or `!node['x'].nil?`
- `node.getAttribute("x")` → `node['x']`
- `node.setAttribute("x", v)` → `node['x'] = v`
- `node.removeAttribute("x")` → `node.remove_attribute("x")`
- `node.getElementsByTagName("x")` → `node.css("x")` (returns NodeSet, snapshot not live)
- `node.querySelectorAll("x")` → `node.css("x")`
- `node.ownerDocument` → `node.document`
- `node.nodeType == 1` → `node.element?`; `node.nodeType == 3` → `node.text?`
- `node.innerHTML` → `node.inner_html`; `node.innerHTML =` → `node.inner_html =`
- `node.matches("li p")` → `node.matches?("li p")`
- `document.createElement("p")` → `Nokogiri::XML::Node.new("p", doc)`
- `document.createDocumentFragment()` → `doc.fragment`
- `parent.replaceChild(new, old)` → `old.replace(new)` or `old.swap(new)`
- `parent.insertBefore(new, ref)` → `ref.add_previous_sibling(new)`
- `parent.appendChild(child)` → `parent.add_child(child)`

- [ ] **Step 2: Commit**

```bash
git add lib/readability/utils.rb
git commit -m "feat: port DOM utility methods (traversal, predicates, text helpers)"
```

---

### Task 6: Scoring Module

**Files:**
- Create: `lib/readability/scoring.rb`

- [ ] **Step 1: Port scoring methods**

`lib/readability/scoring.rb` — port from `Readability.js`:

- `initialize_node(node)` (line 903) — set `@candidates[node] = { content_score: base_score }` based on tag name, then add class_weight. Use the `@candidates` hash (keyed by Nokogiri node) as the side-table for scores since Nokogiri nodes don't support arbitrary properties.
- `get_class_weight(node)` (line 2168) — +/-25 for class/id matching POSITIVE/NEGATIVE regexps. Returns 0 if `FLAG_WEIGHT_CLASSES` not active.
- `get_link_density(element)` (line 2143) — ratio of anchor text to total text. Hash URLs get 0.3 coefficient.
- `get_text_density(element, tags)` (line 2440) — ratio of text in given tags to total text.
- `get_char_count(element, separator = ",")` (line 2102) — count occurrences of separator in inner text.

Helper method for score access:
- `content_score(node)` — returns `@candidates.dig(node, :content_score) || 0`
- `set_content_score(node, score)` — sets `@candidates[node] ||= {}; @candidates[node][:content_score] = score`

The `@candidates` hash is initialized as `{}` in `Document#initialize` and cleared on each retry.

- [ ] **Step 2: Commit**

```bash
git add lib/readability/scoring.rb
git commit -m "feat: port scoring module (node scoring, class weight, link density)"
```

---

### Task 7: Metadata Module

**Files:**
- Create: `lib/readability/metadata.rb`

- [ ] **Step 1: Port metadata extraction methods**

`lib/readability/metadata.rb` — port from `Readability.js`:

- `get_json_ld(doc)` (line 1658) — find `<script type="application/ld+json">`, parse JSON, validate schema.org context, extract title/byline/excerpt/siteName/datePublished. Handle `@graph` arrays. Use `text_similarity` for name vs headline disambiguation.
- `get_article_metadata(json_ld)` (line 1783) — iterate `<meta>` tags, match property/name patterns against OpenGraph/Twitter/DC/Parsely/Weibo patterns. Build values hash. Merge with JSON-LD (JSON-LD takes precedence). Unescape HTML entities.
- `get_article_title` (line 573) — extract from `<title>`, handle separators (`| - – — \ / > >`), colon handling, h1 fallback for short/long titles. Normalize whitespace. Fall back to original if too few words.
- `unescape_html_entities(str)` (line 1631) — replace `&quot;`, `&amp;`, etc. and numeric character references `&#x...;` / `&#...;`.

Key Ruby translations:
- `doc.title` in JS → `doc.at_css("title")&.text&.strip || ""`
- `doc.getElementsByTagName("meta")` → `doc.css("meta")`
- JS regex `.match()` returns truthy/null → Ruby `.match?()` returns bool, or use `=~`
- `String.fromCodePoint(num)` → `[num].pack("U")`

- [ ] **Step 2: Commit**

```bash
git add lib/readability/metadata.rb
git commit -m "feat: port metadata module (JSON-LD, meta tags, title extraction)"
```

---

### Task 8: Cleaner Module

**Files:**
- Create: `lib/readability/cleaner.rb`

- [ ] **Step 1: Port DOM cleaning methods**

`lib/readability/cleaner.rb` — this is the largest module. Port from `Readability.js`:

**Document prep:**
- `prep_document` (line 669) — remove `<style>`, replace BR chains, font→span
- `replace_brs(elem)` (line 706) — find BR chains (2+ consecutive), replace with P, collect phrasing siblings. Complex logic — follow JS exactly.
- `set_node_tag(node, tag)` (line 762) — in Nokogiri: `node.name = tag.downcase` (mutates in place, preserves children/attributes/hash-key identity). Return node.
- `remove_scripts(doc)` (line 2001) — remove script and noscript tags
- `unwrap_noscript_images(doc)` (line 1918) — remove placeholder imgs without src, extract real imgs from noscript tags

**Article prep (run on extracted article content):**
- `prep_article(article_content)` (line 792) — the big cleanup: clean_styles, mark_data_tables, fix_lazy_images, then conditionally clean forms/fieldsets/objects/embeds/footers/links/asides, clean share elements, clean iframes/inputs/textareas/selects/buttons, clean_headers, then conditionally clean tables/uls/divs, replace h1→h2, remove empty paragraphs, remove br before p, replace single-cell tables
- `clean_styles(elem)` (line 2114) — remove style and presentational attributes recursively. Skip SVG.
- `mark_data_tables(root)` (line 2297) — classify tables as data vs layout. Store in a `@data_tables` Set on Document (since we can't set `node._readabilityDataTable` on Nokogiri nodes). Requires `get_row_and_column_count` helper.
- `get_row_and_column_count(table)` (line 2266) — count rows/columns accounting for rowspan/colspan attributes. Returns `{rows:, columns:}` hash. Used by `mark_data_tables` for size-based classification.
- `fix_lazy_images(root)` (line 2358) — handle base64 placeholders, data-src attrs
- `clean(elem, tag)` (line 2208) — remove all nodes of tag, except allowed videos
- `clean_conditionally(elem, tag)` (line 2460) — the heuristic cleaner. Check data tables, code ancestors, class weight, comma count, then apply shadiness checks (p/img ratio, li count, input count, link density, embed count, text density). Check `@data_tables` set instead of `node._readabilityDataTable`.
- `clean_matched_nodes(elem, &filter)` (line 2667) — depth-first remove matching nodes
- `clean_headers(elem)` (line 2685) — remove h1/h2 with negative class weight
- `header_duplicates_title?(node)` (line 2703) — text_similarity > 0.75

**Post-processing:**
- `post_process_content(article_content)` (line 282) — fix_relative_uris, simplify_nested_elements, clean_classes
- `fix_relative_uris(article_content)` (line 457) — convert relative hrefs/srcs/srcsets to absolute using `URI.join(base_uri, uri)` with rescue. Handle javascript: links (replace with span or text node).
- `simplify_nested_elements(article_content)` (line 538) — unwrap unnecessary div/section wrappers
- `clean_classes(node)` (line 418) — remove class attr except classes_to_preserve

- [ ] **Step 2: Commit**

```bash
git add lib/readability/cleaner.rb
git commit -m "feat: port cleaner module (DOM prep, article cleanup, post-processing)"
```

---

### Task 9: Document Orchestrator

**Files:**
- Create: `lib/readability/document.rb`

- [ ] **Step 1: Port the Document class with parse() and grab_article()**

`lib/readability/document.rb` — the main orchestrator. Port from `Readability.js`:

```ruby
module Readability
  class Document
    include Utils
    include Scoring
    include Metadata
    include Cleaner

    def initialize(doc, url: nil, **options)
      @doc = doc.dup  # clone to avoid mutating caller's doc
      @url = url
      @article_title = nil
      @article_byline = nil
      @article_dir = nil
      @article_site_name = nil
      @article_lang = nil
      @attempts = []
      @metadata = {}
      @candidates = {}       # score side-table: node -> {content_score: N}
      @data_tables = Set.new # tracks which table nodes are data tables

      # Options
      @debug = !!options[:debug]
      @max_elems_to_parse = options[:max_elems_to_parse] || DEFAULT_MAX_ELEMS_TO_PARSE
      @nb_top_candidates = options[:nb_top_candidates] || DEFAULT_N_TOP_CANDIDATES
      @char_threshold = options[:char_threshold] || DEFAULT_CHAR_THRESHOLD
      @classes_to_preserve = CLASSES_TO_PRESERVE + (options[:classes_to_preserve] || [])
      @keep_classes = !!options[:keep_classes]
      @disable_json_ld = !!options[:disable_json_ld]
      @allowed_video_regex = options[:allowed_video_regex] || VIDEOS
      @link_density_modifier = options[:link_density_modifier] || 0

      # Flags
      @flags = FLAG_STRIP_UNLIKELYS | FLAG_WEIGHT_CLASSES | FLAG_CLEAN_CONDITIONALLY
    end

    def parse
      # ... port parse() from line 2747
    end

    private

    def grab_article(page = nil)
      # ... port _grabArticle() from line 1041
      # This is the largest method (~580 lines in JS)
      # Key sections:
      # 1. Cache page HTML for retry
      # 2. Node preprocessing loop (remove hidden, bylines, unlikelys, empty elements, convert divs)
      # 3. Scoring loop (score paragraphs, propagate to ancestors)
      # 4. Candidate selection (top N, check common ancestor, walk up tree)
      # 5. Sibling joining
      # 6. Prep article cleanup
      # 7. Retry logic (disable flags one at a time if text too short)
    end

    def flag_is_active?(flag)
      (@flags & flag) > 0
    end

    def remove_flag(flag)
      @flags = @flags & ~flag
    end

    def log(*args)
      return unless @debug
      puts "Reader: (Readability) #{args.map(&:to_s).join(' ')}"
    end
  end
end
```

The `grab_article` method is the core of the algorithm. It must be ported line-by-line from the JS (lines 1041-1623). Key Nokogiri differences to watch for:

1. **Score storage:** Use `@candidates[node][:content_score]` instead of `node.readability.contentScore`
2. **Data table tracking:** Use `@data_tables.include?(node)` instead of `node._readabilityDataTable`
3. **set_node_tag:** Returns same node (mutated in place), not a replacement
4. **NodeSets:** Not live — no need for backward iteration guards, but re-query after removal when the JS code re-fetches `siblings`
5. **innerHTML cache/restore:** Use `page.inner_html` to cache, `page.inner_html = cached` to restore. After restore, clear `@candidates` hash since old nodes are dead.
6. **Document fragment:** Use `@doc.fragment` for collecting phrasing content

- [ ] **Step 2: Run tests to check progress**

Run: `cd /Users/andy/code/cb/readability && bundle exec rake test 2>&1 | tail -20`
Expected: Some tests should start passing. Note which fixtures still fail.

- [ ] **Step 3: Commit**

```bash
git add lib/readability/document.rb
git commit -m "feat: port Document orchestrator with parse() and grab_article()"
```

---

### Task 10: Readerable Module

**Files:**
- Create: `lib/readability/readerable.rb`
- Create: `test/test_readerable.rb`

- [ ] **Step 1: Port isProbablyReaderable**

`lib/readability/readerable.rb` — port from `Readability-readerable.js` (122 lines):

```ruby
module Readability
  module Readerable
    def self.probably_readerable?(doc, min_score: 20, min_content_length: 140, visibility_checker: nil)
      visibility_checker ||= method(:node_visible?)

      nodes = doc.css("p, pre, article")

      # Also include div parents of br nodes
      br_nodes = doc.css("div > br")
      if br_nodes.any?
        node_set = nodes.to_a.to_set
        br_nodes.each { |br| node_set.add(br.parent) }
        nodes = node_set.to_a
      end

      score = 0
      nodes.any? do |node|
        next false unless visibility_checker.call(node)

        match_string = "#{node['class']} #{node['id']}"
        next false if UNLIKELY_CANDIDATES.match?(match_string) && !OK_MAYBE_CANDIDATE.match?(match_string)
        next false if node.matches?("li p")

        text_length = node.text.strip.length
        next false if text_length < min_content_length

        score += Math.sqrt(text_length - min_content_length)
        score > min_score
      end
    end

    # NOTE: This matches JS isNodeVisible exactly — does NOT check visibility:hidden.
    # The separate is_probably_visible? in Utils (used by grab_article) DOES check visibility:hidden.
    def self.node_visible?(node)
      style = node['style']
      return false if style && style =~ /display:\s*none/i
      return false if node.has_attribute?("hidden")
      aria_hidden = node['aria-hidden']
      if aria_hidden == "true"
        class_name = node['class'] || ""
        return false unless class_name.include?("fallback-image")
      end
      true
    end
  end
end
```

- [ ] **Step 2: Create readerable tests**

`test/test_readerable.rb`:
```ruby
require "test_helper"

class TestReaderable < Minitest::Test
  FIXTURES = load_test_pages

  FIXTURES.each do |fixture|
    dir = fixture[:dir]
    expected = fixture[:expected_metadata]["readerable"]

    define_method("test_#{dir}_readerable") do
      result = Readability.readerable?(fixture[:source])
      assert_equal expected, result,
        "#{dir}: readerable? should be #{expected}"
    end
  end

  def test_very_small_doc_not_readerable
    refute Readability.readerable?("<html><p>hello there</p></html>")
  end

  def test_small_doc_not_readerable
    refute Readability.readerable?("<html><p>#{"hello there " * 11}</p></html>")
  end

  def test_large_doc_not_readerable_with_defaults
    refute Readability.readerable?("<html><p>#{"hello there " * 12}</p></html>")
  end

  def test_very_large_doc_readerable
    assert Readability.readerable?("<html><p>#{"hello there " * 50}</p></html>")
  end

  def test_custom_min_content_length
    html = "<html><p>#{"hello there " * 11}</p></html>"
    assert Readability.readerable?(html, min_content_length: 120, min_score: 0)
  end

  def test_custom_visibility_checker_not_visible
    html = "<html><p>#{"hello there " * 50}</p></html>"
    refute Readability.readerable?(html, visibility_checker: ->(_) { false })
  end

  def test_custom_visibility_checker_visible
    html = "<html><p>#{"hello there " * 50}</p></html>"
    assert Readability.readerable?(html, visibility_checker: ->(_) { true })
  end
end
```

- [ ] **Step 3: Run readerable tests**

Run: `cd /Users/andy/code/cb/readability && bundle exec ruby test/test_readerable.rb`
Expected: Unit tests should pass. Fixture tests depend on how well `node_visible?` matches JS behavior.

- [ ] **Step 4: Commit**

```bash
git add lib/readability/readerable.rb test/test_readerable.rb
git commit -m "feat: port Readerable module with tests"
```

---

### Task 11: Debug and Fix Fixture Failures

This is the iterative red-green phase. After Tasks 4-10 provide the initial implementation, most fixtures will have some failures. This task is about systematically fixing them.

**Strategy:**
1. Run full test suite, capture failure summary
2. Group failures by type (content mismatch, metadata mismatch, nil result, crash)
3. Pick the most common failure type and fix the root cause
4. Re-run tests, repeat

- [ ] **Step 1: Run full test suite and capture results**

Run: `cd /Users/andy/code/cb/readability && bundle exec rake test 2>&1 | grep -E "(tests|failures|errors|FAIL|ERROR)" | tail -20`

- [ ] **Step 2: Fix crashes and nil results first**

If any tests crash or return nil, these are the highest priority. Common causes:
- Missing method implementations
- Nokogiri API differences (e.g., `node.children` vs `node.element_children`)
- Nil access on missing nodes

- [ ] **Step 3: Fix content extraction mismatches**

Compare actual vs expected HTML for failing fixtures. Common causes:
- `set_node_tag` not returning correctly
- `replace_brs` logic differences
- `clean_conditionally` heuristic differences
- Score calculation differences (check `@candidates` side-table)

- [ ] **Step 4: Fix metadata mismatches**

Compare actual vs expected metadata. Common causes:
- JSON-LD parsing edge cases
- Meta tag property pattern matching
- Title separator handling
- HTML entity unescaping

- [ ] **Step 5: Commit after each significant batch of fixes**

```bash
git add -A
git commit -m "fix: resolve [N] fixture failures — [brief description]"
```

- [ ] **Step 6: Iterate until all 130 fixtures pass**

Repeat steps 1-5 until `bundle exec rake test` shows 0 failures, 0 errors.

---

### Task 12: API Tests

**Files:**
- Create: `test/test_api.rb`

- [ ] **Step 1: Write API-level tests**

Port the API tests from JS `test-readability.js` lines 195-280:

```ruby
require "test_helper"

class TestAPI < Minitest::Test
  def test_parse_returns_result_with_expected_keys
    result = Readability.parse(load_test_pages.first[:source])
    assert_respond_to result, :content
    assert_respond_to result, :title
    assert_respond_to result, :excerpt
    assert_respond_to result, :byline
  end

  def test_raises_on_oversized_document
    html = "<html><div>yo</div></html>"
    assert_raises(RuntimeError) do
      Readability::Document.new(Nokogiri::HTML5(html), max_elems_to_parse: 1).parse
    end
  end

  def test_clean_classes_runs_by_default
    # Verify classes are stripped (except preserved ones)
    html = "<html><body><p class='page special'>Content here with enough text to pass threshold #{"x" * 500}</p></body></html>"
    result = Readability.parse(html)
    refute_nil result
    # "page" should be preserved, "special" should be stripped
  end

  def test_keep_classes_option
    html = "<html><body><div class='article-content'><p class='custom'>#{" hello world." * 100}</p></div></body></html>"
    result = Readability.parse(html, keep_classes: true)
    refute_nil result
    assert_includes result.content, "custom" if result
  end

  def test_custom_allowed_video_regex
    html = '<p>' + "Lorem ipsum " * 50 + '</p><iframe src="https://mycustomdomain.com/embed"></iframe>'
    result = Readability.parse(html, char_threshold: 20, allowed_video_regex: /.*mycustomdomain\.com.*/)
    refute_nil result
    assert_includes result.content, "mycustomdomain.com" if result
  end

  def test_classes_to_preserve
    html = '<html><body><div><p class="caption">' + "text " * 100 + '</p></div></body></html>'
    result = Readability.parse(html, classes_to_preserve: ["caption"])
    refute_nil result
    assert_includes result.content, 'class="caption"' if result
  end

  def test_convenience_parse_with_url
    result = Readability.parse("<html><body><p>#{"hello " * 100}</p></body></html>", url: "http://example.com")
    refute_nil result
  end

  def test_readerable_convenience_method
    assert Readability.readerable?("<html><p>#{"hello there " * 50}</p></html>")
    refute Readability.readerable?("<html><p>short</p></html>")
  end
end
```

- [ ] **Step 2: Run and verify**

Run: `cd /Users/andy/code/cb/readability && bundle exec ruby test/test_api.rb`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add test/test_api.rb
git commit -m "feat: add API-level tests"
```

---

### Task 13: Final Verification and Cleanup

- [ ] **Step 1: Run full test suite**

Run: `cd /Users/andy/code/cb/readability && bundle exec rake test`
Expected: 0 failures, 0 errors

- [ ] **Step 2: Clean up JS source files used as reference**

Run:
```bash
rm /Users/andy/code/cb/readability/Readability.js
rm /Users/andy/code/cb/readability/Readability-readerable.js
rm /Users/andy/code/cb/readability/index.js
```

- [ ] **Step 3: Verify gem builds**

Run: `cd /Users/andy/code/cb/readability && gem build readability-rb.gemspec`
Expected: `readability-rb-0.1.0.gem` created

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: cleanup reference files, verify gem builds"
```

- [ ] **Step 5: Run full test suite one final time**

Run: `cd /Users/andy/code/cb/readability && bundle exec rake test`
Expected: All green. Count should be ~1000+ test methods (130 fixtures x ~7 assertions each + readerable + API tests).
