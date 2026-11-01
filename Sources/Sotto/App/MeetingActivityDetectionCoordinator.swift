import AppKit
import SottoCore
import SottoViewModels

/// Watches only OS-provided activity metadata and offers an explicit recording action.
@MainActor
final class MeetingActivityDetectionCoordinator {
    private let settings: SettingsViewModel
    private let audio = AudioProcessActivityCollector()
    private let prompt = MeetingActivityPromptController()
    private let isRecording: () -> Bool
    private let isDictationActive: () -> Bool
    private let startRecording: () -> Void
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var candidate: MeetingActivityDetector.Candidate?
    private var presentedIdentity: MeetingIdentity?
    private var declinedUntil: [MeetingIdentity: Date] = [:]
    private var started = false

    init(
        settings: SettingsViewModel,
        isRecording: @escaping () -> Bool,
        isDictationActive: @escaping () -> Bool,
        startRecording: @escaping () -> Void
    ) {
        self.settings = settings
        self.isRecording = isRecording
        self.isDictationActive = isDictationActive
        self.startRecording = startRecording
    }

    func start() {
        guard !started, AppFeatures.meetingActivityDetectionEnabled, AppFeatures.meetingRecordingEnabled else { return }
        started = true
        observer = NotificationCenter.default.addObserver(
            forName: .sottoMeetingActivitySettingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        refresh()
    }

    func stop() {
        started = false
        stopObserving()
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    }

    private func refresh() {
        guard started, settings.meetingActivityDetectionMode != .off else { stopObserving(); return }
        guard timer == nil else { evaluate(); return }
        audio.start { [weak self] _ in Task { @MainActor in self?.evaluate() } }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.evaluate() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        evaluate()
    }

    private func stopObserving() {
        timer?.invalidate(); timer = nil
        audio.stop()
        candidate = nil
        presentedIdentity = nil
        prompt.close()
    }

    private func evaluate() {
        guard started, settings.meetingActivityDetectionMode == .prompt else { return }
        let snapshot = ActivitySignalSnapshot(
            audio: audio.snapshot(),
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        let now = Date()
        let detectedIdentity = MeetingActivityDetector.candidateIdentity(for: snapshot)
        // Browser and camera-only candidates need the richer URL/pre-join
        // corroboration from the full upstream detector. This first port only
        // offers on recognized native meeting-app audio (Slack also requires
        // full duplex in the shared detector).
        let identity = detectedIdentity.flatMap { identity -> MeetingIdentity? in
            guard identity.source == .app, let app = identity.app, app != .browser else { return nil }
            return identity
        }
        if identity != candidate?.identity {
            candidate = identity.map { MeetingActivityDetector.Candidate(identity: $0, since: now) }
            if identity != presentedIdentity { presentedIdentity = nil; prompt.close() }
        }
        let busy = isRecording() || isDictationActive()
        declinedUntil = declinedUntil.filter { $0.value > now }
        if busy {
            presentedIdentity = isRecording() ? identity : nil
            prompt.close()
        }
        let events = MeetingActivityDetector.evaluate(
            signal: snapshot, now: now,
            config: MeetingActivityDetector.Config(mode: .prompt),
            activeRecording: busy, candidate: candidate,
            suppressedIdentities: declinedUntil
        )
        guard !busy, let identity, events.contains(where: {
            if case .promptToRecord(identity) = $0 { return true }; return false
        }), presentedIdentity != identity else { return }
        presentedIdentity = identity
        prompt.show(displayName: Self.displayName(for: identity)) { [weak self] accepted in
            guard let self, self.presentedIdentity == identity else { return }
            if accepted {
                guard !self.isRecording(), !self.isDictationActive(), self.isCurrent(identity) else {
                    self.evaluate()
                    return
                }
                self.prompt.close()
                self.startRecording()
            }
            else {
                self.declinedUntil[identity] = Date().addingTimeInterval(30 * 60)
                self.presentedIdentity = nil
                self.prompt.close()
            }
        }
    }

    private func isCurrent(_ identity: MeetingIdentity) -> Bool {
        let snapshot = ActivitySignalSnapshot(
            audio: audio.snapshot(),
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        guard let detected = MeetingActivityDetector.candidateIdentity(for: snapshot),
              detected.source == .app, detected.app != .browser else { return false }
        return detected == identity
    }

    private static func displayName(for identity: MeetingIdentity) -> String {
        guard let app = identity.app else { return "a video call" }
        switch app {
        case .zoom: return "Zoom"
        case .teams: return "Microsoft Teams"
        case .webex: return "Webex"
        case .slack: return "Slack"
        case .facetime: return "FaceTime"
        case .browser: return "your browser"
        }
    }
}
