---
title: "refactor: Performance optimization pass"
type: refactor
status: active
date: 2026-04-13
---

# Performance Optimization Pass

## Overview

Reduce CPU and memory overhead in readability-rb without changing extracted content. All 130 test fixtures (generating 1051 test methods) must continue to pass identically — this is a pure refactor gated by the existing test suite.

## Problem Frame

The initial port prioritized correctness over performance, translating JS idioms directly to Ruby/Nokogiri. Profiling reveals repeated DOM traversals, uncached text extraction, and expensive innerHTML-based retry restores that are unnecessary in Ruby. On large, ad-heavy pages the parse can perform 80+ CSS selector queries and serialize/re-parse the full document body up to 3 times.

## Requirements Trace

- R1. Zero test regressions — all 1051 tests must pass before and after each unit
- R2. Reduce per-parse CPU time measurably on representative fixtures (small, medium, large)
- R3. Reduce peak memory allocation on retry-heavy pages
- R4. Establish a benchmark harness for ongoing performance tracking
- R5. Improve test suite runtime (currently ~60s) — secondary developer-experience goal, not a gem performance goal

## Scope Boundaries

- No functional changes — output must remain byte-identical for all fixtures
- No new dependencies (Nokolexbor evaluation is a future consideration, not this pass)
- No algorithm changes — this is about eliminating waste, not changing heuristics
- No API changes

## Context & Research

### Relevant Code and Patterns

- `lib/readability/document.rb` — `grab_article` retry loop with `inner_html` cache/restore (lines 112, 500)
- `lib/readability/cleaner.rb` — `clean_conditionally` runs 7+ CSS queries per candidate node (lines 451-490)
- `lib/readability/utils.rb` — `get_inner_text` called repeatedly on same nodes without caching; `has_child_block_element?` is recursive without memoization; `is_element_without_content?` uses two separate CSS queries
- `lib/readability/scoring.rb` — `get_link_density` calls `get_inner_text` on element and each anchor child

### Performance Profile (from repo analysis)

| Phase | Traversals | Notes |
|-------|-----------|-------|
| Pre-parse (before grab_article) | ~10 full-doc queries | Scripts, styles, fonts, meta, noscript, comments, brs |
| grab_article per iteration | 1 full walk + subtree queries per scored element | Manual walk is correct; subtree queries are the issue |
| prep_article | 15+ queries | clean_conditionally alone does 7 queries × 5 tag types |
| Post-processing | 3-4 queries | URI fixing, simplification, class cleaning |
| **Total (no retry)** | **~30** | |
| **Total (3 retries)** | **~80+** | Each retry re-parses via innerHTML |

### External References

- Nokogiri node cache: unlinked nodes persist until Document is GC'd ([Nokogiri #2349](https://github.com/sparklemotion/nokogiri/issues/2349))
- XPath `or` is 5-30% faster than CSS unions for multi-tag selectors ([Nokogiri #2323](https://github.com/sparklemotion/nokogiri/issues/2323))
- `at_css` does not short-circuit internally ([Nokogiri #2213](https://github.com/sparklemotion/nokogiri/issues/2213))

## Key Technical Decisions

- **Retry strategy: serialize post-prep body HTML once, re-parse body on retry** — The current code caches `page.inner_html` after `prep_document` has already run, then restores it on retry. This is semantically correct but leaks unlinked nodes. The fix: cache the body HTML once (after prep, before `grab_article`'s mutation loop), and on retry re-parse just the body fragment into a fresh document. This preserves the current semantics (prepped HTML is restored, not raw HTML) while allowing the old Document to be GC'd. We cannot use `@original_html` (raw HTML) because that would require re-running `prep_document` on each retry. We cannot use `@doc.dup` from before prep because that would undo prep changes. Rationale: matches current semantics exactly while eliminating the node cache leak.

- **`@attempts` must store serialized HTML, not node references** — Each failed retry currently stores the `article_content` node, which roots into the old Document and prevents it from being GC'd. Instead, store `{ html: article_content.inner_html, text_length: text_length }`. On final fallback (all retries exhausted), re-parse the best attempt's HTML. This ensures old Documents can be collected between retries.

- **Cache `get_inner_text` per clean_conditionally invocation, not globally** — A global text cache across the full parse would require invalidation on every DOM mutation. Instead, cache text locally within methods that call it repeatedly on the same node (primarily `clean_conditionally` and `get_link_density`). Rationale: simple, no invalidation bugs, targets the actual hot path.

- **Reduce CSS queries in clean_conditionally via batched selectors** — Replace 7 separate `node.css("tag")` calls with fewer batched queries. A full single-traversal replacement is tempting but complex: `get_text_density` sums `.text` on each matching element (which includes recursive child text), so a flat traverse counting text node lengths would produce different numbers due to double-counting in nested matching tags. Instead, batch the simple counts into `node.css("p, img, li, input")` with a group-by on tag name (one query instead of four), and keep `get_text_density` and embed collection as separate queries. Rationale: captures most of the win (4 queries → 1) without the risk of behavioral divergence from a full rewrite.

- **Benchmark harness uses benchmark-ips and real fixtures** — Use 3 representative fixtures (small, medium, large) from the existing test suite. No synthetic benchmarks. Rationale: measures real workload, fixtures already exist.

## Open Questions

### Resolved During Planning

- **Should we switch to Nokolexbor?** No — that's a future consideration with API compatibility risk. This pass focuses on algorithmic improvements within Nokogiri.
- **Should we cache node.text globally?** No — DOM mutations invalidate text content, making a global cache error-prone. Local caching within method scope is safer and targets the hot path.

### Deferred to Implementation

- **Exact improvement percentages** — will be measured by the benchmark harness after changes
- **Whether XPath `or` vs CSS union matters measurably in practice** — benchmark-ips comparison needed on real fixtures
- **Whether `DocumentFragment` elimination is measurable** — may be negligible compared to other improvements

## Implementation Units

- [ ] **Unit 1: Benchmark harness**

  **Goal:** Establish a repeatable benchmark that measures parse time and memory for representative fixtures, providing a before/after baseline.

  **Requirements:** R4

  **Dependencies:** None

  **Files:**
  - Create: `benchmark/parse_benchmark.rb`
  - Create: `benchmark/README.md`

  **Approach:**
  - Use `benchmark-ips` for CPU comparisons, `benchmark-memory` for allocation tracking
  - Select 4 fixtures: a small blog post (~5KB), a medium news article (~50KB), the largest fixture (yahoo-2 at 1.6MB), and a fixture known to trigger retries (identify by running with `debug: true` and looking for multiple "Starting grabArticle loop" messages)
  - Measure: `Readability.parse` wall time, iterations/second, memory allocated
  - Add a Rake task `rake benchmark` for easy invocation
  - Record baseline numbers in `benchmark/README.md` before any optimization

  **Patterns to follow:**
  - Standard `benchmark-ips` structure with `Benchmark.ips { |x| x.report(...); x.compare! }`

  **Test scenarios:**
  - Benchmark runs without error on all 3 fixtures
  - Results are reproducible (low standard deviation)

  **Verification:**
  - `rake benchmark` runs and produces readable output with iterations/second for each fixture size

- [ ] **Unit 2: Cache `get_inner_text` in hot paths**

  **Goal:** Eliminate repeated `node.text` subtree walks within methods that query the same node multiple times.

  **Requirements:** R1, R2

  **Dependencies:** Unit 1 (for measurement)

  **Files:**
  - Modify: `lib/readability/cleaner.rb`
  - Modify: `lib/readability/scoring.rb`

  **Approach:**
  - In `clean_conditionally`: cache `get_inner_text(node)` in a local variable at the top of the per-node block. Use it for `get_char_count`, content_length, and the ad/loading word checks. Pass cached text to `get_link_density` or restructure to avoid re-extraction.
  - In `get_link_density`: cache the outer `get_inner_text(element)` and avoid re-calling it.
  - Do not introduce a global cache — local variables within method scope only.

  **Patterns to follow:**
  - The existing pattern in `grab_article` line 270: `inner_text = get_inner_text(element_to_score)`

  **Test scenarios:**
  - All 1051 tests pass
  - Benchmark shows measurable improvement on large fixture

  **Verification:**
  - `rake test` — 0 failures
  - `rake benchmark` — measurable improvement on medium and large fixtures

- [ ] **Unit 3: Batch CSS queries in `clean_conditionally`**

  **Goal:** Reduce CSS queries per candidate node from 7+ to 3-4 by batching compatible selectors.

  **Requirements:** R1, R2

  **Dependencies:** Unit 2 (builds on the same method)

  **Files:**
  - Modify: `lib/readability/cleaner.rb`

  **Approach:**
  - Replace 4 separate count queries (`node.css("p").length`, `node.css("img").length`, `node.css("li").length`, `node.css("input").length`) with a single batched query: `node.css("p, img, li, input")` followed by `group_by(&:name)` to get per-tag counts. This reduces 4 subtree traversals to 1.
  - Keep `get_text_density` and `get_all_nodes_with_tag(node, ["object", "embed", "iframe"])` as separate queries. `get_text_density` sums `.text` on each matching element, which includes recursive child text — a flat traversal would produce different numbers due to double-counting in nested matching tags. Preserving these as separate queries avoids behavioral divergence.
  - Net result: ~4 queries per candidate instead of ~7, across 5 `clean_conditionally` calls.

  **Patterns to follow:**
  - `Hash.new(0)` for tag counters from grouped NodeSet

  **Test scenarios:**
  - All 1051 tests pass — output must be byte-identical
  - Benchmark shows improvement on large fixtures

  **Verification:**
  - `rake test` — 0 failures
  - `rake benchmark` — improvement on medium and large fixtures

- [ ] **Unit 4: Replace innerHTML retry with doc.dup**

  **Goal:** Eliminate the serialize-then-reparse retry strategy to reduce both CPU and memory on difficult pages.

  **Requirements:** R1, R2, R3

  **Dependencies:** None (independent of Units 2-3)

  **Files:**
  - Modify: `lib/readability/document.rb`

  **Approach:**
  - After `prep_document` runs but before `grab_article`'s `while true` loop, serialize the prepped body once: `prepped_body_html = page.inner_html`. This captures the state after scripts/styles/brs/fonts are cleaned but before scoring mutations.
  - On retry, create a fresh document from the cached prepped body: wrap `prepped_body_html` in a minimal HTML shell, parse with `Nokogiri::HTML5`, and re-acquire `page`. This lets the old Document (with all its unlinked node cache) be GC'd.
  - Clear `@candidates`, `@data_tables`, and all node-referencing instance variables (`@article_byline`, `@article_dir`, `@article_lang`) on retry.
  - Change `@attempts` to store serialized HTML instead of node references: `{ html: article_content.inner_html, text_length: text_length }`. On final fallback (all retries exhausted), re-parse the best attempt's HTML into a fresh node. This prevents old Documents from being pinned in memory by `@attempts`.
  - Do NOT re-parse from the original raw HTML — that would require re-running `prep_document` on each retry, changing semantics.
  - Do NOT use `@doc.dup` from before prep — that would undo prep changes.

  **Test scenarios:**
  - All 1051 tests pass
  - Fixtures that trigger retries (short articles, pages with many unlikely candidates) still produce correct output
  - Memory profiler shows no unbounded growth across retries

  **Verification:**
  - `rake test` — 0 failures
  - `rake benchmark` — improvement on retry-heavy fixtures
  - Memory profiler shows flat or declining RSS across retry iterations

- [ ] **Unit 5: Consolidate pre-parse traversals**

  **Goal:** Reduce the ~10 full-document CSS queries that run before `grab_article`.

  **Requirements:** R1, R2

  **Dependencies:** None

  **Files:**
  - Modify: `lib/readability/cleaner.rb`
  - Modify: `lib/readability/document.rb`
  - Modify: `lib/readability/utils.rb`

  **Approach:**
  - Combine `is_element_without_content?` two CSS queries (`node.css("br").length + node.css("hr").length`) into one: `node.css("br, hr").length`
  - Replace `@doc.css("*").length` element count guard with a `traverse` that short-circuits when count exceeds `@max_elems_to_parse`
  - Evaluate merging adjacent full-doc queries (e.g., `remove_scripts` + `prep_document` style removal) into a single traversal. Only merge if the logic remains clear.
  - Memoize `has_child_block_element?` using a per-parse Set of already-checked nodes to avoid O(n^2) on deeply nested divs

  **Test scenarios:**
  - All 1051 tests pass
  - Benchmark shows modest improvement on all fixture sizes

  **Verification:**
  - `rake test` — 0 failures
  - `rake benchmark` — improvement visible on large fixtures

- [ ] **Unit 6: Test suite speedup — memoize parse results per fixture**

  **Goal:** Reduce test suite runtime by not re-parsing each fixture 5-8 times.

  **Requirements:** R1, R5

  **Dependencies:** None (independent of library changes)

  **Files:**
  - Modify: `test/test_readability.rb`

  **Approach:**
  - Extract `Readability.parse(fixture[:source], ...)` into a memoized result per fixture, computed once and shared across all test methods for that fixture
  - Use a class-level Hash keyed by fixture directory name
  - Each `define_method` block reads from the cache instead of re-parsing

  **Patterns to follow:**
  - `RESULTS ||= {}; RESULTS[dir] ||= Readability.parse(...)`

  **Test scenarios:**
  - All 1051 tests still pass
  - Suite runtime drops from ~60s to ~10-15s

  **Verification:**
  - `rake test` — 0 failures, runtime reduced significantly

- [ ] **Unit 7: Record final benchmarks and document**

  **Goal:** Capture before/after comparison and document the optimizations.

  **Requirements:** R4

  **Dependencies:** Units 2-6

  **Files:**
  - Modify: `benchmark/README.md`

  **Approach:**
  - Run `rake benchmark` and record final numbers alongside the Unit 1 baseline
  - Summarize improvements by fixture size
  - Note any remaining optimization opportunities for future work (Nokolexbor, XPath `or`, etc.)

  **Verification:**
  - `benchmark/README.md` contains before/after comparison table

## System-Wide Impact

- **Interaction graph:** No external interfaces change. All optimizations are internal to the parse pipeline.
- **Error propagation:** Retry behavior must remain identical — same number of retries, same flag progression, same fallback to longest attempt.
- **State lifecycle risks:** The retry strategy replaces `@doc` with a fresh document. All instance variables that reference nodes in the old document must be reset: `@candidates`, `@data_tables`, `@article_byline`, `@article_dir`, `@article_lang`. The `@attempts` array stores serialized HTML (not node references) so it does not pin old documents in memory.
- **API surface parity:** No API changes. `Readability.parse` and `Readability.readerable?` signatures unchanged.
- **Integration coverage:** The 130 fixture tests ARE the integration coverage — they compare output byte-for-byte against Mozilla's expected results.

## Risks & Dependencies

- **Risk: Behavioral divergence from innerHTML restore** — The doc.dup retry strategy changes how the DOM is rebuilt between retries. Nokogiri's HTML5 parser may produce subtly different trees when re-parsing a serialized string vs cloning a pre-mutation document. Mitigation: the test suite catches any content differences. Run the full suite after each change.
- **Risk: Benchmark noise** — Ruby benchmarks are noisy due to GC. Mitigation: use `benchmark-ips` which handles warmup and statistical confidence. Run benchmarks multiple times.
- **Dependency: benchmark-ips and benchmark-memory gems** — Add to Gemfile as development dependencies.

## Sources & References

- Related code: `lib/readability/document.rb`, `lib/readability/cleaner.rb`, `lib/readability/utils.rb`, `lib/readability/scoring.rb`
- Nokogiri node cache behavior: [#2349](https://github.com/sparklemotion/nokogiri/issues/2349)
- XPath OR performance: [#2323](https://github.com/sparklemotion/nokogiri/issues/2323)
- Nokolexbor (future consideration): [github.com/serpapi/nokolexbor](https://github.com/serpapi/nokolexbor)
