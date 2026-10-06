# Apple SpeechTranscriber spike

This directory contains a developer-only locale/asset inventory probe and a separate Sotto runtime adapter. Both require explicit opt-in and stay outside shipping engine selection, `sotto-cli`, and defaults. Neither starts an asset download.

## Locale and asset inventory probe

The direct probe reports supported and installed locale identifiers on macOS 26 or later. It checks `AssetInventory.status` for both `SpeechTranscriber` and `DictationTranscriber`; locale enumeration alone is not an asset-readiness result.

Compile and inventory locales:

```sh
swiftc -parse-as-library -swift-version 6 -framework Speech \
  benchmarks/asr/apple-speech-spike/LocaleInventory.swift \
  -o /tmp/sotto-apple-speech-locale-inventory
/tmp/sotto-apple-speech-locale-inventory --developer-opt-in --inventory
```

For a selected locale, its file mode calls `assetInstallationRequest(supporting:)` and proceeds only when it returns `nil`; if it returns a request object, the probe stops without downloading it:

```sh
/tmp/sotto-apple-speech-locale-inventory --developer-opt-in \
  --transcribe-file en_US /path/to/audio-file
```

On the development Mac running macOS 27.2, the inventory returned available=true, 45 supported locales, and 16 `installedLocales` entries. Status calls returned `.supported`, but the `en_US` installation request returned `nil` and a subsequent status reported `.installed`. A locally generated `say` fixture transcribed successfully while network access was enabled. Offline behavior, clean-machine behavior, and matched-corpus quality/performance remain unqualified; system-wide Wi-Fi isolation interrupts network-dependent work.

## Sotto runtime adapter

The separate Swift package exercises Apple's on-device `SpeechTranscriber` through Sotto's background STT scheduler lane. It is compiled only in debug builds, requires an already-installed locale, and leaves `assetRevision` unset because Apple does not expose an asset revision.

```sh
swift run --package-path benchmarks/asr/apple-speech-spike AppleSpeechSpike \
  --developer-opt-in --transcribe-file en_US /path/to/audio.wav
```

The harness emits a JSON result with a session snapshot of the selected locale, module, preset, OS version, and asset status. It does not change network settings, and a connected run does not establish offline behavior or quality qualification.
