# PRJCT RPCK

A repack catalogue and transfer client for Windows and Linux.

It indexes repack sites, normalises their listings into one model, and downloads
through the BitTorrent client built into the app — torrent files, magnets, or
plain mirrors — without handing anything off to a browser or a separate client.

## Layout

```
lib/
  bootstrap.dart        builds the long-lived services and hands them down explicitly
  core/                 primitives with no knowledge of the domain
    cache/              content-addressed disk cache
    http/               resilient client, per-host rate limiter
    platform/           download directory resolution
    result.dart         typed failure classification
    version.dart        semantic version comparison
  domain/models/        Repack, GameIndexEntry, sealed SourceOption
  sources/              one folder per repack site
    repack_source.dart  the adapter contract
    source_registry.dart
    fitgirl/            locator, page parser, adapter
  download/             transfer model, registry, magnet parsing
    engine/             torrent, magnet, direct
  update/               Hyperion manifest, version verdict, installer
  features/             startup, setup, library, repack, downloads, settings
  ui/prjct_app_bar.dart the single definition of the top bar
test/
  fixtures/             captured HTML and the live Hyperion payload
```

## Adding a repack site

1. Create `lib/sources/<name>/`.
2. Put every CSS selector in `<name>_locator.dart`.
3. Implement `RepackSourceAdapter`.
4. Add one line to the list in `bootstrap.dart`.

No feature code changes. `SourceSelector` appears in the library bar as soon as
more than one source is registered, and the contract tests in `test/sources/`
run against whatever adapter is registered.

## Commands

```sh
flutter pub get
dart analyze lib test     # scoped, preferred over a project-wide run
flutter test
flutter build linux --debug
flutter build windows --release   # from a Windows host
```

## Update channel

Releases are read from
`GET https://hyperion.alibks.dev/api/v1/apps/prjct_rpck`.

Hyperion keys releases by platform. A build whose platform has no published
release reports "up to date" rather than being offered another platform's
installer, and an update is only ever offered when the artifact carries a
SHA-256. Windows builds can replace themselves; Linux and Android builds surface
the release and leave installation to the user.

## Platform notes

- **Windows / Linux** are the supported targets.
- **Android** compiles, but writing to the shared Downloads folder needs
  scoped-storage handling that is not implemented yet; downloads fall back to
  the app's documents directory.
- `dtorrent_task` is pure Dart, so the transfer engine is identical on every
  platform.

## Testing

`flutter test` covers the pieces that break silently: magnet parsing including
base32 info hashes, bencode splicing against the info hash, the per-host
concurrency ceiling, semantic version comparison, the Hyperion manifest against
the real captured payload, and the FitGirl parser against a saved HTML fixture.

The fixture tests are the reason `fitgirl_locator.dart` exists. A site redesign
should fail `test/sources/`, not empty the grid.