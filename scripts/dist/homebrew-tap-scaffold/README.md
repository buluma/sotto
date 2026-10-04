# `buluma/homebrew-tap` README reference

This is the sotto repo's reference copy of the live
**`buluma/homebrew-tap`** README. The actual tap lives at
<https://github.com/buluma/homebrew-tap>.

Keep this file in sync when the tap README changes. See `HOWTO.md` for the
CLI release flow and tap update checklist.

---

# buluma/homebrew-tap

Homebrew tap for [buluma](https://github.com/buluma) packages.

## Available formulae

### `sotto-cli`

Local Parakeet TDT speech-to-text + transcription tooling for Apple
Silicon. ~155&times; realtime on the Apple Neural Engine, ~2.5% WER,
GPL-3.0.

```bash
brew tap buluma/tap
brew install sotto-cli

sotto-cli --version
sotto-cli health --json
sotto-cli transcribe ~/Downloads/audio.mp3 --format json
```

**Requirements:** macOS 14.2+ (Sonoma) on Apple Silicon (M1, M2, M3, M4).

The first transcription with a local engine downloads the selected CoreML
model. Parakeet, Nemotron, and Cohere models are cached under
`~/Library/Application Support/FluidAudio/Models/`; optional Whisper models
use `~/Library/Application Support/Sotto/models/stt/whisper/`.
Subsequent transcription with that model is fully offline.

**Source:** <https://github.com/buluma/sotto>
**Compatibility policy (semver):** [`Sources/CLI/CHANGELOG.md`](https://github.com/buluma/sotto/blob/main/Sources/CLI/CHANGELOG.md)
**Agent integration docs:** [`integrations/README.md`](https://github.com/buluma/sotto/tree/main/integrations)
**For agent operators:** <https://github.com/buluma/sotto>

> Why a tap and not homebrew-core? `sotto-cli` ships as a signed,
> precompiled Apple-Silicon binary, and homebrew-core only accepts formulae
> that build from source (or produce cross-platform binaries). A tap is the
> correct permanent home for it.

## Mac app — now in the official Homebrew cask

The Sotto macOS app no longer ships from this tap. It graduated to the
official **[`homebrew/cask`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/m/sotto.rb)**
on 2026-06-06, so no tap is required:

```bash
brew install --cask sotto
```

Homebrew keeps the official cask up to date automatically (BrewTestBot
autobump). Existing app installs from this tap are redirected to the official
cask automatically via [`tap_migrations.json`](tap_migrations.json) on the
next `brew update`.

## License

The formulae in this tap are MIT-licensed. The packages they install have
their own licenses (`sotto-cli` is GPL-3.0 — see source).
