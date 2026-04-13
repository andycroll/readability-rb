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
