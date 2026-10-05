# Personal Sotto feature-flag inventory

Source of truth: `Sources/SottoCore/AppFeatures.swift`. Defaults below are compile-time gates, not proof of workflow qualification or a public release. There is no public Sotto release channel. The fork maintainer owns every keep/remove decision; subsystem names below identify implementation responsibility, not an invented assignment to an upstream developer. No named delegate is recorded in this checkout.

| Flag | Default | Purpose / implementation owner | Current availability | Keep/remove decision | Personal-fork 1.0 relevance |
|---|---|---|---|---|---|
| `askWorkspaceEnabled` | `false` | Cross-recording evidence Q&A / Ask services | DEBUG opt-in `--enable-ask-workspace`; release builds ignore it | Keep gated pending qualification | Post-baseline experiment |
| `voiceControlEnabled` | `false` | Explicit command capture / Voice Control | DEBUG opt-in `--enable-voice-control`; separate cloud/OCR consent | Keep gated pending qualification | Outside core 1.0 |
| `shareLinksEnabled` | `false` | Hosted transcript snapshots / Sharing | Unavailable in every build; debug arguments cannot enable it | Keep disabled; preserve records/formats | Excluded from personal fork |
| `voiceProfilesEnabled` | `false` | Speaker identity / Diarization and voice profiles | DEBUG opt-in `--enable-voice-profiles`; consent remains separate | Keep gated pending held-out evaluation | Outside core 1.0 |
| `meetingRecordingEnabled` | `true` | Meeting entry points / Meeting capture | Available; permissions requested when needed | Keep | Core capture |
| `calendarEnabled` | `true` | Reminders and optional auto-start / Calendar | Available; per-user auto-start defaults off | Keep opt-in behavior | Supporting meeting workflow |
| `meetingAutoStopEnabled` | `true` | Activity-based auto-stop / Meeting lifecycle | Available; per-user preference defaults off | Keep opt-in behavior | Supporting capture; manual stop remains core |
| `meetingCaptureReliabilityEnabled` | `true` | Source liveness watchdog / Meeting capture | Default-on monitoring; retained event hooks have no uploader | Keep reliability kill switch | Core reliability |
| `meetingSourceHealthUIEnabled` | `false` | Routine health indicators / Recording presentation | Routine chips hidden; actionable faults bypass gate | Keep quiet default and actionable faults | Core error recovery |
| `meetingActivityDetectionEnabled` | `false` | Passive meeting detection / Activity collectors | Runtime collector/coordinator surface disabled | Keep gated | Outside core 1.0 |
| `transformsEnabled` | `true` | Selected-text rewriting / Transforms | Available; requires a configured AI route | Keep | Existing optional utility |
| `cohereEngineEnabled` | `true` | Local batch speech engine / STT runtime | Selectable; model download required; no live partials/word timings | Keep optional engine | Existing capture option |
| `meetingVadLiveChunkingEnabled` | `true` | Speech-boundary live chunks / Audio and STT | Available with cached VAD; fixed-chunk fallback | Keep fallback and gate | Core meeting reliability |
| `liveDictationStreamingEnabled` | `true` | Display-only partial transcript / Dictation and STT | Available per engine; final paste remains stop-time | Keep | Core dictation feedback |
| `aiFormatterProfilesEnabled` | `false` | App-aware formatting profiles / Text processing | Normal profile settings/routing disabled; persistence retained | Keep gated | Outside focused 1.0 |
| `inProcessLocalLLMEnabled` | `false` | In-process MLX / Local AI runtime | Explicit developer visibility override plus compiled runtime required | Keep gated | Qualification experiment |

## Additional gates and overrides

Ask, Voice Control, and Voice Profiles launch overrides are DEBUG-only. Sharing always returns unavailable, even with the old debug argument. Enabling an experimental surface does not bypass its consent or provider boundary.

Local MLX has three independent conditions: the default-off product flag, developer visibility (`SottoEnableInProcessLocalLLM` preference or `--enable-local-ai`), and an available runtime compiled with `SOTTO_ENABLE_MLX_LOCAL_LLM=1`. Its visibility override is not guarded by DEBUG in current source; runtime availability still controls actual availability. Do not describe all developer overrides as release-disabled.

`voiceControl.screenText.v1` is a separate per-user OCR consent preference, not the Voice Control feature gate. Calendar auto-start and meeting auto-stop are separately opt-in preferences despite their compile-time gates being on.

Telemetry preferences/environment variables are inert compatibility inputs, not feature gates. Discover visibility defaults off and controls bundled local content only. See [network boundaries](network-boundaries.md).

## Qualification policy

Retain enabled behavior and default-off experiments without changing literals during normalization. Any later availability change requires its governing ADR/contract, focused tests, and native/model qualification where applicable. Source inventory is not a substitute for baseline capture and recovery acceptance tests.
