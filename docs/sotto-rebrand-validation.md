# Sotto personal rebrand validation

Implemented in this local checkout on 2026-10-04. No commits, pushes, publishing,
or user-data migration occurred. The original Git metadata disappeared during
inspection; a pre-edit backup is at `/tmp/sotto-rebrand-backup/macparakeet-before.tgz`.
The workspace directory remains `macparakeet` to avoid the existing sibling
`sotto` project. Runtime namespaces and storage use Sotto.

## Verified

- `SOTTO_SKIP_WHISPERKIT=1 SOTTO_CLI_ONLY=1 swift build --product sotto-cli` passed.
- `sotto-cli --help`, `--version`, `spec --json` (valid JSON), and command help work.
- All source/test Swift files passed frontend syntax parsing.
- All shell scripts passed `bash -n`.
- New telemetry facade, identity test and icon code passed focused swift-format lint.
- Original LICENSE and THIRD_PARTY_LICENSES.md are byte-identical to the backup.
- No URLSession, HTTP endpoint, timer, queue or retry transport remains in the
  telemetry subsystem. GUI and CLI configure no-op services. Crash artifacts
  are retained locally instead of being drained through telemetry.
- Sparkle is removed from package dependencies, app wiring, update menus,
  bundle feed keys and packaging. Local rebuilds are the update path.

## Blocked by environment

The active developer directory is `/Library/Developer/CommandLineTools`.
Full Xcode is not installed. Standard build/full test gating fails because
`actool`/`xcstringstool` are unavailable. Reduced GUI compilation also lacks
SwiftUIMacros; focused CLI/identity test compilation lacks XCTest. No tests ran,
and the native app was not launched or visually verified. Full `swift test`
was attempted once. no-mistakes is not installed.

The reduced build excludes WhisperKit and streaming Markdown; success does not
qualify the normal app dependency graph or experimental feature gates.
