# Apple Speech locale inventory spike

This developer-only probe checks `SpeechTranscriber` availability and reports supported and installed locale identifiers on macOS 26 or later. It does not install speech assets or start recognition.

Compile and run it explicitly:

```sh
swiftc -parse-as-library -swift-version 6 -framework Speech \
  benchmarks/asr/apple-speech-spike/LocaleInventory.swift \
  -o /tmp/sotto-apple-speech-locale-inventory
/tmp/sotto-apple-speech-locale-inventory --developer-opt-in --inventory
```

The inventory includes `AssetInventory.status` for both `SpeechTranscriber` and `DictationTranscriber` for each locale returned by `installedLocales`. These are separate module-specific readiness checks; locale enumeration alone is not an asset-readiness result. For a selected locale, the file-recognition mode also calls `assetInstallationRequest(supporting:)` and proceeds only when it returns `nil` (Apple documents `nil` when assets are installed); it never calls `downloadAndInstall()`.

To run a file recognition attempt, use:

```sh
/tmp/sotto-apple-speech-locale-inventory --developer-opt-in \
  --transcribe-file en_US /path/to/audio-file
```

The file mode proceeds only if `assetInstallationRequest(supporting:)` returns `nil`; if it returns a request object, the probe stops without downloading it. The inventory's status result is diagnostic and differed from the installation-request result for `en_US` on the development Mac. Keep this tool outside normal engine selection and do not use a successful connected run alone to claim offline recognition or quality qualification.

## Development Mac observation — 2026-10-06

On the development Mac running macOS 27.2, `SpeechTranscriber.isAvailable` returned `true`; 45 supported locales and 16 `installedLocales` entries were reported. The inventory's `status(forModules:)` calls returned `.supported` for all 16 entries. However, a direct `assetInstallationRequest(supporting:)` check for `en_US` returned `nil` (documented as already installed), and a subsequent status call returned `.installed`. This status inconsistency remains unexplained.

The probe then transcribed a locally generated `say` fixture for `en_US` and returned: “The local speech asset is ready. Please capture the meeting transcript.” Network access stayed enabled, so this proves only that the current Mac can complete a file transcription with the available asset. A system-wide Wi-Fi disconnect was not used because it would interrupt the Mac's network-dependent work and this session. Offline behavior, clean-machine behavior, and matched-corpus quality/performance remain unqualified; a future offline check needs an isolation method that does not cut off the whole Mac and that also covers any Apple Speech service process.
