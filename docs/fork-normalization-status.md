# Fork normalization status

Audit date: 2026-10-05. Baseline: `9cc07da` on `docs/reconcile-personal-fork`, followed by this inventory/documentation pass. No public release, push, data migration, licensing removal, or feature-default change is part of normalization.

| Phase 0 criterion | Status | Evidence / remaining work |
|---|---|---|
| Branding consistent | Mostly complete | Runtime storage/preferences use Sotto namespaces. Dormant share-link host strings preserve upstream record/URL compatibility; do not rename them as a new hosted service. Original legal attribution is intentional. |
| Privacy docs consistent | Core guides reconciled | README, spec index/vision, integrations, diagnostics, Discover, and local packaging reflect removed transports. Historical ADRs are explicitly superseded. This is not an exhaustive certification of every archived document. |
| Network surfaces inventoried | Complete source inventory | [Network boundaries](network-boundaries.md) covers downloads, providers, experimental routes, licensing, and removed services. Live packet capture remains a separate acceptance check. |
| Feature flags classified | Complete source inventory | [All 16 flags](feature-flags.md), ownership, defaults, decisions, relevance, and overrides verified against `AppFeatures.swift`. No named subsystem delegates are recorded. |
| License state explicit | Partial | GPLv3 and inherited copyright remain; third-party notices document dependencies and several models. Separate speech-weight entries for Cohere and Nemotron are not present in `THIRD_PARTY_LICENSES.md`; dependency licenses alone do not establish model-weight licensing. Exact installed/downloaded artifacts and required notices need qualification before closing this criterion. |
| No unknown upstream service dependency | Audited, with known residuals | Removed telemetry/Discover/sharing transports are inert. Conditional LemonSqueezy validation remains active; unused Sparkle-specific signing support remains in packaging. Neither is silently treated as removed. |

## Remaining upstream dependencies

`Sources/SottoCore/Licensing/LemonSqueezyLicenseAPI.swift` targets LemonSqueezy. `AppEnvironmentConfigurer` refreshes stored activation during setup; CLI transcription does so under `--enforce-entitlements`. Without stored key/instance state there is no refresh request. Entitlements remain unlocked. Retain this code under the licensing subsystem rule; a later removal needs an explicit licensing decision and governing ADR update.

`scripts/dist/sign_notarize.sh` still has a conditional Sparkle framework signing block. There is no Sparkle package dependency or app updater wiring. The block is dormant compatibility support, not an active update connection. Removing or replacing it is a separate packaging change and should preserve signing of other embedded components.

The upstream sharing host remains in link formats and dormant UI/data comments. The default sharing transport rejects requests, and `isShareLinksAvailable` returns false in every build. Keep historical formats and existing local records intact.

## Verification

`bash scripts/dist/test_verify_app_privacy_surface.sh` passed its packaging privacy-surface fixture tests. The focused Swift test run did not execute tests: the default Xcode backend failed at CLI code signing and library archiving, and the native-backend retry failed during dependency compilation with `No space left on device`. Runtime test verification remains open. The attempted selection covered `SottoCoreIdentityTests`, `CLITelemetryTests`, `DiscoverViewModelTests`, and `ShareRemoteClientTests`. No full suite was run. All 16 inventory names/default values match source, audit links resolve, and `git diff --check` passes. Source inspection establishes transport composition and defaults; it does not establish native GUI permission behavior, a network trace, signed-bundle behavior, or full capture qualification.

Phase 0 remains open until model-weight notice coverage and the residual-dependency decisions are resolved. Baseline capture/recovery qualification is Phase 1, not proof implied by an implemented flag.
