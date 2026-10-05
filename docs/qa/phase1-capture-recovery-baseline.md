# Phase 1 capture and recovery baseline

Started: 2026-10-06. Checkout: `docs/reconcile-personal-fork`, source baseline `db111b6`. Scope: begin baseline qualification with existing capture/recovery tests and native smoke preflight. Tests use ephemeral databases, synthetic audio, and disposable writer subprocesses; user recordings, preferences, and credentials are not recovery fixtures. The process journey uses real AVFoundation files and stubbed STT, certifying retained artifacts and recovery orchestration rather than recognition quality.

## Automated smoke run

Command:

```bash
SOTTO_CRASH_RECOVERY_TESTS=1 swift test --disable-sandbox --build-system native --filter 'DictationFlowTests|CancelFlowTests|DictationFlowCoordinatorTests|MeetingRecordingFlowCoordinatorTests|MeetingRecordingRecoveryServiceTests|MeetingRecordingCrashRecoveryTests|MeetingFinalizationReconcilerTests|MicrophoneEnginePlatformConfigChangeRecoveryTests'
```

Result: the cold native build completed and tests executed. Four suites passed all 72 tests: `CancelFlowTests` (19), `DictationFlowCoordinatorTests` (41), `DictationFlowTests` (3), and `MeetingFinalizationReconcilerTests` (9). The broader smoke selection failed and eventually aborted with signal 6 in a native CoreAudio exception; there is no passing aggregate result.

The first attempt failed before test execution because nested `sandbox-exec` could not apply its sandbox. `--disable-sandbox` allowed SwiftPM compilation; session restrictions still applied. Main log: `/tmp/sotto-phase1-smoke-retry.log`. No additional local full-suite run was performed; the previous full-suite attempt also has no final result. Independent PR #9 checks on `db111b6` are green: general tests, audio tests, Release and Bundle, and the separate `swift-test` check all passed. Build Cache Invalidation was skipped. The general job’s opt-in `Meeting Process Recovery` step also passed both real writer/process journeys (run `37382386237`). This independent result supports the branch baseline but does not erase this session’s native integration failures.

| Area | Evidence exercised | Result |
|---|---|---|
| Dictation/cancellation | Start/stop, save/search, STT failure, cancellation, insertion/clipboard failure handling | 63 tests passed across three suites; fixture evidence, not real microphone/app insertion |
| Finalization reconciliation | Ownership, stale processing rows, active finalization leases | 9 tests passed |
| Meeting flow | Stop/finalization ownership, source failure, retained-audio retry, panel readiness | 37 tests completed; one panel-readiness case failed with two assertions. That case failed again in isolation |
| Recovery logic | Metadata/audio preservation, orphan locks, retry | 49 tests completed; 44 failed while native audio fixtures were being created (`com.apple.coreaudio.avfaudio`, code `1718449215`). Recovery behavior dependent on those fixtures remains unverified |
| Process crash | Disposable synthetic writer, playable media, fresh-process recovery/idempotence | Both parent journeys failed locally because `AVAssetWriter` could not add audio input. Both passed in CI’s opt-in `Meeting Process Recovery` step |
| Microphone recovery | Route/configuration recovery and cancellation | Partially executed, then the runner aborted at `testRunningConfigurationChangeOnBluetoothRouteNotifies`: `comp != nullptr` failed in `AVAudioEngine.inputNode`. No complete suite result |

A standalone AVFoundation probe, with no Sotto imports, narrowed the audio blocker: PCM/WAV writing passed, AAC and ALAC writing both failed with code `1718449215`, and `AVAssetWriter.canAdd(AAC)` returned false. This demonstrates a native audio/codec failure outside Sotto’s recovery implementation. It does not establish whether the cause is session restrictions, host configuration, or the platform runtime. Probe log: `/tmp/sotto-phase1-audio-probe.log`.

The isolated panel test remained in `starting` instead of `recording`, while HIServices XPC connection errors appeared. The failure is reproducible in this session; its root cause is unresolved. Log: `/tmp/sotto-phase1-live-panel-retry.log`. A subsequent isolated comparison, `testStartWithFloatingPillHiddenStillStartsRecordingFlow`, passed in 0.327 seconds with the same service spy and coordinator factory (`/tmp/sotto-phase1-hidden-panel.log`). This narrows the failure to the live-panel presentation path: the coordinator presents an AppKit/SwiftUI panel synchronously before scheduling the recording-start task. It does not establish which panel or session interaction delays readiness. Do not change capture semantics or inflate timing allowances merely to hide it.

- [x] Deterministic dictation/cancellation smoke (63 tests)
- [x] Finalization reconciliation smoke (9 tests)
- [ ] Complete meeting-flow smoke without readiness failures
- [ ] Complete recovery-service smoke with functioning native audio fixtures
- [x] Real writer/process crash-recovery regression in CI (`Meeting Process Recovery`, run `37382386237`)
- [ ] Repeat the writer/process journey successfully on this Mac
- [ ] Complete microphone route-recovery suite without native exceptions

## Native capture smoke

The canonical sequence is three dictations, one meeting, dictation during that meeting, Stop, and one further dictation. Verify retained meeting audio/transcript, history, and clean capture stop. Run through `scripts/dev/run_app.sh` with a disposable `SOTTO_DEBUG_APP_STATE_DIR`; do not use existing recordings for crash/discard checks. Preferences and Keychain remain shared, so leave credentials and provider configuration untouched.

Status: canonical normal-quit/process preflight passed (exit 0) using `scripts/dev/stop_app_processes.sh` with this checkout’s exact dev executable paths. The canonical dev launcher was attempted with `SOTTO_DEBUG_APP_STATE_DIR=/tmp/sotto-phase1-native-state` and failed before building: Xcode reported that the checkout does not contain a project, workspace, or package, despite the root `Package.swift`. Log: `/tmp/sotto-phase1-native-launch.log`. No dev app launched; the native capture sequence remains unverified. Real microphone/system-audio capture, permission dialogs, target-app insertion, hardware route changes, sleep/wake, playback/export, and long-duration recording remain unverified until exercised in the native app. Synthetic process recovery does not certify those checks.

## Remaining qualification

- [ ] Native sequential/concurrent dictation and meeting smoke
- [ ] Push-to-talk and hands-free in the target application matrix
- [ ] Microphone-only, system-only, and combined capture with real sources
- [ ] Route loss/disconnect and sleep/wake using disposable recordings
- [ ] File formats, cancellation/retry, playback, and export
- [ ] 30-minute, 1-hour, 2-hour, and 4-hour soaks
- [ ] Accessibility and VoiceOver

Current classification: native build/package discovery and standalone audio/codec failures block integration qualification; panel readiness requires separate triage because its cause is unresolved. The next step is to restore native package discovery and audio-component availability, repeat only the failed/aborted focused checks, then run the disposable native capture sequence. Do not mark a whole Phase 1 journey complete from fixture coverage alone.

## Observed baseline issues

- Build environment: SwiftPM’s nested sandbox startup initially failed; `--disable-sandbox` allowed compilation to proceed. User-level cache directories remain unavailable in this session.
- Compiler debt: current `STTRuntime.swift` emits an implicit strong/weak capture ownership warning, and `Observability.swift` uses a deprecated task-local `withValue` overload. These source paths are unchanged by this documentation/test pass.

- Native build environment: the canonical Xcode launcher could not recognize this package. Investigate local Xcode package discovery before native capture qualification; the smoke pass does not establish a root cause.
