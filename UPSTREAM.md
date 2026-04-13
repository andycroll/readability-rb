# Upstream Tracking

This gem is a Ruby port of [Mozilla Readability.js](https://github.com/mozilla/readability).

## Pinned Upstream Version

| Key | Value |
|-----|-------|
| **Repository** | `mozilla/readability` |
| **Commit** | `08be6b4bdb204dd333c9b7a0cfbc0e730b257252` |
| **Date** | 2025-11-18 |
| **Last source change** | `d7949dc47dd9ed9ee1d3b34ffdcf3bce28cde435` (2025-09-29) |
| **Files ported** | `Readability.js`, `Readability-readerable.js` |
| **Test fixtures from** | `test/test-pages/*` at same commit |

## Checking for Updates

```bash
ruby script/check_upstream.rb
```

This compares the pinned commit against current `main` and reports any changes to the source files or test fixtures.

## Updating

1. Run `ruby script/check_upstream.rb` to see what changed
2. Run `ruby script/diff_upstream.rb` to get a full diff of source changes
3. Port changes to the Ruby code
4. Run `ruby script/download_fixtures.rb` to update test fixtures
5. Run `bundle exec rake test` to verify
6. Update the commit SHA in this file and in `script/check_upstream.rb`
