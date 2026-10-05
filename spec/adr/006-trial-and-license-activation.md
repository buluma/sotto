# ADR-006: Trial + License Key Activation

## Personal-fork amendment — 2026-10-05

The owner explicitly requested removal of licensing network calls while preserving stored credentials and unlocked behavior. This supersedes the inherited trial/activation design below. There is no LemonSqueezy HTTP transport. `EntitlementsService` retains its compatibility methods and initializer but performs no provider or Keychain I/O: bootstrap/refresh are no-ops, activation reports unavailable, deactivation preserves stored state, and capture remains unlocked. Legacy app/CLI calls cannot enable licensing networking. See the [local entitlement contract](../contracts/licensing-local-only.md).

## Historical upstream decision

> Status: **Superseded in this personal fork**
> Original date: 2026-02-12

## Context

Sotto needs a simple, local-first way to let users try the product and then unlock Pro permanently, without accounts.

The implementation uses:
- A time-based trial that allows full feature evaluation.
- A one-time purchase Pro unlock via license key activation.

## Decision

1. **Trial model**
   - Provide a **7-day full-feature trial**, starting at onboarding completion (not first launch — user doesn't lose trial days to permission setup).
   - After the trial ends (and without a valid Pro license), dictation and transcription are **blocked**.

2. **Pro unlock**
   - Pro is unlocked via **license key activation** (one-time purchase) via LemonSqueezy.
   - License validation is cached locally with an **unlimited grace period** — validate once on activation, never expire. One-time purchase = yours forever.

3. **No accounts**
   - No user accounts are required for trial or Pro.

## Consequences

### Positive

- Users can fully evaluate the product before paying.
- No accounts and no subscriptions.
- Clear gating boundary: transcribe features are either enabled (trial/unlocked) or disabled (locked).

### Negative

- Requires a licensing backend for activation/validation.
- Users without network access may be unable to activate Pro (trial still works until it expires).
