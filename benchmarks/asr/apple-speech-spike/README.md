# Apple Speech locale inventory spike

This developer-only probe checks `SpeechTranscriber` availability and reports supported and installed locale identifiers on macOS 26 or later. It does not install speech assets or start recognition.

Compile and run it explicitly:

```sh
swiftc -parse-as-library -swift-version 6 -framework Speech \
  benchmarks/asr/apple-speech-spike/LocaleInventory.swift \
  -o /tmp/sotto-apple-speech-locale-inventory
/tmp/sotto-apple-speech-locale-inventory --developer-opt-in --inventory
```

The probe rejects invocations that omit either explicit flag. Keep this tool outside normal app engine selection and do not use its inventory alone to claim clean-machine, offline-recognition, or quality qualification.

## Development Mac observation — 2026-10-06

On the development Mac running macOS 27.2, `SpeechTranscriber.isAvailable` returned `true`; 45 supported locales and 16 installed locales were reported. Installed locales were `de_AT`, `de_CH`, `de_DE`, `en_AU`, `en_CA`, `en_GB`, `en_IE`, `en_IN`, `en_NZ`, `en_SG`, `en_US`, `en_ZA`, `fr_BE`, `fr_CA`, `fr_CH`, and `fr_FR`. Locale counts can change with OS asset state; rerun the probe when qualifying another machine.

This is a single-machine inventory. A clean-machine inventory, asset readiness semantics, offline recognition, and matched-corpus quality/performance remain unqualified.
