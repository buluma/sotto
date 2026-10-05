# Sotto: Vision & Philosophy

> Status: **ACTIVE** - Authoritative, current
> Fast, private, local-first voice app for Mac. Fully local speech with separately documented network surfaces, free and open-source (GPL-3.0).
> Fork scope: personal local use, GPLv3, no public distribution or automatic app updates. Upstream pricing/release history does not establish a Sotto release. Inert licensing compatibility and preserved credentials are documented in [network boundaries](../docs/network-boundaries.md).

---

## The North Star

**Fast, private, local-first voice for Mac. Fully local speech when you want it. No required cloud subscription for core speech.**

That is the day-one promise. The destination it builds toward ([ADR-027](adr/027-product-north-star.md)): **every word you speak or hear on your Mac becomes private, permanent, and useful — on your machine, owned by you, readable by you and your agents.** Sotto is the private speech memory of your Mac.

```
+-----------------------------------------------------------------------+
|                                                                       |
|   CLOUD SPEECH SERVICE                                                |
|   --------------------                                                |
|   Voice -> Provider -> Text -> account and service dependency         |
|                                                                       |
|   LOCAL SINGLE-MODE TOOL                                              |
|   ----------------------                                              |
|   Voice/file -> Local model -> Text -> narrow workflow                |
|                                                                       |
|   MacPARAKEET                                                         |
|   -----------                                                         |
|   Voice -> Text. Done. Local-first and GPL open-source.               |
|                                                                       |
+-----------------------------------------------------------------------+
```

Three capture modes plus one optional selected-text AI utility. That is the product:

1. **Dictate anywhere** -- Double-tap Fn for hands-free dictation, or hold Fn for push-to-talk. Text appears where your cursor is.
2. **Drop a file** -- Drag audio/video in. Get a transcript out.
3. **Record a meeting** -- Capture system audio, mic audio, or both, and get a transcript when you stop.
4. **Transform selected text** -- Press a bound Transform hotkey to rewrite selected text through your configured LLM provider.

Everything else exists to make those capture modes and the selected-text rewrite surface faster, smarter, and more useful.

### Where This Is Going

The modes converge ([ADR-027](adr/027-product-north-star.md)): dictation captures what you say, meetings capture what you discuss, files capture what you consume — and all of it lands in one local, searchable library that compounds in value the longer you use the app.

- **The Library becomes the center of gravity** — unified search across all three modes, question-answering over your own corpus, and export. Scope guard: search + QA + export, not a PKM.
- **Agents are first-class consumers** — scriptable corpus operations belong in `sotto-cli`'s versioned contract, not a mirror of every GUI affordance. Current retrieval capabilities and limits live in the [integration guide](../integrations/README.md).
- **Session-based, by design** — every capture is explicitly started by you. Ambient/always-on capture is deliberately parked ([ADR-027](adr/027-product-north-star.md) §4); cloud STT remains permanently out ([ADR-002](adr/002-local-only.md)).

Every feature must capture speech better, make the corpus more useful, or hand it safely to you and your agents — otherwise it does not ship.

---

## Why Sotto Exists

**The problem:** Mac users who want voice-to-text face a bad tradeoff:

| Option | Speech boundary | Product breadth | Ownership |
|--------|-----------------|-----------------|-----------|
| **Cloud speech services** | Audio leaves the Mac | Often focused on dictation or meetings | Provider account and service dependency |
| **Local transcription tools** | Speech can stay local | Often focused on files or one capture mode | Local files, product-specific automation |
| **Built-in OS dictation** | OS-managed | Dictation only | No shared transcript library or file/meeting workflow |
| **Sotto** | **No cloud STT; can be fully local** | **Three capture modes + Transforms** | **Local library, exports, and versioned CLI** |

Sotto is deliberately optimized for **speed + privacy + simplicity + user ownership**. Competitor capabilities and prices change; this spec defines Sotto's product commitments rather than serving as a live market-comparison table.

**Sotto's answer:** Built from the ground up around Parakeet TDT for speed, with multilingual v3 as the standard-path default, English-only v2 as an opt-in TDT build, and Parakeet Unified as an opt-in English build with punctuation, capitalization, live preview, and word-timestamped output, plus local Nemotron Beta, Cohere Transcribe, and WhisperKit engines for broader language coverage and accuracy-focused batch work. Locale-aware first-run setup selects WhisperKit for Korean/Japanese/Chinese/Cantonese when no preferred English language is present. Fully local speech by default, with optional networked features. Three capture modes, plus Transforms for selected text. Simple and GPL open-source. Done.

---

## Core Philosophy

### 1. Speed Is the Feature

On the repository's Apple M4 Pro reference benchmark, the three Parakeet builds sustain roughly 81–93x realtime with 115–131 MB peak RSS, depending on the build. English-only v2 provides a no-auto-detect TDT path, while Parakeet Unified provides English punctuation/capitalization, live preview, and word timestamps. These measurements are hardware- and corpus-specific; [`benchmarks/asr/`](../benchmarks/asr/) and the README carry the current tables.

Speed changes behavior. When a short dictation returns quickly and predictably, voice becomes a practical input method for emails, messages, code comments, documents, and notes.

### 2. Privacy Is the Brand

Fully local speech is a core product property. Core workflows can run offline after model setup; this is not a guarantee that a connected app makes no network requests.

- Local STT. No cloud speech processing, no accounts, no required backend for core speech.
- Audio never leaves your Mac for dictation or transcription.
- No required product account. Remote telemetry and crash-event transport are removed; diagnostics remain local.
- Core capture and local-file speech workflows work in airplane-mode or air-gapped environments after the required models are installed. Media/model/helper downloads and configured AI providers have separate network boundaries.
- Discover is off by default and reads bundled offline cards only. No feed refresh, thoughts submission, feedback uploader, or hosted sharing transport remains.

This is privacy by architecture at the speech boundary: recognition has no server path. [ADR-002](adr/002-local-only.md) documents the current provider and media/model/helper I/O boundaries; disabling one is not a global network opt-out.

### 3. Simplicity Over Features

Sotto keeps the top-level product centered on three capture modes plus Transforms.

- **Dictate** -- Double-tap Fn or hold Fn, speak, and text appears at cursor. Works in any app.
- **Transcribe** -- Drop a file, get text out. Audio, video, YouTube links.
- **Record** -- Capture a meeting (system audio, mic audio, or both), get a transcript.
- **Transform** -- Select text anywhere, press a bound hotkey, rewrite it through your configured LLM provider.

Every feature we add must pass the test: "Does this make dictation, transcription, or meeting recording better?" If not, it does not ship.

### 4. Modern, Not Minimalist

Simple does not mean basic. Sotto includes modern capabilities that cloud competitors pioneered, but runs them locally:

- **Clean Pipeline** -- Deterministic text processing: filler removal, custom word replacement, snippet expansion, whitespace normalization. Professional output with zero latency.
- **Custom Words** -- Teach it your vocabulary. Technical terms, proper nouns, acronyms. Anchors that improve recognition accuracy.
- **Context Awareness** -- (Future) Reads the surrounding text to produce better transcriptions. Knows "React" in a code editor, "react" in a therapy note.

### 5. Personal GPLv3 Fork

Sotto is a personal local fork derived from MacParakeet. It has no paid feature limits, required subscription, public release channel, or hosted Sotto service. Development gates still hide unfinished capabilities; see the [flag inventory](README.md#release-channels-and-feature-flags). Original copyright and third-party notices remain intact.

Retained activation code is not a commercial roadmap. It performs no licensing network or stored-state I/O; see [network boundaries](../docs/network-boundaries.md). Preserve the local compatibility surface and stored credentials.

---

## What Sotto Is

| Attribute | Description |
|-----------|-------------|
| **Product type** | Native macOS app (menu bar + window) |
| **Core function** | Voice dictation, file transcription, and meeting recording |
| **Target users** | Developers, professionals, writers who want fast private voice input |
| **Key differentiators** | Parakeet speed + optional local Nemotron/Cohere/Whisper engines + free/open-source |
| **Fork scope** | Personal local use; GPLv3; no public distribution or hosted Sotto service |
| **Platform** | macOS 14.2+, Apple Silicon only |

---

## What Sotto Is Not

- **Not a full meeting intelligence app** -- Sotto records and transcribes meetings, has live notes, Ask, and prompt-based action summaries. Calendar auto-start is implemented and enabled (opt-in). Cross-mode search and QA over your own library are in scope ([ADR-027](adr/027-product-north-star.md)); entity extraction, CRM-style enrichment, and team intelligence are not.
- **Not a note-taking app** -- It puts text where your cursor is. Your note app is your note app.
- **Not a cloud service** -- No hosted transcription backend, no accounts, no sync product. Core speech stays local.
- **Not an enterprise product** -- Single-user, single-Mac. No admin console, no team management (initially).
- **Not a mobile app** -- macOS only. Apple Silicon required for the local speech stack.
- **Not a transcription editor** -- Drop a file, get text. We do not build a full editing environment around transcripts.

---

## The Sotto Experience

### Mode 1: Dictate Anywhere

```
+-----------------------------------------------------------------------+
|  Any app. Any text field. Any time.                                   |
|                                                                       |
|  1. Hold Fn for push-to-talk or double-tap Fn for hands-free          |
|  2. Speak naturally                                                   |
|  3. Release Fn, or tap Fn again                                       |
|  4. Clean text appears at cursor in <500ms                            |
|                                                                       |
|  +-----------------------------------------+                          |
|  |  [Fn held]  Recording...  0:03          |  <-- floating pill        |
|  +-----------------------------------------+                          |
|                                                                       |
|  Works in: Slack, VS Code, Mail, Pages,                               |
|  Terminal, browsers -- everywhere.                                    |
+-----------------------------------------------------------------------+
```

- System-wide. Works in every app that accepts text input.
- Floating pill overlay shows recording status. Unobtrusive.
- Clean pipeline processes output: capitalization, punctuation, number formatting.
- Custom words ensure your vocabulary is transcribed correctly.

### Mode 2: Transcribe Files

```
+-----------------------------------------------------------------------+
|  +---------------------------+                                        |
|  |                           |                                        |
|  |   Drop audio or video     |     Supported:                        |
|  |   files here              |     .mp3 .wav .m4a .mp4 .mov          |
|  |                           |     .webm .ogg .flac .aac             |
|  |   [Browse Files]          |     YouTube URLs                       |
|  |                           |                                        |
|  +---------------------------+                                        |
|                                                                       |
|  Recent Transcriptions:                                               |
|  +-----------------------------------------------------------+       |
|  | meeting-recording.m4a      | 47:23  | 12s  | Completed    |       |
|  | podcast-ep-42.mp3          | 1:12:00| 18s  | Completed    |       |
|  | interview-notes.wav        | 22:15  | 6s   | Completed    |       |
|  +-----------------------------------------------------------+       |
|                                                                       |
|  Export: [Copy] [TXT] [SRT] [VTT] [Markdown]                         |
+-----------------------------------------------------------------------+
```

- Drag and drop. Or paste a YouTube URL.
- Progress indicator with ETA based on file duration.
- Multiple export formats: plain text, SRT subtitles, VTT, Markdown.
- Transcription history with search.

### Mode 3: Record a Meeting

```
+-----------------------------------------------------------------------+
|  Capture system audio, mic audio, or both. Transcribe locally.        |
|                                                                       |
|  1. Click "Record Meeting" (or press meeting hotkey)                  |
|  2. Grant the permissions required by the selected source mode         |
|  3. Meeting pill appears — recording the selected audio source(s)      |
|  4. Click Stop when done                                              |
|  5. Local STT transcribes source audio (Parakeet by default)          |
|  6. Result saved to library with full export/prompt support            |
|                                                                       |
|  Runs concurrently with dictation (ADR-015).                          |
|  Dictate a Slack message while your meeting is being recorded.        |
+-----------------------------------------------------------------------+
```

- Source-mode capture: system audio (ScreenCaptureKit), mic (AVAudioEngine), or both
- Floating recording pill with elapsed timer and stop button
- Results stored as `Transcription` with `sourceType = .meeting` — gets export, prompts, summaries, chat for free
- Requires Screen & System Audio Recording permission only for modes that capture system audio (macOS 14.2+)

> **Historical note:** This slot was originally "Command Mode (Pro)" which was removed in 2026-02. Meeting recording replaced it as Mode 3 in v0.6.

### Optional Utility: Transform Selected Text

```
+-----------------------------------------------------------------------+
|  Rewrite selected text anywhere without leaving the current app.       |
|                                                                       |
|  1. Select text in Slack, Mail, Linear, a browser, or an editor         |
|  2. Press a bound Transform hotkey (Control-Option-1/2/3)              |
|  3. Sotto captures the selection and runs the saved prompt        |
|  4. The result replaces the selection in place                         |
|                                                                       |
|  Uses the user's configured LLM provider. No selected text is sent      |
|  unless the user explicitly triggers a Transform.                      |
+-----------------------------------------------------------------------+
```

- Built-ins: Polish, Distill, Decide.
- Uses the same BYO-provider LLM architecture as summaries, chat, and the AI formatter.
- Separate from STT: it operates on selected text, not audio.

---

## Target Users

### Primary: Developers and Power Users

People who type quickly but prefer voice for long messages, thinking out loud, and dictating documentation. They care about low latency, clear privacy boundaries, automation, and avoiding a required subscription.

**What they want:** Fast dictation that works in VS Code, Terminal, Slack. No cloud, no subscription, no bloat.

### Secondary: Privacy-Conscious Professionals

People who handle sensitive notes, interviews, research, or internal material and want speech recognition to stay on their Mac. Sotto does not itself certify a user's regulatory compliance; users must evaluate their complete workflow, device controls, local diagnostics, configured AI providers, and remaining network boundaries.

**What they want:** Understandable data boundaries, no required product account, local core speech, and local diagnostics and the ability to avoid remote AI providers.

### Tertiary: Subscription-Fatigued Users

People who want a capable voice app without another recurring subscription, account, or feature-gated trial.

**What they want:** A good product without recurring charges. Free and open-source.

### Quaternary: Writers and Content Creators

Writers who think better out loud. Podcasters who need episode transcripts. Content creators making captions and subtitles. Students transcribing lectures. Anyone who produces text and prefers speaking to typing.

**What they want:** Fast file transcription with good export formats. Clean output that needs minimal editing. Reliable custom vocabulary for domain-specific terms.

---

## Product Position

Sotto does not depend on a time-sensitive competitor matrix for its identity. Published comparisons must be reverified when used; prices, engine choices, and feature sets are not stable facts.

| Product commitment | Sotto's position |
|--------------------|------------------------|
| Speech privacy | No cloud STT; supported speech engines run on the Mac |
| Scope | System-wide dictation, file/media transcription, and meeting recording in one app |
| Ownership | Local library, local artifacts, export, and a versioned CLI contract |
| Processing | Deterministic cleanup by default; optional provider-backed AI |
| Distribution | Current public build is free and GPL-3.0 |
| Platform fit | Native Swift app for Apple Silicon Macs |

---

## Competitive Advantages

### 1. Parakeet-First Architecture

We are not a Whisper app that added Parakeet. We built the entire product around Parakeet TDT 0.6B-v3 from day one, later exposed v2 and Unified as English-only Parakeet options, then added WhisperKit, Nemotron, and Cohere explicitly as local opt-in engines for broader coverage, experimentation, and accuracy-focused batch work.

- **Fast default path** -- the current M4 Pro benchmark measures roughly 81–93x steady realtime across Parakeet v3, v2, and Unified.
- **Measured engine tradeoffs** -- the shared benchmark reports accuracy, throughput, memory, and language coverage instead of relying on one headline number.
- **Word-level timestamps** -- enables synced subtitles, precise seeking, and speaker alignment where the selected engine supplies timings.
- **Vocabulary support** -- deterministic replacements ship today; recognition-time custom-vocabulary boosting is separately controlled and tested.

Sotto optimizes the default pipeline for Parakeet while routing optional Nemotron, Cohere, and Whisper through the same scheduler/runtime control plane.

### 2. Local-First, Zero-Compromise Speech

This is not "cloud by default with a local mode." Core speech recognition runs entirely on-device. There is no cloud STT path, no account system, and no requirement to send audio anywhere.

Network surfaces remain separate from speech inference: configured AI providers may receive text; model/media/helper paths download assets. Remote telemetry, feedback, sharing, Discover feed requests, and automatic app updates are removed. See [network boundaries](../docs/network-boundaries.md).

### 3. Free and Open-Source

The current free and open-source build removes account, trial, and subscription friction. Future monetization should sell official convenience, support, hosted services, or team workflows without undermining local-first GPL distribution.

### 4. Focused Simplicity

Three capture modes plus Transforms. Not twenty. Not fifty.

The product surface area is intentionally small. This means fewer bugs, faster iteration, easier onboarding, and a UI that does not require a tutorial. If a user cannot figure out Sotto in 30 seconds, we have failed.

---

## Licensing

Sotto is a personal local fork derived from [MacParakeet](https://github.com/moona3k/macparakeet), under the **GPL-3.0** license. Original copyright and third-party notices are retained. This fork has no public distribution channel.

> Historical note: MacParakeet’s earlier pricing decisions are retained in ADR-003. They are not a commercial plan for this personal fork.

---

## Relationship to Oatmeal

The comparison below records the original separate-product positioning. [ADR-027](adr/027-product-north-star.md) now owns the boundary: Library search and corpus Q&A belong in Sotto's direction, while deeper entity/graph/team work stays outside its scope. Whether Oatmeal continues as a distinct product is open; the older comparison is not a reason to reject Sotto Library work.

```
+-----------------------------------------------------------------------+
|                       Shared Technology                                |
|  +---------------------------------------------------------------+    |
|  |  FluidAudio CoreML (STT on Neural Engine)                      |    |
|  |  Text processing pipeline (raw/clean modes)                    |    |
|  +---------------------------------------------------------------+    |
+-----------------------+-----------------------------------------------+
|    Sotto        |              Oatmeal                          |
|    (Voice App)        |              (Meeting Memory)                  |
|                       |                                               |
|  - Dictate anywhere   |  - Calendar integration                       |
|  - Transcribe files   |  - Entity extraction                          |
|  - Record meetings    |  - Cross-meeting memory                       |
|  - Custom words       |  - Action items                               |
|  - YouTube import     |  - Knowledge graph                            |
|  - Export formats     |  - Pre-meeting briefs                         |
|  Simple, focused      |  Complex, powerful                            |
|  Personal GPLv3 fork |  TBD                                  |
+-----------------------+-----------------------------------------------+
```

### Key Distinctions

| Dimension | Sotto | Oatmeal |
|-----------|-------------|---------|
| **Purpose** | Voice input, transcription, meeting recording | Meeting memory and knowledge |
| **Scope** | Text in, text out, meetings transcribed | Meetings, entities, relationships, patterns |
| **Complexity** | Three capture modes + Transforms | Full knowledge system |
| **User relationship** | Tool whose local library compounds over time ([ADR-027](adr/027-product-north-star.md)) | System (compounds over time) |
| **Codebase** | Independent | Independent |
| **Revenue** | Personal local use; no public distribution | TBD |

### Strategic Relationship

- **Standalone value**: Sotto is a complete product on its own. It does not require or reference Oatmeal.
- **Historical funnel idea**: the original split reserved meeting intelligence for Oatmeal. Sotto now includes Calendar integration and is building toward corpus search/Q&A; only the deeper knowledge-system boundary remains outside its stated scope.
- **Adoption timing**: Sotto builds community and mindshare while Oatmeal matures. Simpler product = faster to market.
- **Technology proving ground**: Parakeet integration and clean pipeline are battle-tested in Sotto before being used in Oatmeal.
- **Boundary note (2026-07)**: [ADR-027](adr/027-product-north-star.md) moves cross-mode search and corpus QA into Sotto; whether Oatmeal continues as a distinct product is an open question recorded there.

---

## Success Metrics

### Quality Metrics

| Metric | Target |
|--------|--------|
| Dictation latency | Measure end-of-capture to paste by engine/build; do not publish one hardware-independent number |
| Parakeet throughput | ≥80x steady realtime on the current M4 Pro reference harness |
| Word error rate | Publish per-engine/corpus results from `benchmarks/asr/`; no universal WER claim |
| App crash rate | < 0.1% of sessions |
| First-use success rate | > 95% (user dictates successfully on first try) |

### The Ultimate Test

A new user should be able to:

1. Build and launch Sotto locally
2. Open it
3. Hold Fn and speak a sentence
4. See clean text appear at their cursor
5. Think "this is better than anything I have tried"

On first use, the user should reach this outcome as soon as the required model download and permission setup complete. No product account is required.

---

## Inherited Upstream Product Roadmap

These version milestones describe upstream history. Feedback, Sparkle, and public distribution listed below are removed or unavailable in this personal fork.

### v0.1: MVP -- Core Engine

The foundation. Dictation works. File transcription works. It is fast.

- Parakeet STT integration (FluidAudio CoreML on Neural Engine)
- System-wide dictation (Fn trigger, configurable, floating overlay)
- File transcription (drag-and-drop, common audio/video formats)
- Basic UI (menu bar app, transcription window)
- Settings (audio input selection, output preferences)

### v0.2: Clean Pipeline

Clean pipeline makes dictation output polish-ready.

- Clean text pipeline (deterministic: filler removal, custom words, snippets)
- Custom words & snippets management UI
- In-app feedback

### v0.3: YouTube & Export

YouTube transcription and full export pipeline.

- YouTube URL transcription (yt-dlp + local STT)
- Export formats (.txt, .srt, .vtt, .docx, .pdf, .json)

### v0.4: Polish + Launch

Ship-quality polish. Direct distribution via notarized DMG.

- Onboarding flow (permissions, first dictation)
- Notarized DMG distribution (macparakeet.com/R2 + Sparkle)
- Sparkle auto-updates
- Marketing site (macparakeet.com)
- Accessibility (VoiceOver, keyboard navigation)
- UI Localization (English UI first, structure for future languages; STT already supports 25 European languages)

### v0.6: Meeting Recording + Multilingual STT

- System audio + mic capture with fragmented source files and crash recovery
- Live meeting pill + Notes / Transcript / Ask panel
- Source-aware final transcription with prompt results and chat in the library
- Parakeet model selection: v3 multilingual default, v2 English-only TDT opt-in, and Unified English opt-in
- Optional local WhisperKit and Cohere Transcribe engines for languages or accuracy needs outside the default Parakeet coverage
- Settings speech-engine picker, Parakeet model picker, Nemotron controls, Cohere language picker, and Whisper language picker
- CLI `transcribe --engine parakeet|nemotron|whisper|cohere --language --parakeet-model`
- Meeting recordings pin engine/language for live preview, recovery, and finalization
- Calendar auto-start is implemented and enabled (`AppFeatures.calendarEnabled = true`); defaults to opt-in mode `.off`. Calendar-driven auto-stop was removed (ADR-017 amendment); recordings stop manually

### v0.7: Post-v0.6 polish

- v0.7.3 added System Default microphone-routing repair, split live/final speech-engine routes, bounded meeting-capture lifecycle handling, meeting auto-save feedback, CLI 3.0, and post-v0.6 reliability polish.
- Meeting echo cancellation ships as a fail-soft derived cleaned-microphone artifact; activity-based auto-stop remains opt-in and activity-based meeting detection remains gated.
- Direction per [ADR-027](adr/027-product-north-star.md): continue Library convergence and safe agent access through the CLI. Developer-gated local MLX groundwork is not a normal-user v0.7 feature.

### v0.8: Library, meetings, and transcript workflow

- Stable v0.8.7 is the current user-facing DMG. The train adds meeting import and split, timed transcript corrections, live transcription during recording, independent capture-source startup, per-event calendar skip, start-meetings-muted, Microsoft 365/Exchange calendar setup, Library labels/layouts, Seed of Life covers, Clean English “um” stripping, optional preserved discarded dictations, DAPT export, skip-microphone onboarding for file-only users, AI Formatter off by default with separate dictation and transcript prompts, optional streaming-cursor insert, China-lab LLM providers, and CLI 4.4.0. 0.8.5 cleared a stuck Wrapping up tile label after stop (status only; recordings were already saved). 0.8.6 kept the Sonoma Parakeet encoder off ANE. 0.8.7 restores hold-to-talk when the microphone is already granted, admits Fn while Caps Lock is latched, and splits overlay insets so hold-to-talk stays 16pt while cancelled/Undo is 7pt.
- Voice profiles, encrypted share links, activity-based meeting detection, app-aware AI Formatter profiles, and in-process MLX remain gated.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Platform** | macOS 14.2+, Apple Silicon only | FluidAudio CoreML requires Apple Silicon. |
| **STT engine** | Parakeet TDT 0.6B-v3 on the standard path; locale-aware CJK/Korean onboarding can select WhisperKit; Parakeet v2 and Unified English opt-ins; selectable Nemotron Beta, WhisperKit, and Cohere Transcribe | Parakeet gives the latency target for supported languages; v2 avoids language auto-detect for English-only users; Unified offers a newer English punctuation/capitalization path with live preview and word timestamps; Nemotron is a fast local Beta path; WhisperKit keeps mature broader multilingual speech local; Cohere is a larger batch-only accuracy path. |
| **YouTube downloads** | Standalone yt-dlp | macOS binary, auto-updates via `--update`. No Python needed. |
| **UI framework** | SwiftUI | Native Mac experience. Menu bar + window. |
| **Structured records** | SQLite (GRDB) | Single local database for history, library, vocabulary, prompts/results and derived retrieval. Preferences use UserDefaults, credentials use Keychain, and retained audio/artifacts remain files. |
| **Cloud option** | No cloud STT; configured AI providers are optional | Core speech stays local. Remaining network paths are documented in [network boundaries](../docs/network-boundaries.md); remote telemetry and automatic updates are removed. |
| **Pricing** | Personal GPLv3 fork | No paid feature limits, required account, or public distribution channel. |

---

## Naming

**Sotto** -- Named after the Parakeet STT model that powers it. "Mac" prefix signals native macOS. The name is friendly, memorable, and directly communicates the technology inside.

The parakeet bird is known for mimicking speech -- a fitting metaphor for a voice transcription app.

---

## Killer Features (What Sets Us Apart)

| Feature | What It Does | Why It Matters |
|---------|--------------|----------------|
| **Parakeet Speed** | ~81–93x steady realtime across current builds on the M4 Pro reference benchmark | Fast local transcription with measured, hardware-specific evidence |
| **System-wide Dictation** | Fn to dictate in any app | Voice input everywhere, not just our app |
| **Meeting Recording** | Capture system audio, mic audio, or both; transcribe locally | Record any call or meeting without cloud services |
| **YouTube Transcription** | Paste a URL, get a transcript | File transcription for the YouTube era |
| **Local-First STT** | Speech stays on-device; optional networked AI | Strong privacy claim without pretending the app never uses the network |
| **Clean Pipeline** | Deterministic text cleanup | Professional output without LLM overhead |
| **Custom Words** | User-defined vocabulary anchors | Technical terms transcribed correctly every time |
| **GPLv3** | Personal fork with original legal notices retained | No required account or paid feature limits. |

---

*This document defines the "why" and the "what." See [02-features.md](./02-features.md) for detailed feature specs and [03-architecture.md](./03-architecture.md) for technical architecture.*
