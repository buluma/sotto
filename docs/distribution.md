# Local Packaging and Optional Signing

> Personal Sotto fork: manual installation through stable and nightly GitHub releases is supported when explicitly requested by the owner. Builds use ad-hoc signing; automatic app updates and telemetry remain removed.

This repo uses Swift packages. App distribution builds those packages through Xcode and assembles a `.app` bundle for Developer ID distribution. Xcode compiles asset catalogs and generates resource lookups that work after installation on another Mac. `BUILD_SYSTEM=swiftpm` is rejected for app distribution; ordinary `swift build`, `swift test`, and SwiftPM CLI builds remain supported.

## Stable and nightly releases

Both channels call `.github/workflows/package-release.yml` to validate the candidate and wait for exact-source CI on an Ubuntu runner before allocating a Mac runner. Once CI passes, they build and verify an Apple Silicon DMG, create a draft, upload the DMG and checksum, check upload completion, then publish. A failed build creates no release; a failed upload leaves a resumable draft. Published releases and existing tags are never overwritten or moved. Releases created by the workflow token do not need to trigger a second workflow.

### Stable

Run **Stable release** from GitHub Actions on `master`, supplying a numeric `version` (for example `0.1.10`), the full `source_sha`, and `ui_verified=true`. The SHA must be reachable from `master`. Check the candidate's sidebar on startup and resize, Settings navigation, and capture before accepting it. This checkbox records the owner's manual acceptance; it does not automate UI verification. To promote a nightly, use the full commit from its release notes, not the current branch head. The candidate must contain the release tooling. The workflow creates `vX.Y.Z` at that exact commit and marks the completed release Latest. Pushing a version tag alone no longer publishes a release. Update `.github/release-version` to the next target version after a stable release.

### Nightly

**Nightly release** runs at 23:17 UTC (02:17 Nairobi the following day), or through manual dispatch. GitHub schedules run from the default branch; keep the workflow there. It selects the latest commit on `master` that changes files outside CI-excluded `docs/` and `plans/`, reads the next numeric version from `.github/release-version`, and skips a version/commit pair that already has a published nightly. Tags use `vX.Y.Z-nightly.YYYYMMDD.<12-character-sha>`. Failed builds can be retried. Nightlies are prereleases, never Latest, and only the newest 14 published nightly releases/assets are retained; their tags remain for traceability. Stable releases are not affected by cleanup.

### App identity and storage

Stable installs as `Sotto.app` (`com.sotto.Sotto`); nightly installs as `Sotto-Nightly.app` (`com.sotto.nightly`). Numeric `CFBundleShortVersionString` stays `X.Y.Z` for both. `CFBundleVersion` is a UTC build timestamp, with channel, full source commit, and build date stored separately and shown in Settings > About and Copy Build Info. Nightly has its own preferences suite and `~/Library/Application Support/Sotto-Nightly` for its database, media, logs, helpers, and models. Its default auto-save exports go to `~/Documents/Sotto-Nightly/{Transcriptions,Meetings}`. It ignores the stable meeting folder preference. There is no automatic data migration or copying between channels. Keychain-backed provider credentials remain shared; macOS permission grants are separate for each bundle identity. A standalone CLI continues using stable storage; the CLI embedded in a nightly app uses that app's identity. Shared global hotkeys can conflict if both apps are running: quit one before using dictation shortcuts.

## Local DMGs

Package an existing local app bundle with `scripts/dist/build_dmg.sh dist/Sotto.app dist/Sotto.dmg` after building it with `VERSION=X.Y.Z`. The disk image contains `Sotto.app` and an Applications shortcut. Personal builds can use ad-hoc signing; that is not Developer ID signing or notarization. Publishing remains an explicit owner action for stable builds; enabling the nightly workflow on the default branch authorizes its scheduled prereleases.

## 1) Build the app bundle

From the repo root:

```bash
scripts/dist/build_app_bundle.sh
```

This creates `dist/Sotto.app` and bundles:
- `Assets/AppIcon.icns` into `Contents/Resources/AppIcon.icns` (app icon for Dock, Finder, DMG)
- `sotto-cli` into `Contents/MacOS/sotto-cli`
- SwiftPM resource bundles into `Contents/Resources/`
- Standalone helper binaries (FFmpeg, yt-dlp helper seed, and optional Node runtime) into `Contents/Resources/` when configured by the build scripts
- No Python runtime or `uv` bootstrap is bundled (FluidAudio/CoreML STT is native Swift)

The Ask workspace uses a private JavaScript helper bundle. The app and standalone CLI bundle the pinned Pi agent-core helper plus the official Node.js 24.13.1 runtime; `scripts/build_ask_helper.sh` installs npm packages at build time with `npm ci` and esbuild, not when the app launches. The app places the helper and its generated per-package notices under `Contents/Resources/AskAgentHelper/Legal/`; its Node license is at `Contents/Resources/Legal/Node/LICENSE`. The standalone CLI uses `libexec/sotto-cli/AskAgentHelper/Legal/` and `libexec/sotto-cli/Legal/Node/LICENSE`. Keep `AskAgentHelper/Legal/dependencies.json` and every package license listed by it with the bundle. The helper receives no provider credentials; Swift retains provider calls and source access. See [THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md) for the bundled package inventory and notice policy.

`build_app_bundle.sh` automatically downloads a **statically-linked FFmpeg** from [ffmpeg.martin-riedl.de](https://ffmpeg.martin-riedl.de/) (macOS arm64, SHA256-verified). No Homebrew dependency. To use a custom binary instead, set `FFMPEG_PATH`:

```bash
FFMPEG_PATH=/absolute/path/to/static-ffmpeg scripts/dist/build_app_bundle.sh
```

The script verifies the bundled binary has no non-system dylib dependencies (portability check via `otool -L`).

`yt-dlp` is bundled as a signed helper seed. At runtime, the app/CLI copies it to `~/Library/Application Support/Sotto/bin/yt-dlp` before first YouTube transcription so future helper updates never mutate the signed app bundle. To use a pre-fetched helper in release builds, set `YTDLP_PATH`; set `BUNDLE_YTDLP=0` only for diagnostic builds.

Meeting echo suppression assets are optional for local/dev bundles, but AEC-ready release builds should require them. With `REQUIRE_MEETING_ECHO_ASSETS=1`, the bundle script builds the pinned LocalVQE runtime from source and downloads the selected v1.4 echo-only GGUF into `.build/meeting-echo-assets/` when explicit asset paths are not supplied:

```bash
export REQUIRE_MEETING_ECHO_ASSETS=1
VERSION=X.Y.Z scripts/dist/build_app_bundle.sh
```

The default model is `localvqe-v1.4-aec-200K-f32.gguf` (`SHA256=b6e43138588a83bfe903ab5e143b4020b91c1e1629f5a575ac5855ff0003c731`). It is roughly 2.9 MB before compression. The source-built runtime is copied to `Contents/Frameworks/liblocalvqe.dylib`, and the selected model is copied under `Contents/Resources/MeetingEchoSuppression/`. Release bundles must contain exactly one GGUF model so asset verification and runtime model resolution cannot drift.

The native CMake build uses host parallelism by default; if that build fails, the script cleans the build directory and retries once with `-j1`. If an interrupted prior build leaves a Git index lock in the default generated LocalVQE source checkout under `.build/`, the prep script discards that generated checkout and clones it again. Custom `LOCALVQE_SOURCE_DIR` checkouts are left in place and require manual cleanup on lock errors.

`prepare_meeting_echo_assets.sh` passes `CMAKE_OSX_DEPLOYMENT_TARGET` to the LocalVQE build, aligned with the app's `MIN_MACOS_VERSION` (default `14.2`) so the shipped `liblocalvqe.dylib` never requires a newer macOS than the app advertises support for. `build_app_bundle.sh` propagates its own `MIN_MACOS_VERSION` into the auto-prepared build automatically. The runtime cache stamp keys on the deployment target, so changing it (or picking up this fix over an older cached build) forces a rebuild rather than reusing a stale dylib.

For a deliberately serialized release build, set:

```bash
export LOCALVQE_CMAKE_BUILD_JOBS=1
export REQUIRE_MEETING_ECHO_ASSETS=1
VERSION=X.Y.Z scripts/dist/build_app_bundle.sh
```

To use prebuilt assets instead of the pinned auto-prep path, set both source paths explicitly:

```bash
export SOTTO_MEETING_ECHO_LIBRARY=/absolute/path/to/liblocalvqe.dylib
export SOTTO_MEETING_ECHO_MODEL=/absolute/path/to/localvqe-v1.4-aec-200K-f32.gguf
export SOTTO_MEETING_ECHO_MODEL_SHA256=b6e43138588a83bfe903ab5e143b4020b91c1e1629f5a575ac5855ff0003c731
export REQUIRE_MEETING_ECHO_ASSETS=1
VERSION=X.Y.Z scripts/dist/build_app_bundle.sh
```

`build_app_bundle.sh` preserves the source GGUF filename by default; override with `SOTTO_MEETING_ECHO_MODEL_NAME=<filename>.gguf` only when the source path is not the intended bundled name. Set `SOTTO_MEETING_ECHO_AUTO_PREPARE=0` to force explicit prebuilt paths and fail if they are absent.

`scripts/dist/verify_meeting_echo_assets.sh dist/Sotto.app` is the release gate. With `REQUIRE_MEETING_ECHO_ASSETS=1`, it fails if either asset is missing, if the model checksum does not match, if `liblocalvqe.dylib` is not executable, if required LocalVQE C symbols are not exported, or if `otool -L` shows non-portable dylib references outside `@rpath`, `@loader_path`, `/System/Library`, or `/usr/lib`. Without `REQUIRE_MEETING_ECHO_ASSETS=1`, missing assets are accepted and the app intentionally runs the meeting echo path as passthrough.

The verifier also inspects every bundled LocalVQE dylib (`liblocalvqe.dylib` and any dependency copied into `Contents/Frameworks/`) and every architecture slice of each, reading the Mach-O minimum-OS-version load command (`LC_BUILD_VERSION minos`, or legacy `LC_VERSION_MIN_MACOSX`) and rejecting any slice higher than the app's `LSMinimumSystemVersion`. A missing/malformed version is always a hard failure; a missing `otool`/`lipo` is a hard failure only under `STRICT_MEETING_ECHO_ASSETS=1` (implied by `REQUIRE_MEETING_ECHO_ASSETS=1`) and otherwise a skipped-check warning. When run as part of `build_app_bundle.sh`, the expected minimum is the build's `MIN_MACOS_VERSION`; run standalone against an already-built bundle, it reads `LSMinimumSystemVersion` from the bundle's `Info.plist`. `SOTTO_MEETING_ECHO_MIN_MACOS_VERSION` can supply or tighten this: it is used on its own if the bundle has no `Info.plist` yet, but once the bundle's `Info.plist` exists, it must contain a valid minimum even when an override is supplied. The effective ceiling is the lower of the override and `LSMinimumSystemVersion` — an override can only make the check stricter, never raise it above what the bundle's `Info.plist` actually advertises.

Legacy activation metadata is normally unset. `SOTTO_CHECKOUT_URL` and `SOTTO_LS_VARIANT_ID` may still be embedded as `SottoCheckoutURL` and `SottoLemonSqueezyVariantID` for source compatibility; they cannot enable licensing calls, change unlocked behavior, or modify stored credentials. Local builds do not need them.

## 2) Optional signing and notarization

Prereqs:
- A **Developer ID Application** certificate in Keychain.
- `notarytool` credentials stored in Keychain under the profile `AC_PASSWORD`:

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Verify credentials work:

```bash
xcrun notarytool history --keychain-profile "AC_PASSWORD"
```

Then:

```bash
scripts/dist/sign_notarize.sh
```

The script defaults `NOTARYTOOL_PROFILE` to `AC_PASSWORD`. Override with `NOTARYTOOL_PROFILE="other" scripts/dist/sign_notarize.sh` if needed. It submits with `--no-wait --no-progress --no-s3-acceleration`; see gotcha #1 if a submit crashes.

Outputs:
- `dist/Sotto.app` (signed + stapled)
- `dist/Sotto.dmg` (signed + stapled)

## Pre-flight and versioning

### Pre-flight

Before building, verify the codebase is ready:

```bash
# All tests must pass
swift test

# The app bundle includes the public CLI. If Sources/CLI/CHANGELOG.md has
# non-empty Unreleased entries, promote them to the required semver release and
# bump CLI.cliVersion before building the app candidate.
swift test --filter CLIVersionTests

# Fresh SwiftPM checkouts must be able to update package submodules. The bundle
# script automatically lends xcodebuild the shell Git helper path when needed.
{ test -n "${GIT_EXEC_PATH:-}" && test -x "$GIT_EXEC_PATH/git-submodule"; } || \
  test -x "$(xcrun git --exec-path)/git-submodule" || \
  test -x "$(env -u GIT_EXEC_PATH git --exec-path)/git-submodule"

# Distribution privacy/entitlement guard runs after signing, but this source
# file is the expected entitlement surface for the final app.
plutil -p scripts/dist/Sotto.entitlements
```

Decide on the version number (see Version bumping below).

Do not ship new CLI behavior under a previously published CLI version. The CLI embedded in a new app bundle must report the promoted semver from `Sources/CLI/CHANGELOG.md`.

### Version bumping

Version identifiers are local build metadata inherited from upstream; this fork has no public release channel. Keep the CLI compatibility version independent of the app bundle version.

The build script accepts `VERSION` and `BUILD_NUMBER` env vars:

```bash
VERSION=0.1.1 scripts/dist/build_app_bundle.sh   # set version explicitly
scripts/dist/build_app_bundle.sh                   # local/dev only: VERSION defaults to 0.0.0
```

- **Patch bump** (0.1.x): Bug fixes, UX improvements to existing features
- **Minor bump** (0.x.0): New user-facing features (e.g., speaker diarization GUI, batch processing)
- **Build number**: Auto-generated UTC timestamp that always increases
- **Release builds must set `VERSION=X.Y.Z` explicitly.** The script's default `0.0.0` is intentionally non-release metadata so local bundles cannot be mistaken for a release.

### Historical upstream packaging lessons

The dated release incidents below are retained technical context, not evidence of a Sotto release.

These are bugs and edge cases discovered during actual releases. Read before your first release.

#### 1. A `notarytool` crash is an incomplete upload — resubmit the same bytes

**Do not use `--wait`.** Default `notarytool submit` (progress + S3 acceleration) also SIGBUS-crashes on this Mac (exit 138) *without* `--wait`. Apple then lists a new ID that can stay `In Progress` indefinitely because the file never finished uploading. That history row is a reservation, not a receipt. Polling it cannot converge. 0.8.5 burned ~55 minutes this way; 0.8.4 morning left seven ghost DMG IDs before one Accepted. Evidence: `docs/audits/2026-09-17-0.8.5-release-postmortem.md` (historical reference; file absent from this checkout).

**Instead:** submit with the flags that printed `Successfully uploaded file` and Accepted in under a minute:

```bash
xcrun notarytool submit dist/Sotto.app.zip \
  --keychain-profile "AC_PASSWORD" \
  --no-wait --no-progress --no-s3-acceleration \
  --output-format json
# Expect: {"id":"...","message":"Successfully uploaded file",...}

xcrun notarytool info <SUBMISSION_ID> \
  --keychain-profile "AC_PASSWORD" --output-format json
```

After SIGBUS / exit 138 / any submit without `Successfully uploaded file`:

1. Preserve `dist/` (do not rebuild, do not re-sign).
2. Do **not** poll the crash-era history ID.
3. Resubmit the **same** zip or DMG with the flags above.
4. Staple only after that new ID is `Accepted`.

`sign_notarize.sh` now uses those flags and refuses to poll a submit that did not report a finished upload. Rerunning the whole script still re-signs; if submit crashed, call `notarytool submit` on the existing artifact instead of starting the script over.

#### 1a. Bound polling only after the upload actually finished

Gotcha #1a applies **after** `Successfully uploaded file`. Then `In Progress` is real Apple processing, not a ghost. Apple notes that some uploads take longer. [Apple Developer Technical Support](https://developer.apple.com/forums/thread/818575).

Poll that exact ID at a sensible interval, for example once per 60 seconds for up to 30 minutes. Stop on `Accepted`, `Invalid`, or `Rejected`. The script's polling timeout and interval are `NOTARY_TIMEOUT_SECONDS` and `NOTARY_POLL_INTERVAL_SECONDS`.

If the deadline expires while Apple still reports `In Progress` **on an ID that already printed `Successfully uploaded file`**, stop the local poller, preserve the artifact and ID, and check [Apple's service status](https://developer.apple.com/system-status/). Do not blindly rebuild. Resume bounded read-only polling of the same ID.

For `Invalid` or `Rejected`, retrieve `notarytool log <SUBMISSION_ID>` with the same profile, fix the artifact, and submit a new archive. Only staple or distribute the exact artifact whose submission is `Accepted`. Never treat an older candidate's acceptance as approval of a new build.

#### 2. DMG must include Applications symlink

Without `ln -s /Applications` in the DMG staging folder, users run the app from `/Volumes/Sotto/` instead of `/Applications/`. macOS TCC will not register apps running from a mounted DMG volume — microphone permission requests silently fail, and the app never appears in System Settings > Privacy & Security > Microphone.

The `sign_notarize.sh` script creates this symlink during DMG creation. If building a DMG manually, always include it:

```bash
ln -s /Applications dist/dmg-staging/Applications
```

#### 3. `yt-dlp_macos` is PyInstaller and needs a special signing entitlement

Sotto bundles `yt-dlp` as a helper seed. Fresh installs copy that seed from `Contents/Resources/yt-dlp` into `~/Library/Application Support/Sotto/bin/yt-dlp` before first YouTube transcription. Existing users may already have a working managed helper, so a bad bundled seed can appear as a fresh-install-only bug.

The official `yt-dlp_macos` asset is a PyInstaller binary. If the release script re-signs it with Developer ID + hardened runtime but does not include `com.apple.security.cs.disable-library-validation=true`, macOS library validation blocks PyInstaller's extracted embedded `Python.framework` at runtime:

```text
[PYI:ERROR] Failed to load Python shared library ... different Team IDs
```

This fails when a user starts YouTube transcription or opens the YouTube video playback stream extraction path. It does not affect dictation, local file transcription, meeting recording, or STT model loading.

Release requirements:
- Sign bundled `yt-dlp` with hardened runtime plus `com.apple.security.cs.disable-library-validation=true`, or do not apply hardened runtime to that helper.
- Smoke-test after signing: `dist/Sotto.app/Contents/Resources/yt-dlp --version`.
- If a bad build shipped, repair existing users by replacing `~/Library/Application Support/Sotto/bin/yt-dlp`; a fixed bundled seed alone will not help users who already copied the bad managed helper.

## Privacy Strings and Entitlements

Permission prompts require both the appropriate `Info.plist` usage string and the matching signed app entitlement when macOS gates access through TCC. The release signing script runs `scripts/dist/verify_app_privacy_surface.sh` after codesigning to catch drift before notarization.

| Capability | Info.plist key | Entitlement |
|------------|----------------|-------------|
| Microphone input | `NSMicrophoneUsageDescription` | `com.apple.security.device.audio-input` |
| System audio capture | `NSAudioCaptureUsageDescription` | macOS TCC prompt, no app entitlement |
| Calendar event read access | `NSCalendarsFullAccessUsageDescription` | `com.apple.security.personal-information.calendars` |

Microphone-only meeting capture uses only the Microphone permission and never triggers the System Audio (Screen Recording) prompt; system audio is requested only for source modes that capture it.

## Notes

- The scripts default to a single-arch Release build. For a universal binary:

```bash
UNIVERSAL=1 scripts/dist/build_app_bundle.sh
```

- `Sotto` requests microphone permission. The app bundle `Info.plist` includes `NSMicrophoneUsageDescription`.
- **Users must install to /Applications before launching.** Running directly from a mounted DMG (`/Volumes/Sotto/`) will not register with macOS TCC — the app won't appear in System Settings > Privacy & Security > Microphone, and permission requests will silently fail. The DMG includes an Applications symlink for drag-to-install.
- If a user's microphone permission gets stuck as "Denied", reset it with: `tccutil reset Microphone com.sotto.Sotto`
