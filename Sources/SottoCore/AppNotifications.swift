import Foundation

public extension Notification.Name {
    /// Payload-free cross-process hint; committed database intent is authoritative.
    static let sottoShareStopQueued = Notification.Name("sotto.shareStopQueued")
    static let sottoOpenOnboarding = Notification.Name("sotto.openOnboarding")
    static let sottoOpenSettings = Notification.Name("sotto.openSettings")
    static let sottoHotkeyTriggerDidChange = Notification.Name("sotto.hotkeyTriggerDidChange")
    static let sottoPushToTalkHotkeyTriggerDidChange = Notification.Name("sotto.pushToTalkHotkeyTriggerDidChange")
    static let sottoMeetingHotkeyTriggerDidChange = Notification.Name("sotto.meetingHotkeyTriggerDidChange")
    static let sottoFileTranscriptionHotkeyTriggerDidChange = Notification.Name("sotto.fileTranscriptionHotkeyTriggerDidChange")
    static let sottoYouTubeTranscriptionHotkeyTriggerDidChange = Notification.Name("sotto.youtubeTranscriptionHotkeyTriggerDidChange")
    static let sottoDictationAIPolishHotkeyTriggerDidChange = Notification.Name("sotto.dictationAIPolishHotkeyTriggerDidChange")
    static let sottoAppearanceModeDidChange = Notification.Name("sotto.appearanceModeDidChange")
    static let sottoMenuBarOnlyModeDidChange = Notification.Name("sotto.menuBarOnlyModeDidChange")
    static let sottoMenuBarIconVisibilityDidChange = Notification.Name("sotto.menuBarIconVisibilityDidChange")
    static let sottoShowIdlePillDidChange = Notification.Name("sotto.showIdlePillDidChange")
    /// Posted when idle-pill / live-overlay screen placement changes so both
    /// panels can move without waiting for the next show.
    static let sottoDictationOverlayPlacementDidChange = Notification.Name(
        "sotto.dictationOverlayPlacementDidChange"
    )
    static let sottoShowDiscoverDidChange = Notification.Name("sotto.showDiscoverDidChange")
    static let sottoShowMeetingRecordingPillDidChange = Notification.Name("sotto.showMeetingRecordingPillDidChange")
    static let sottoInstantDictationDidChange = Notification.Name("sotto.instantDictationDidChange")
    static let sottoMicrophoneSelectionDidChange = Notification.Name("sotto.microphoneSelectionDidChange")
    /// Posted when meeting audio retention changes. The app schedules one
    /// immediate guarded sweep so auto-delete choices take effect without
    /// waiting for a relaunch.
    static let sottoMeetingAudioRetentionDidChange = Notification.Name("sotto.meetingAudioRetentionDidChange")
    static let sottoAIFormatterWarning = Notification.Name("sotto.aiFormatterWarning")
    /// Posted by `DictationService`/`TranscriptionService` just before the AI
    /// formatter begins running on a transcript. Observed by the dictation
    /// flow coordinator to promote the overlay pill into the `.formatting`
    /// beat (visually distinct from `.processing`).
    ///
    /// `userInfo["source"]` is "dictation" or "transcription".
    static let sottoAIFormatterDidStart = Notification.Name("sotto.aiFormatterDidStart")
    /// Posted immediately after the formatter returns (success, fallback, or
    /// cancellation). Observers should not rely on this alone for terminal
    /// state — the regular `.showSuccess` / `.showError` flow will fire next.
    /// This exists mainly so observers can clear any formatter-scoped UI if
    /// the higher-level flow has already moved on.
    static let sottoAIFormatterDidFinish = Notification.Name("sotto.aiFormatterDidFinish")
    /// Posted when any calendar auto-start setting (mode, reminder lead time,
    /// trigger filter, included calendars) changes. The
    /// `MeetingAutoStartCoordinator` re-reads its config and re-evaluates on
    /// the next poll tick instead of waiting for the timer.
    static let sottoCalendarSettingsDidChange = Notification.Name("sotto.calendarSettingsDidChange")
    /// Posted when the ADR-023 activity-based meeting auto-stop setting
    /// changes. The coordinator re-reads the opt-in toggle immediately so
    /// disabling it tears down observers/countdowns without waiting.
    static let sottoMeetingAutoStopDidChange = Notification.Name("sotto.meetingAutoStopDidChange")
    /// Posted when the live transcript preview text size changes. The dictation
    /// flow coordinator re-reads the preference and updates the on-screen
    /// preview live, so a size change is visible mid-dictation.
    static let sottoDictationPreviewTextSizeDidChange = Notification.Name("sotto.dictationPreviewTextSizeDidChange")
    /// Posted by `DictationService` (as `object`) each time a live microphone
    /// capture ends: stop (before STT, usable or not), cancel, discard, or a
    /// stale take replaced by a new start.
    /// `userInfo[DictationCaptureNotificationKey.sessionID]` is the `Int`
    /// session whose capture ended. Observers pair it with their own start
    /// cue; the service does not know whether a cue played.
    static let sottoDictationCaptureDidStop = Notification.Name("sotto.dictationCaptureDidStop")
    /// Posted after a cancelled dictation is transcribed and saved to History.
    static let sottoDictationHistoryDidChange = Notification.Name("sotto.dictationHistoryDidChange")
}

public enum DictationCaptureNotificationKey {
    public static let sessionID = "sessionID"
}
