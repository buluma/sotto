# Personal-fork entitlement compatibility

## Purpose and scope

Licensing must not contact a server, block capture, or read/mutate stored activation data in this personal fork. This supersedes inherited trial/activation behavior under ADR-006’s personal-fork amendment. GPLv3 and third-party model licenses are independent of product activation.

## Producers and consumers

`EntitlementsService` is used by app composition, onboarding, settings, dictation, and optional CLI `transcribe --enforce-entitlements` setup. `DisabledLicenseAPI` is the default app/CLI dependency. `LicenseAPI`, its value types, and the service initializer remain local source/test compatibility seams; there is no LemonSqueezy HTTP implementation.

## Stable behavior

- `currentState` returns unlocked with no masked license key or validation timestamp.
- `assertCanTranscribe` succeeds without provider or Keychain I/O.
- Trial bootstrap and validation refresh are no-ops, even for stored activation older than a day.
- Activation reports a configuration error explaining that activation is unavailable and the fork is already unlocked. It sends no key, creates no instance, and changes no state.
- Deactivation returns unlocked without contacting a server or deleting stored credentials.
- Neither injected API behavior nor legacy checkout/product metadata can re-enable service calls.
- No migration or cleanup of activation/trial/install fields occurs. Existing Keychain records remain intact.
- CLI `--enforce-entitlements` remains accepted, without licensing I/O; flags, JSON schemas, and exit codes are unchanged.

Copy, dates supplied by callers, and historical metadata are not a new wire format. Changing the no-network/no-mutation behavior requires an explicit product decision, ADR update, contract update, focused tests, and CLI compatibility review.

## Verification

`EntitlementsServiceTests` exercises existing and empty state, stale validation, activation, deactivation, bootstrap, unlocked checks, an injected recording API, and a recording store. `testDisabledAPIRejectsEveryOperation` verifies the default inert provider. Identity/privacy tests remain separate; tests do not certify a live network trace.
