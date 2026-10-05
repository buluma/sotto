# ADR-002: Local-First Processing

## Personal Sotto amendment — 2026-10-04

This amendment supersedes the inherited Discover, telemetry and app-update network descriptions below for this personal fork. Discover is off by default and reads only bundled, original Rick-and-Morty-style banter. It ignores old feed caches, never refreshes over HTTP, and has no thoughts submission surface. Remote analytics/crash transport and Sparkle app updates are removed. Feedback submission and hosted sharing transports are also removed. Configured AI/media/model/helper integrations  remain separate. See [personal Discover](../../docs/discover.md) and [telemetry contract](../contracts/telemetry-v1.md).

## Decision context

The rationale and market inputs are inherited history. The network boundaries below describe this fork.

> Status: **Accepted** (Amended 2026-03-11)
> Date: 2026-02-08
> Amended: 2026-03-11 — Refined scope from "no cloud processing" to local processing with optional external AI/telemetry surfaces (ADR-011)

## Context

The competitor examples, ratings, prices, and model-quality comparisons below are historical decision inputs from February–March 2026, not a current market survey or a benchmark of today's providers.

Sotto is entering a market where the dominant player (WisprFlow) relies on cloud processing. WisprFlow sends audio to remote servers for transcription and AI refinement, which creates three problems users consistently report:

1. **Privacy**: Audio data leaves the device. Users dictating medical notes, legal documents, proprietary code, or personal journals have legitimate privacy concerns.
2. **Latency**: WisprFlow users report 20-30 second server delays during peak usage hours. Cloud dependency means performance varies with server load, network conditions, and geographic distance.
3. **Reliability**: WisprFlow's Trustpilot rating is 2.8/5, with many complaints about server outages and inconsistent behavior. Cloud dependency introduces a failure mode that local processing eliminates entirely.

Meanwhile, local-only alternatives (MacWhisper, VoiceInk, BetterDictation) have proven that on-device STT is viable and increasingly preferred by privacy-conscious users.

## Decision

**Local processing with a fully local path.** The core product — transcription and dictation — runs on-device. Audio never leaves the device.

LLM-powered features (summaries, chat/Meeting Ask, AI Formatter, and Transforms) use external providers configured by the user. This is opt-in, explicit, and text-only — audio is never sent.

### What is always local (non-negotiable)

- **STT**: Parakeet runs locally via FluidAudio CoreML on ANE (v3 default, v2 English-only TDT opt-in, Unified English opt-in), with optional local Nemotron Beta, Cohere Transcribe, and WhisperKit engines for broader language and accuracy coverage (ADR-001, ADR-007, ADR-016, ADR-021)
- **Audio capture**: All microphone and file audio stays on-device
- **Text processing**: Deterministic pipeline runs locally (ADR-004)
- **Database**: All dictations, transcriptions, history stored locally (SQLite/GRDB)
- **Derived retrieval**: Segment search, transcript context reads, and existing knowledge-card reads are local. Generating cards is a separate LLM operation.

### What uses external providers (opt-in, user-configured)

- **LLM features**: Summaries, transcript/meeting chat, AI Formatter, Transforms, automatic titles, and knowledge-card generation (ADR-011)
  - Text context (transcripts, notes, selected text, or conversation as needed), never captured audio, is sent to the user's chosen provider
  - User configures their own API key, Ollama runtime, or Local CLI tool
  - No default provider — user must explicitly opt in
  - Features work without any provider configured (they're just unavailable)

### Other network surfaces

- **Media imports**: User-requested public media downloads through yt-dlp and Apple Podcasts directory/RSS/enclosure requests.
- **Model/helper setup**: Required model downloads, explicitly requested local model preparation, and helper installation/update paths.
- **Removed services**: Remote telemetry/crash uploads, feedback/thoughts submission, hosted sharing, and Sparkle app updates have no active transport in this fork. Debug sharing arguments cannot enable publication.
- **Discover**: Bundled-only cards, off by default; no HTTP refresh or legacy feed-cache loading.
- **Licensing**: Server validation and HTTP transport are removed. The compatibility service stays unlocked and never reads, writes, or clears stored credentials; see [the local entitlement contract](../contracts/licensing-local-only.md).

## Rationale

### Audio privacy is the brand

"Your voice never leaves your Mac" remains the core promise. This is unchanged. Captured audio is always processed on-device; the selected speech engine and compute policy determine whether inference uses the ANE, GPU, or CPU. What changed is recognizing that *transcript text* has a different privacy profile than *audio recordings*, and users should choose their own tradeoff.

### The quality gap is real

A local 8B model produces mediocre summaries. Cloud models (Claude, GPT-4) produce excellent ones. We tried local-only LLM (Qwen3-8B, ADR-008) and removed it because the quality wasn't worth the complexity. The "bring your own provider" approach delivers better quality with less code and zero resource impact.

### Privacy is a spectrum, not binary

| Configuration | Audio leaves device? | Text leaves device? | Quality |
|--------------|---------------------|---------------------|---------|
| No provider (default) | No | No | No LLM features |
| Ollama | No | No with a localhost server; remote endpoints send text off-device | Depends on configured model |
| Local CLI | No | Depends on the CLI tool | Varies by tool/provider |
| Apple Intelligence provider | No | No; Sotto uses the on-device Foundation Models API only | Depends on the system model |
| Cloud API key | No | Yes, for configured AI workflows | Depends on configured model |

Users make an informed choice. The UI makes the tradeoff explicit. Apple's broader Intelligence platform may use Private Cloud Compute, but Sotto's Apple Intelligence provider uses the on-device Foundation Models API with no cloud fallback.

Core capture, local-file transcription, and local retrieval remain usable offline after model setup. Local providers can keep generated text on-device. Remaining network paths are documented in the [network inventory](../../docs/network-boundaries.md); a local speech engine does not sandbox configured provider or download I/O.

### Official paid distribution still works

Cloud LLM costs are paid directly by the user to their provider (Anthropic, OpenAI, etc.). Sotto has zero server costs for core speech and zero marginal STT cost per user. The original one-time purchase model (ADR-003) was superseded by the current free/GPL release, but GPL-compatible paid official distribution, support, hosted services, or team features remain possible.

### Market validation

- Cursor ($20/mo) — bring your own API key for AI features
- Raycast — optional AI features with user's API key
- Char (fastrepl/char) — meeting transcription with cloud + local-provider support
- Apple Intelligence platform — on-device processing and, in other Apple surfaces, Private Cloud Compute; Sotto uses only its on-device model

## Consequences

### Positive

- Audio never leaves the device — core privacy promise intact
- Transcription works fully offline — no degradation
- LLM features use best-available models (Claude, GPT-4) without bundling a runtime
- Local-only users can use Ollama or LM Studio, and the eligible on-device Apple Intelligence provider for dictation cleanup
- Zero resource impact from LLM in the default configuration (no GPU memory, no automatic model downloads; the developer-gated Local MLX path in ADR-011 is explicit opt-in)
- Business model remains flexible: current public builds are free/GPL, while official paid distribution/support can be added without changing the local-first architecture
- App Store compatible

### Negative

- **Messaging complexity**: Local speech is narrower than a no-network app. Configured providers, media/model/helper downloads must be described independently.
- **Cloud providers require internet**: Summaries, chat/Meeting Ask, AI Formatter, and Transforms can run offline only when configured with an available local provider (eligible on-device Apple Intelligence covers dictation cleanup only). Transcription still works offline.
- **Transcript text exposure**: When using cloud providers or cloud-backed CLI tools, transcript text is sent to third-party services. Must be clear in UI. Users with sensitive content should choose a local provider or skip LLM features.
- **No cloud backup or sync**: User data stays on-device. If the Mac is lost, dictation history is lost. This is intentional.
- **No collaborative corpus**: ADR-029 permits a separately encrypted, read-only text snapshot. Real-time collaboration, team vocabularies, comments, and cross-device Library sync remain out of scope.

## References

- ADR-011: LLM via cloud API keys + optional local providers
- ADR-029: Explicit encrypted share snapshots
- ADR-008: Previous local LLM approach (HISTORICAL — removed 2026-02-23)
- WisprFlow Trustpilot reviews: 2.8/5 average, common complaints about delays and reliability
- Reddit r/macapps sentiment: strong preference for local processing
- Apple Intelligence platform strategy: on-device processing plus optional Private Cloud Compute in other Apple surfaces; this app's provider uses only on-device Foundation Models
