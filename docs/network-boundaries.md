# Personal Sotto network boundaries

This inventory describes the personal fork’s source behavior, not a packet-capture certification. Core microphone/system capture, installed-model speech recognition, transcript storage, corrections, playback, local search, and exports stay on-device. Offline operation requires the selected models and helpers to be installed already. Optional integrations are not a global network sandbox.

| Surface | Classification | Current boundary |
|---|---|---|
| Speech and diarization model assets | Required for an uninstalled selected model | FluidAudio/WhisperKit and model stores download assets from their original sources. Recognition itself remains local. Model preparation/repair can request missing assets. |
| Media imports and playback | User-triggered | URL imports use yt-dlp, podcast directory/RSS/enclosure requests, and media conversion/download paths. Remote thumbnails may load when displaying imported media. Local file imports do not require a media upload. |
| Helper setup and repair | Required when a needed helper is missing | FFmpeg, yt-dlp, and JavaScript helper/runtime packaging or repair can download binaries/packages. Build-time downloads are separate from capture. |
| AI providers | Optional, configured | Summaries, prompts, chat, titles, cards, dictation formatting, and Transforms send text context to the selected provider. Cloud endpoints and cloud-backed CLI tools may send text off-device. A local server is local only when its endpoint/runtime is local. Sotto does not send captured audio to an LLM. |
| Apple Intelligence | Optional, on-device | The Foundation Models adapter uses the system on-device model with no cloud fallback. Availability depends on the device/system setup. |
| In-process local AI | Development-only | Default-off feature and opt-in MLX build; model installation downloads assets. Local inference and download consent are separate boundaries. |
| Ask and Voice Control | Development-only, default-off | Debug opt-ins expose experimental workflows. Ask uses configured providers; Voice Control has its own consent-gated external decision client. These flags do not establish production qualification. |
| Retained licensing | Conditional legacy I/O | App setup calls `refreshValidationIfNeeded()`; CLI transcription does so with `--enforce-entitlements`. Stored key/instance state with stale validation can contact LemonSqueezy. No stored activation means no refresh request. Validation does not lock this fork. |
| Calendar | Optional, local API | Sotto reads EventKit data. Account/calendar synchronization is managed by macOS outside Sotto’s local repository boundary. |
| External links | User-triggered | Opening a link delegates to the system browser; the destination has its own network behavior. |
| Telemetry and crash uploads | Removed | GUI/CLI configure `NoOpTelemetryService`. No uploader, endpoint, timer, or retry queue remains. Preferences and `SOTTO_TELEMETRY=1` cannot enable uploads. Local diagnostic logs/artifacts remain. |
| Feedback and Discover thoughts | Removed | No submission UI/CLI or uploader remains. Diagnostic export is an explicit local action. |
| Hosted sharing | Removed | Unavailable in every build, including debug opt-ins. Default transport rejects requests; local sharing records, formats, and migrations remain for data integrity. |
| Discover feed | Removed network surface | Off by default; bundled cards only. Old remote caches are ignored; no HTTP refresh occurs. |
| App auto-updates | Removed | No Sparkle app wiring or feed. Update source manually, review changes, and rebuild locally. Model/helper preparation is a separate surface. |
| Packaging and release tooling | Development-only | Builds may fetch dependencies/assets; optional notarization contacts Apple when invoked. Retained release workflows are not authorization to publish, push, or upload this personal fork. |

Source anchors: `Sources/SottoCore/AppFeatures.swift`, `Sources/SottoCore/Services/Telemetry/TelemetryService.swift`, `Sources/CLI/Commands/CLITelemetry.swift`, `Sources/SottoCore/Services/Discover/DiscoverService.swift`, `Sources/SottoCore/Services/Sharing/ShareRemoteClient.swift`, `Sources/SottoCore/Licensing/README.md`, `Sources/Sotto/App/AppEnvironmentConfigurer.swift`, and the provider/model/media services under `Sources/SottoCore/`.

See the [local diagnostics contract](../spec/contracts/telemetry-v1.md), [Discover guide](discover.md), [CLI integration guide](../integrations/README.md), and [local-only decision](../spec/adr/002-local-only.md). Original third-party download sources and license notices are not Sotto-hosted services and must not be renamed as if they were.
