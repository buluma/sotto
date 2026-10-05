# Fork normalization status

Audit date: 2026-10-05. Baseline: `9cc07da` on `docs/reconcile-personal-fork`, followed by this inventory/documentation pass. No public release, push, data migration, or feature-default change is part of normalization. On 2026-10-05 the owner approved removing licensing network calls while preserving stored credentials.

| Phase 0 criterion | Status | Evidence / remaining work |
|---|---|---|
| Branding consistent | Mostly complete | Runtime storage/preferences use Sotto namespaces. Dormant share-link host strings preserve upstream record/URL compatibility; do not rename them as a new hosted service. Original legal attribution is intentional. |
| Privacy docs consistent | Core guides reconciled | README, spec index/vision, integrations, diagnostics, Discover, and local packaging reflect removed transports. Historical ADRs are explicitly superseded. This is not an exhaustive certification of every archived document. |
| Network surfaces inventoried | Complete source inventory | [Network boundaries](network-boundaries.md) covers downloads, providers, experimental routes, licensing, and removed services. Live packet capture remains a separate acceptance check. |
| Feature flags classified | Complete source inventory | [All 16 flags](feature-flags.md), ownership, defaults, decisions, relevance, and overrides verified against `AppFeatures.swift`. No named subsystem delegates are recorded. |
| License state explicit | Notices added; Cohere discrepancy recorded | GPLv3 and original copyright remain. `THIRD_PARTY_LICENSES.md` and bundled `SpeechModels.txt` now distinguish Cohere, Nemotron English, and Nemotron multilingual weights. Cohere conversion metadata and README disagree; that upstream discrepancy remains explicit, with no claim that all installed artifacts share the audited revision. |
| No unknown upstream service dependency | Source audit complete | Licensing HTTP transport and unused Sparkle signing support are removed. Telemetry, Discover HTTP, feedback, and sharing remain inert/removed. Configured providers and third-party downloads remain documented external boundaries. |

## Residual-dependency closure

The licensing decision is recorded in [ADR-006](../spec/adr/006-trial-and-license-activation.md) and the [local entitlement contract](../spec/contracts/licensing-local-only.md). `EntitlementsService` ignores provider/store dependencies and never reads, writes, or clears activation state. App/CLI compose `DisabledLicenseAPI`; the LemonSqueezy HTTP implementation is removed. Existing compatibility calls remain accepted without restoring networking.

The Sparkle-specific block is removed from `scripts/dist/sign_notarize.sh`. Non-Sparkle dylib/helper/app signing is preserved. Both local packaging scripts copy the new speech-model notice; weights themselves remain optional separate downloads.

The upstream sharing host remains in historical formats and dormant comments. The default transport rejects requests in every build. Keep existing local records and formats intact.

## Verification

`bash scripts/dist/test_verify_app_privacy_surface.sh` passed its packaging privacy-surface fixture tests. The native-backend focused run passed all 478 tests across `SottoCoreIdentityTests`, `CLITelemetryTests`, `DiscoverViewModelTests`, `ShareRemoteClientTests`, `SettingsViewModelTests`, and `CLIVersionTests`, including entitlement no-network/no-storage-mutation coverage. The full native-backend suite is running as the final gate. Earlier default-backend signing/archive failures and disk-full compilation were superseded by the successful focused run after generated-build cleanup. All 16 inventory names/default values match source, audit links resolve, and `git diff --check` passes. These checks do not establish native GUI permission behavior, a live network trace, signed-bundle behavior, or full capture qualification.

Residual-dependency decisions and missing notice entries are addressed. The affected runtime contracts pass focused verification; the Cohere conversion licensing discrepancy remains an explicitly recorded upstream issue. Baseline capture/recovery qualification is Phase 1, not proof implied by an implemented flag.
