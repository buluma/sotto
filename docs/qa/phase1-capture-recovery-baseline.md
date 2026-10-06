# Phase 1 capture and recovery baseline

Status: **Phase 1 baseline reporting and issue classification complete, with documented exceptions (2026-10-06).** The owner omitted the hardware and target-application matrix. Native integration and live-soak qualification remain unverified; this closeout does not claim an all-green full suite or release readiness. All eight engineering-plan baseline areas are covered below.

Started: 2026-10-06. Checkout: `docs/reconcile-personal-fork`, source baseline `db111b6`. Scope: begin baseline qualification with existing capture/recovery tests and native smoke preflight. The initial capture/recovery tests use ephemeral databases, synthetic audio, and disposable writer subprocesses; user recordings, preferences, and credentials are not recovery fixtures. The process journey uses real AVFoundation files and stubbed STT, certifying retained artifacts and recovery orchestration rather than recognition quality.

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
- [x] Complete meeting-flow smoke without readiness failures (all 37 coordinator tests passed after test synchronization repair)
- [ ] Complete recovery-service smoke with functioning native audio fixtures
- [x] Real writer/process crash-recovery regression in CI (`Meeting Process Recovery`, run `37382386237`)
- [ ] Repeat the writer/process journey successfully on this Mac
- [ ] Complete microphone route-recovery suite without native exceptions

## Native capture smoke

The canonical sequence is three dictations, one meeting, dictation during that meeting, Stop, and one further dictation. Verify retained meeting audio/transcript, history, and clean capture stop. Run through `scripts/dev/run_app.sh` with a disposable `SOTTO_DEBUG_APP_STATE_DIR`; do not use existing recordings for crash/discard checks. Preferences and Keychain remain shared, so leave credentials and provider configuration untouched.

Status: canonical normal-quit/process preflight passed (exit 0) using `scripts/dev/stop_app_processes.sh` with this checkout’s exact dev executable paths. The canonical dev launcher was attempted with `SOTTO_DEBUG_APP_STATE_DIR=/tmp/sotto-phase1-native-state` and failed before building: Xcode reported that the checkout does not contain a project, workspace, or package, despite the root `Package.swift`. Log: `/tmp/sotto-phase1-native-launch.log`. No dev app launched; the native capture sequence remains unverified. Real microphone/system-audio capture, permission dialogs, target-app insertion, hardware route changes, sleep/wake, playback/export, and long-duration recording remain unverified until exercised in the native app. Synthetic process recovery does not certify those checks.

## Deferred native qualification

- [ ] Native sequential/concurrent dictation and meeting smoke
- [ ] Push-to-talk and hands-free in the target application matrix
- [ ] Microphone-only, system-only, and combined capture with real sources
- [ ] Route loss/disconnect and sleep/wake using disposable recordings
- [ ] File formats, cancellation/retry, playback, and export
- [ ] 30-minute, 1-hour, 2-hour, and 4-hour soaks
- [ ] Accessibility and VoiceOver

Initial classification: native build/package discovery and standalone audio/codec failures blocked integration qualification; panel readiness needed separate triage. The follow-up below resolves the panel test synchronization issue and records the owner’s native-matrix omission. If native qualification is reinstated, restore package discovery and audio-component availability before retrying the affected checks and the disposable capture sequence. Fixture coverage does not certify a native journey.

## Observed baseline issues

- Build environment: SwiftPM’s nested sandbox startup initially failed; `--disable-sandbox` allowed compilation to proceed. User-level cache directories remain unavailable in this session.
- Compiler debt: current `STTRuntime.swift` emits an implicit strong/weak capture ownership warning, and `Observability.swift` uses a deprecated task-local `withValue` overload. These source paths are unchanged by this documentation/test pass.

- Native build environment: the canonical Xcode launcher could not recognize this package. Investigate local Xcode package discovery before native capture qualification; the smoke pass does not establish a root cause.

## Follow-up after PR #10 merge

PR #10 merged as `ff6628b502024d10988d5e05c654284625a266ed`. The canonical native launcher retry still failed package discovery; the selected developer directory is `/Applications/Xcode.app/Contents/Developer`. The standalone audio probe again passed PCM while failing AAC/ALAC and rejecting the AAC writer input. Git fetch remains restricted by `.git/FETCH_HEAD` write permissions in this session.

The isolated live-panel readiness test failed again (one test, two assertions, 24.316 seconds; `/tmp/sotto-phase1-live-panel-retry2.log`). Two independent AppKit/SwiftUI probes successfully created, hosted, presented, activated, and hid disposable panels: a text-only panel completed in 1.024 seconds, and a `TextEditor` panel with a constant binding completed in 1.429 seconds (`/tmp/sotto-phase1-panel-probe.log`, `/tmp/sotto-phase1-editor-probe.log`). Generic window presentation and a basic text editor therefore work in this session; the probes do not reproduce Sotto’s Notes focus task, animation, view-model wiring, or async recording-start scheduling. Next isolate those interactions before changing production behavior. No capture code changed and no native capture journey is newly qualified.

## Expanded baseline and owner scope decision

On 2026-10-06 the owner explicitly instructed “none, skip it” for the hardware and target-application qualification matrix. Those checks are omitted from this Phase 1 closeout, not marked as passing. Real capture, hardware route/sleep recovery, live soaks, insertion into the application matrix, and native accessibility remain unqualified. This is an automated baseline and known-issue inventory, not a release-readiness certification.

The first expanded run completed 634 tests with three failing cases. The isolated follow-up completed 483 tests with two failing cases (three assertions/errors). Across those two runs there are 1,035 distinct cases: 1,032 passed after the isolated rerun, and three native codec-dependent cases failed locally. The original four-suite capture smoke contributes another 72 passing cases. Logs: `/tmp/sotto-phase1-baseline-matrix.log` and `/tmp/sotto-phase1-baseline-isolated.log`. Subsequent commands set `SOTTO_DEBUG_APP_STATE_DIR` to a new temporary directory so managed media/log/model paths cannot resolve to the normal app’s state; preferences and Keychain are still shared and are not used as recovery fixtures.

| Baseline area | Evidence | Qualification limit |
|---|---|---|
| Dictation | 63 capture/cancellation tests; 197 hotkey/Fn/gesture/conflict tests; 16 recognition-vocabulary tests passed | Fixture routing and orchestration; physical keys, live STT, and target-app insertion omitted |
| Meeting recording | All 37 coordinator tests, 20 state-machine tests, 10 queue tests, and 9 finalization reconciliation tests passed; both real process-recovery journeys previously passed in CI | Local native writer/recovery/route tests remain blocked by audio-component availability |
| File transcription | 3 flow tests and 14 converter tests passed; 103 of 105 transcription-service cases passed | Two meeting cleaned-mic cases failed at the native AAC writer; recognition correctness is not measured by mocked STT |
| Library | All 82 Library view-model tests and 78 repository tests passed | Native Library journey and accessibility unqualified |
| Diarization | 29 diarization service, 21 Nemotron service, and 25 attribution resolver tests passed | Fixture/service contracts; no real-model diarization accuracy claim |
| Exports | 58 export service, 14 export CLI, and 14 export-option tests passed | Native playback/visual document QA unqualified |
| Summaries | 17 saved-audio auto-prompt, 17 result repository, and 92 result view-model tests passed | Mock AI generation and local result persistence/edit/retry; no provider quality claim |
| CLI | 82 transcribe, 28 history, 9 search, and 14 export tests passed; 38 of 39 meeting CLI tests passed | One meeting artifact fixture needs the unavailable native codec; real recognition/capture not exercised |

The panel readiness issue was a test-ordering race: `testStartRecordingCanPresentLivePanelWhenReady` timed UI state before awaiting the coordinator’s owned asynchronous startup. It now uses the existing `waitForStartCall` helper before the unchanged one-second UI-state assertion. The isolated test passed in 2.463 seconds and all 37 coordinator tests passed in the broader follow-up, despite the session’s HIServices warning. No production capture or presentation behavior changed. Log: `/tmp/sotto-phase1-live-panel-owned-start.log`.

## Classified issues and omissions

| Item | Classification | Disposition |
|---|---|---|
| Native package/workspace discovery | Environment blocker: root package and explicit `.swiftpm/xcode/package.xcworkspace` both rejected by Xcode in this session | Keep native launch unqualified; do not generate a substitute project or alter dependencies |
| Native audio components/codecs | Environment blocker reproduced without Sotto: PCM writes work; AAC/ALAC writes and AAC writer inputs fail; audio inventory reports zero devices | Keep local writer/recovery/cleaned-mic cases unqualified; retain independent CI crash-recovery evidence |
| Live-panel timeout | Test synchronization defect | Fixed by awaiting owned startup; coordinator suite green, timing limit unchanged |
| Library cleanup fixtures | Test invocation isolation defect: managed fixture paths resolved outside the sandbox | Resolved by temporary `SOTTO_DEBUG_APP_STATE_DIR`; all 82 cases pass |
| Raw `.aac` | Existing format limitation: not in `AudioFileConverter.supportedAudioExtensions` or the current feature spec | Record rejection as current behavior; adding support is future implementation work |
| Hardware and target applications | Owner-requested omission | Omit rather than fabricate native qualification |
| Live 30-minute/1-hour/2-hour/4-hour soaks, playback, VoiceOver | Native qualification blocked/omitted with unavailable capture/app access | Retain as unverified acceptance work; synthetic tests are not live soaks |
| Whole-suite baseline | No successful local aggregate result | Focused results are recorded individually; no full-suite pass claimed |

## Reproducible media-format qualification

`Phase1MediaConversionTests` is opt-in. It runs the real `AudioFileConverter` over generated one-second 440 Hz tone fixtures, verifies mono 16 kHz PCM output, duration, retained signal and source-file preservation, and records raw AAC rejection. MP4/MOV fixtures include a video stream. FFmpeg must already be installed; the fixture generator never downloads helpers or accesses user media.

```bash
SOTTO_PHASE1_MEDIA_FIXTURES="$(python3 scripts/testing/phase1-media-fixtures.py)" \
SOTTO_DEBUG_APP_STATE_DIR="$(mktemp -d /tmp/sotto-phase1-media-state.XXXXXX)" \
python3 scripts/ci/run-test-process.py --timeout 900 -- \
swift test --disable-sandbox --build-system native --filter Phase1MediaConversionTests
```

Result: passed (one integration test, 0.955 seconds). All five supported planned formats preserved the tone, duration, mono 16 kHz output, and input files; raw `.aac` was rejected as specified by current behavior. Log: `/tmp/sotto-phase1-media-conversion.log`. The same test passed again against fixtures produced by `scripts/testing/phase1-media-fixtures.py` (0.691 seconds; `/tmp/sotto-phase1-media-generator-check.log`). Python compilation and changed Swift test lint passed, and relative documentation links and whitespace checks passed.

## Phase 1 closeout checklist

- [x] Baseline report covers dictation, meeting recording, file transcription, Library, diarization, exports, summaries, and CLI
- [x] Known issues classified; test synchronization repaired and isolation rerun completed
- [x] Supported planned media conversions exercised with real FFmpeg and PCM reads
- [x] Hardware/application omissions and native/live-soak limitations recorded explicitly
- [x] No production capture, storage, codec, recognition, or network behavior changed

The expanded selected baseline contains 1,036 distinct cases after the media test: 1,033 passed and three failed locally at native codec-dependent boundaries. Combined with the original 72 passing capture cases, there are 1,105 passing distinct cases in this report. This is selected-suite evidence, not the whole test suite. Earlier native recovery/audio-run failures remain recorded above rather than erased by these totals. Remaining work is native qualification if the owner reinstates it, optional raw-AAC support, and the next product-plan phase; the baseline inventory/classification milestone is complete.
