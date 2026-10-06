# Apple Speech locale inventory spike

This developer-only probe checks `SpeechTranscriber` availability and reports supported and installed locale identifiers on macOS 26 or later. It does not install speech assets or start recognition.

Compile and run it explicitly:

```sh
swiftc -parse-as-library -swift-version 6 -framework Speech \
  benchmarks/asr/apple-speech-spike/LocaleInventory.swift \
  -o /tmp/sotto-apple-speech-locale-inventory
/tmp/sotto-apple-speech-locale-inventory --developer-opt-in --inventory
```

The inventory includes `AssetInventory.status` for both `SpeechTranscriber` and `DictationTranscriber` for each locale returned by `installedLocales`. These are separate module-specific readiness checks; locale enumeration alone is not an asset-readiness result.

To run a file recognition attempt, only after the requested module reports `.installed`, use:

```sh
/tmp/sotto-apple-speech-locale-inventory --developer-opt-in \
  --transcribe-file en_US /path/to/audio-file
```

The probe rejects invocations that omit the explicit opt-in flag. It never calls the asset installation API. Keep this tool outside normal engine selection and do not use a successful connected run alone to claim offline recognition or quality qualification.

## Development Mac observation — 2026-10-06

On the development Mac running macOS 27.2, `SpeechTranscriber.isAvailable` returned `true`; 45 supported locales and 16 `installedLocales` entries were reported. For all 16 entries, both `SpeechTranscriber` and `DictationTranscriber` returned `AssetInventory.Status.supported`, which Apple defines as compatible but requiring an asset download. A local `say`-generated English fixture was rejected before recognition because the `en_US` `SpeechTranscriber` assets were not installed. No asset installation or download was requested.

This is a single-machine inventory. The existing `installedLocales` list does not establish that either module's assets are ready on this device; use the module-specific status. Offline recognition could not be evaluated without installed module assets, and matched-corpus quality/performance remain unqualified. To test offline behavior later, first authorize/install a module asset, then repeat recognition with network access disabled or otherwise isolated for the recognition process and its service.
