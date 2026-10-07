# Release channel identity and local storage

Stable and nightly builds share code but have separate bundle identities. The stable bundle is `com.sotto.Sotto`; nightly is `com.sotto.nightly`. No automatic app update transport is introduced.

Stable keeps existing database, preferences, media, helpers, logs, and model resolution. Nightly uses the `com.sotto.nightly` preferences domain and `~/Library/Application Support/Sotto-Nightly` for database, media, helpers, logs, and models, including Finder launches and the embedded CLI. The standalone CLI retains stable defaults. A deliberate `SOTTO_DEBUG_APP_STATE_DIR` override still takes precedence. Nightly ignores custom meeting-folder preferences and uses its own artifact root. Default auto-save exports use `~/Documents/Sotto-Nightly/{Transcriptions,Meetings}`; user-selected export destinations are preserved. No stable user files are migrated, copied, or deleted. Keychain provider credentials are shared; macOS permissions are granted separately.

Both channels retain numeric `CFBundleShortVersionString`; nightly identity is recorded in `SottoReleaseChannel`, `SottoBuildSource`, `SottoGitCommit`, and the build timestamp. About and copied build information expose channel and commit.

Stable publication requires the owner to name a full SHA reachable from master and affirm native UI acceptance. CI is checked for that exact SHA. Nightly runs after successful `CI` for a master push associated with a merged PR and packages that exact merge SHA; direct pushes and stable version-bump commits are ignored. Scheduled/manual runs continue to select the latest CI-eligible code commit on master. All triggers skip already-published version/commit pairs and publish prereleases without changing Latest. A verified DMG and checksum must be uploaded before either channel is published. Existing tags cannot be moved; published assets cannot be replaced. Retention removes only matching published nightly releases and assets beyond the newest 14; it retains tags and all stable releases.

Operational instructions are in [distribution](../../docs/distribution.md#stable-and-nightly-releases). Runtime and live Actions verification must be reported separately from static lint.

## Producers and consumers

The stable and nightly entry workflows select candidates; `package-release.yml`, `build_app_bundle.sh`, and `publish_release.py` produce bundle metadata, artifacts, tags, and releases. `BuildIdentity`, About, `AppPaths`, `AutoSaveService`, Finder, and the embedded CLI consume channel identity. Numeric versions, channel identifiers, tag patterns, bundle IDs, and stable storage behavior are contractual; build timestamps and commits vary with each candidate.

## Verification and compatibility

`AppPathsTests`, `AutoSaveServiceTests`, and `UIUXPresentationTests` cover existing adjacent behavior; nightly-specific runtime coverage and live publication qualification remain pending. Static workflow lint and syntax checks are not substitutes for those checks. Existing stable data layout and standalone CLI defaults remain compatible. Channel or storage changes must update this contract and the release instructions; published tags and assets remain immutable by workflow policy.
