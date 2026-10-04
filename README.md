# Sotto

A personal, local-first voice workspace for Apple Silicon Macs, based on
[MacParakeet by Daniel Moon](https://github.com/moona3k/macparakeet).

Sotto provides system-wide dictation, file/media transcription, meeting recording,
a local transcript library, selected-text Transforms, and optional configured AI.
Speech recognition runs locally using Parakeet, Nemotron, WhisperKit, or Cohere.
Parakeet is the model name, independent of the Sotto app identity.

## Personal build

- App executable: `Sotto`; CLI: `sotto-cli`.
- Preferences: `com.sotto.Sotto`; development bundle: `com.sotto.dev`.
- Local storage: `~/Library/Application Support/Sotto`; development storage:
  `~/Library/Application Support/Sotto-Dev`; database: `sotto.db`.
- Keychain service names, process labels, environment variables, and helper
  identifiers use Sotto namespaces. Existing MacParakeet data and credentials
  are left untouched. No automatic import or destructive migration occurs.
- Remote analytics/crash telemetry transport is removed from the GUI and CLI.
  Local diagnostic logs remain. Legacy event hooks support local tests only;
  the legacy `config telemetry` preference cannot enable uploads.
- Upstream feedback UI/CLI and hosted sharing connections are removed. Debug
  arguments cannot enable sharing. Existing local records are preserved.
- App auto-updates are removed. Update source manually, review upstream changes,
  retain the personal changes, and rebuild. There is no Sotto release feed.
- Discover is a bundled, offline Rick-and-Morty-style banter feed, off by default.
- Optional cloud AI, media/model downloads, explicit
  feedback, and gated sharing are separate network features, not telemetry.
  Original service URLs remain truthful upstream references, not Sotto services.

## Build and run

Requires Apple Silicon, macOS 14.2+, and full Xcode for the normal GUI build.

```sh
swift build
swift run sotto-cli --help
scripts/dev/run_app.sh
```

For the repository's reduced compatibility graph (without WhisperKit or the
streaming Markdown renderer):

```sh
SOTTO_SKIP_WHISPERKIT=1 swift build
# CLI-only build without full Xcode:
SOTTO_SKIP_WHISPERKIT=1 SOTTO_CLI_ONLY=1 swift build --product sotto-cli
```

Automated XCTest suites and native GUI verification require full Xcode.

The dev script owns bundle wrapping, signing, permissions, and macro validation.
The working directory is intentionally still named `macparakeet`; no neighboring
Sotto project is overwritten.

## Code map

- `Sources/Sotto`: native UI, lifecycle, hotkeys, and feature coordinators.
- `Sources/SottoViewModels`: testable presentation state.
- `Sources/SottoCore`: capture, speech, text processing, persistence, and services.
- `Sources/CLI`: automation commands over shared Core services.
- `Tests/SottoTests` and `Tests/CLITests`: focused and integration coverage.
- [Architecture](spec/03-architecture.md), [spec index](spec/README.md), and
  [agent guide](AGENTS.md) describe subsystem rules and experimental feature gates.

Historical release/audit documents describe the inherited upstream project;
renaming their product references does not establish a released Sotto build.

## License and attribution

Derived from MacParakeet, Copyright (C) 2026 Daniel Moon. Original copyright and
third-party legal notices are retained. This personal fork remains GPLv3:
[LICENSE](LICENSE), [third-party notices](THIRD_PARTY_LICENSES.md).
