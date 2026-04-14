# Readability-rb Benchmarks

Measured with `benchmark-ips` (warmup: 2s, time: 5s).

## Fixtures

| Label  | Directory    | Size   | Notes                          |
|--------|-------------|--------|--------------------------------|
| small  | 001          | ~12KB  | Simple blog post               |
| medium | mozilla-1    | ~95KB  | Standard article               |
| large  | yahoo-2      | ~1.6MB | Heavy page with many elements  |
| retry  | hukumusume   | ~24KB  | Triggers 3 grabArticle retries |

## Baseline (2026-04-13)

<!-- Results captured by running: rake benchmark -->

```
readability-rb benchmark (2026-04-13)
Ruby 4.0.2, Nokogiri 1.19.2
------------------------------------------------------------
Warming up --------------------------------------
   parse:small (001)    11.000 i/100ms
parse:medium (mozilla-1)
                         1.000 i/100ms
parse:large (yahoo-2)
                         1.000 i/100ms
parse:retry (hukumusume)
                         1.000 i/100ms
Calculating -------------------------------------
   parse:small (001)    110.588 (± 0.9%) i/s    (9.04 ms/i) -    561.000 in   5.073087s
parse:medium (mozilla-1)
                         17.414 (± 0.0%) i/s   (57.43 ms/i) -     88.000 in   5.055071s
parse:large (yahoo-2)
                          4.682 (± 0.0%) i/s  (213.58 ms/i) -     24.000 in   5.126042s
parse:retry (hukumusume)
                         10.750 (± 0.0%) i/s   (93.03 ms/i) -     54.000 in   5.023874s

Comparison:
   parse:small (001):      110.6 i/s
parse:medium (mozilla-1):   17.4 i/s - 6.35x  slower
parse:retry (hukumusume):   10.7 i/s - 10.29x  slower
parse:large (yahoo-2):       4.7 i/s - 23.62x  slower
```

## After Optimization (2026-04-13)

```
readability-rb benchmark (2026-04-13)
Ruby 4.0.2, Nokogiri 1.19.2
------------------------------------------------------------
   parse:small (001):      110.0 i/s   (9.09 ms/i)
parse:medium (mozilla-1):   17.6 i/s  (56.81 ms/i)
parse:retry (hukumusume):   11.3 i/s  (88.84 ms/i)
parse:large (yahoo-2):       4.6 i/s (215.30 ms/i)
```

### Summary

| Fixture | Before (i/s) | After (i/s) | Change |
|---------|-------------|-------------|--------|
| small   | 110.6       | 110.0       | ~same  |
| medium  | 17.4        | 17.6        | ~same  |
| retry   | 10.7        | 11.3        | +5%    |
| large   | 4.7         | 4.6         | ~same  |

CPU improvements are modest (within benchmark noise for most fixtures). The primary wins from this pass are:

- **Memory**: retry-heavy pages no longer leak unlinked Nokogiri nodes across retry iterations. `@attempts` stores serialized HTML instead of node references, allowing old Documents to be GC'd.
- **Reduced CSS queries**: `clean_conditionally` batches 4 separate CSS queries into 1 per candidate node.
- **Cached text extraction**: `get_inner_text` results are cached locally in hot paths, eliminating redundant subtree walks.
- **Test suite**: 6x faster (~10s vs ~60s) via parse result memoization.

### Future opportunities

- **Nokolexbor**: drop-in Nokogiri replacement with up to 5x faster parsing and 1000x faster CSS selectors
- **XPath `or` vs CSS unions**: 5-30% faster for multi-tag selectors ([Nokogiri #2323](https://github.com/sparklemotion/nokogiri/issues/2323))
- **DocumentFragment elimination**: skip intermediate fragment in phrasing content wrapping

## How to Run

```bash
bundle exec rake benchmark
```

## Interpreting Results

- **i/s** — iterations per second; higher is better.
- **Compare!** output shows relative performance of each fixture.
- The `retry` fixture is useful for measuring improvements to the
  `grabArticle` loop, since it exercises the retry path multiple times
  per parse.
