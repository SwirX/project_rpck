## What changed

## Why

## How it was verified

- [ ] `dart analyze lib test` is clean
- [ ] `flutter test` passes
- [ ] `flutter build linux --release` succeeds

## If a repack source changed

- [ ] Selectors were updated in the source's own `locator` file
- [ ] The fixture under `test/fixtures/<source>/` was refreshed
- [ ] The parser tests were run against the new fixture
