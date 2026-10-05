import AppKit
import SwiftUI
import SottoCore
import SottoViewModels
import XCTest

@testable import Sotto

@MainActor
final class UIUXPresentationTests: XCTestCase {
    func testReduceTransparencyRemovesBehindWindowMaterial() {
        for reduceTransparency in [false, true] {
            let host = NSHostingView(
                rootView: WindowCanvasSurface(reduceTransparency: reduceTransparency))
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let materials = descendants(host).compactMap { $0 as? NSVisualEffectView }
            if reduceTransparency {
                XCTAssertTrue(materials.isEmpty, "Reduced transparency must use an opaque canvas")
            } else {
                XCTAssertEqual(materials.count, 1, "The canvas must install only one backdrop")
                XCTAssertEqual(materials.first?.blendingMode, NSVisualEffectView.BlendingMode.behindWindow)
                XCTAssertEqual(materials.first?.state, NSVisualEffectView.State.followsWindowActiveState)
            }
        }
    }

    func testFileImportCardFitsCompactPaneInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(
                rootView: PortalDropZone(isDragging: .constant(false), onDrop: { _ in false }, onBrowse: {})
                    .environment(\.colorScheme, scheme)
                    .transaction { $0.disablesAnimations = true })
            host.frame = NSRect(x: 0, y: 0, width: 360, height: 340)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            XCTAssertLessThanOrEqual(host.fittingSize.width, 361)
            XCTAssertLessThanOrEqual(host.fittingSize.height, 341)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertGreaterThan(bitmap.pixelsWide, 0)
            XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        }
    }

    private struct SettingsHeaderFixture: View {
        @FocusState private var focused: Bool

        var body: some View {
            SettingsHeaderView(
                activeTab: .constant(.system),
                tabBadges: [.capture: .required, .system: .required],
                query: .constant(""), isFocused: $focused)
        }
    }

    func testSettingsHeaderFitsCompactPaneWithoutRemovingTabsOrSearch() throws {
        for width in [560.0, 800.0] {
            let host = NSHostingView(rootView: SettingsHeaderFixture())
            host.frame = NSRect(x: 0, y: 0, width: width, height: 120)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            // ViewThatFits reports its first candidate's ideal width as fittingSize.
            // Inspect the actual native field in the offered pane instead.
            let field = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextField }.first(where: \.isEditable))
            let rect = host.convert(field.bounds, from: field)
            XCTAssertGreaterThan(rect.width, 150, "Search must keep a usable text area")
            XCTAssertGreaterThanOrEqual(rect.minX, -1)
            XCTAssertLessThanOrEqual(rect.maxX, width + 1)
            XCTAssertGreaterThanOrEqual(rect.minY, -1)
            XCTAssertLessThanOrEqual(rect.maxY, 121)
        }
    }

    func testLibraryRendersAtPlannedWindowSizes() async throws {
        let model = TranscriptionLibraryViewModel()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("sotto-ui-layout", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        model.configure(transcriptionRepo: repository)
        let recording = Transcription(fileName: "Synthetic recording with a deliberately long descriptive title.m4a", cleanTranscript: "A synthetic transcript for presentation checks.", status: .completed)
        for state in ["empty", "populated", "selected"] {
            if state == "populated" {
                try repository.save(recording)
                await model.loadTranscriptions().value
                XCTAssertEqual(model.transcriptions.count, 1)
            } else if state == "selected" {
                model.beginBulkSelection(startingWith: recording)
                XCTAssertEqual(model.selectedTranscriptionIDs, [recording.id])
            }
            for size in [CGSize(width: 860, height: 640), CGSize(width: 1280, height: 800), CGSize(width: 1600, height: 1000)] {
                // Offer the detail pane the remaining width after the existing sidebar.
                let pane = CGSize(width: size.width - 200, height: size.height - 52)
                let host = NSHostingView(rootView: TranscriptionLibraryView(
                    viewModel: model, primaryActionTitle: "New Transcription", onPrimaryAction: {},
                    onManagePrompts: {}, onSelect: { _ in })
                    .background(DesignSystem.Colors.background)
                    .environment(\.colorScheme, .dark)
                    .transaction { $0.disablesAnimations = true })
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: pane), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = host
                host.frame = NSRect(origin: .zero, size: pane)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                await model.loadTranscriptions().value
                XCTAssertFalse(model.isLoading, "The static fixture must finish its on-appear reload")
                XCTAssertNil(model.errorMessage)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(50))
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: output.appendingPathComponent("library-\(state)-\(Int(size.width))x\(Int(size.height)).png"))
                window.close()
            }
        }
        print("Library layout screenshots: \(output.path)")
    }

    func testTransformsRendersAtPlannedWindowSizes() async throws {
        let model = TransformsViewModel()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("sotto-ui-layout", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for state in ["unconfigured", "configured"] {
            model.hasLLMProvider = state == "configured"
            model.transforms = model.hasLLMProvider ? ["Polish", "Distill", "Decide"].enumerated().map { index, name in
                Prompt(name: name, content: "Rewrite selected text with clear, concise wording while preserving its meaning.", category: .transform, sortOrder: index)
            } : []
            for width in [660.0, 1080.0, 1400.0] {
                let pane = CGSize(width: width, height: 748)
                let host = NSHostingView(rootView: TransformsView(
                    viewModel: model, reservedHotkeys: [], llmConfiguredAction: {},
                    onEdit: { _ in }, onCreate: {}, onBindingsChanged: {})
                    .background(DesignSystem.Colors.background)
                    .environment(\.colorScheme, .dark)
                    .transaction { $0.disablesAnimations = true })
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: pane), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = host
                host.frame = NSRect(origin: .zero, size: pane)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: output.appendingPathComponent("transforms-\(state)-\(Int(width)).png"))
                window.close()
            }
        }
    }

    func testVocabularyModesRenderAtPlannedWindowSizes() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("sotto-ui-layout", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for mode in ["raw", "clean"] {
            let suite = "UIUXVocabulary.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(mode, forKey: UserDefaultsAppRuntimePreferences.processingModeKey)
            let settings = SettingsViewModel(defaults: defaults)
            for (width, height) in [(660.0, 748.0), (1080.0, 748.0), (1400.0, 748.0), (660.0, 2200.0)] {
                let pane = CGSize(width: width, height: height)
                let host = NSHostingView(rootView: VocabularyView(
                    settingsViewModel: settings, customWordsViewModel: CustomWordsViewModel(),
                    textSnippetsViewModel: TextSnippetsViewModel(), backupViewModel: VocabularyBackupViewModel())
                    .defaultAppStorage(defaults)
                    .background(DesignSystem.Colors.background)
                    .environment(\.colorScheme, .dark)
                    .transaction { $0.disablesAnimations = true })
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: pane), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = host
                host.frame = NSRect(origin: .zero, size: pane)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: output.appendingPathComponent("vocabulary-\(mode)-\(Int(width))-\(Int(height)).png"))
                window.close()
            }
        }
    }

    func testDictationsRenderAtPlannedWindowSizes() async throws {
        let database = try DatabaseManager()
        let repository = DictationRepository(dbQueue: database.dbQueue)
        let model = DictationHistoryViewModel()
        model.configure(dictationRepo: repository)
        for state in ["empty", "populated"] {
            if state == "populated" {
                try repository.save(Dictation(durationMs: 120000, rawTranscript: "A synthetic dictation for layout checks.", pastedToApp: "com.sotto.dev", wordCount: 240))
                model.loadDictations()
                XCTAssertEqual(model.stats.totalWords, 240)
            }
            for tab in [DictationHistoryViewModel.SubTab.history, .stats] {
                model.selectedSubTab = tab
                for size in [CGSize(width: 860, height: 640), CGSize(width: 1280, height: 800), CGSize(width: 1600, height: 1000)] {
                    try await renderFixture(DictationHistoryView(viewModel: model),
                        size: CGSize(width: size.width - 200, height: size.height - 52),
                        name: "dictations-\(state)-\(tab)-\(Int(size.width))")
                }
            }
        }
    }

    func testMeetingsRenderReadinessAndFailureAtPlannedWindowSizes() async throws {
        let suite = "UIUXMeetings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsViewModel(defaults: defaults)
        let pill = MeetingRecordingPillViewModel()
        let recent = TranscriptionLibraryViewModel()
        let model = MeetingsWorkspaceViewModel(recentMeetingsViewModel: recent,
            meetingPillViewModel: pill, settingsViewModel: settings,
            llmSettingsViewModel: LLMSettingsViewModel(defaults: defaults))
        for (name, state) in [("idle", MeetingRecordingPillViewModel.PillState.idle),
            ("error", .error("The recording was interrupted. Check the microphone connection and try again.")),
            ("recording", .recording)] {
            pill.state = state
            pill.elapsedSeconds = 125
            for size in [CGSize(width: 860, height: 640), CGSize(width: 1280, height: 800), CGSize(width: 1600, height: 1000)] {
                try await renderFixture(MeetingsView(viewModel: model, onRecordMeeting: {},
                    onPauseToggleMeeting: {}, onOpenCalendarSettings: {}, onOpenAISettings: {},
                    onRecoverMeetings: {}, onSelectMeeting: { _ in }).defaultAppStorage(defaults),
                    size: CGSize(width: size.width - 200, height: size.height - 52),
                    name: "meetings-\(name)-\(Int(size.width))")
            }
        }
    }

    func testCaptureRendersProcessingAndErrorAtPlannedWindowSizes() async throws {
        let suite = "UIUXCapture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TranscriptionViewModel(defaults: defaults,
            isWhisperModelDownloaded: { false }, isNemotronModelDownloaded: { false },
            isCohereModelDownloaded: { false })
        let settings = SettingsViewModel(defaults: defaults)
        let pill = MeetingRecordingPillViewModel()
        let workspace = MeetingsWorkspaceViewModel(recentMeetingsViewModel: TranscriptionLibraryViewModel(),
            meetingPillViewModel: pill, settingsViewModel: settings,
            llmSettingsViewModel: LLMSettingsViewModel(defaults: defaults))
        for state in ["idle", "processing", "error"] {
            model.isTranscribing = state == "processing"
            model.progress = state == "processing" ? "Transcribing locally…" : ""
            model.setError(message: state == "error" ? "The audio could not be opened. Choose another recording and try again." : nil)
            for size in [CGSize(width: 860, height: 640), CGSize(width: 1280, height: 800), CGSize(width: 1600, height: 1000)] {
                try await renderFixture(TranscribeView(viewModel: model,
                    chatViewModel: TranscriptChatViewModel(), promptResultsViewModel: PromptResultsViewModel(),
                    promptsViewModel: PromptsViewModel(), meetingPillViewModel: pill,
                    meetingsWorkspaceViewModel: workspace, showingProgressDetail: .constant(false),
                    onRecordMeeting: {}).defaultAppStorage(defaults),
                    size: CGSize(width: size.width - 200, height: size.height - 52),
                    name: "capture-\(state)-\(Int(size.width))")
            }
        }
    }

    private struct RecoveryFixtureService: MeetingRecordingRecoveryServicing {
        func discoverPendingRecoveries() async throws -> [MeetingRecordingLockFile] {
            [MeetingRecordingLockFile(sessionId: UUID(), startedAt: Date(), displayName: "Synthetic interrupted meeting")]
        }
        func recover(_ lock: MeetingRecordingLockFile) async throws -> Transcription {
            throw NSError(domain: "UIUXFixture", code: 1)
        }
        func discard(_ lock: MeetingRecordingLockFile) async throws {
            throw NSError(domain: "UIUXFixture", code: 1)
        }
    }

    func testMeetingsRecoveryRemainsProminentAtPlannedWindowSizes() async throws {
        let suite = "UIUXRecovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let database = try DatabaseManager()
        let settings = SettingsViewModel(defaults: defaults)
        settings.configure(permissionService: MockPermissionService(),
            dictationRepo: DictationRepository(dbQueue: database.dbQueue),
            entitlementsService: EntitlementsService(
                config: LicensingConfig(checkoutURL: nil, expectedVariantID: nil),
                store: InMemoryKeyValueStore(), api: StubLicenseAPI()),
            checkoutURL: nil, meetingRecoveryService: RecoveryFixtureService())
        for _ in 0..<20 where settings.pendingMeetingRecoveryCount == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(settings.pendingMeetingRecoveryCount, 1)
        let pill = MeetingRecordingPillViewModel()
        let model = MeetingsWorkspaceViewModel(recentMeetingsViewModel: TranscriptionLibraryViewModel(),
            meetingPillViewModel: pill, settingsViewModel: settings,
            llmSettingsViewModel: LLMSettingsViewModel(defaults: defaults))
        XCTAssertEqual(model.attentionItems.first?.id, "meeting-recovery")
        for size in [CGSize(width: 860, height: 640), CGSize(width: 1280, height: 800), CGSize(width: 1600, height: 1000)] {
            try await renderFixture(MeetingsView(viewModel: model, onRecordMeeting: {},
                onPauseToggleMeeting: {}, onOpenCalendarSettings: {}, onOpenAISettings: {},
                onRecoverMeetings: {}, onSelectMeeting: { _ in }).defaultAppStorage(defaults),
                size: CGSize(width: size.width - 200, height: size.height - 52),
                name: "meetings-recovery-\(Int(size.width))")
        }
    }

    func testOpaqueCanvasPresentationInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let fixture = VStack(alignment: .leading, spacing: 20) {
                Text("Capture").font(DesignSystem.Typography.pageTitle)
                Text("Choose a recording to transcribe locally.")
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                PortalDropZone(isDragging: .constant(false), onDrop: { _ in false }, onBrowse: {})
                    .frame(height: 340)
            }
            .padding(24)
            .background(WindowCanvasSurface(reduceTransparency: true))
            try await renderFixture(fixture, size: CGSize(width: 660, height: 588),
                name: "accessibility-reduced-\(scheme == .light ? "light" : "dark")", scheme: scheme)
        }
    }

    private func renderFixture<V: View>(_ view: V, size: CGSize, name: String, scheme: ColorScheme = .dark) async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("sotto-ui-layout", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let host = NSHostingView(rootView: view.background(DesignSystem.Colors.background)
            .environment(\.colorScheme, scheme).transaction { $0.disablesAnimations = true })
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
        window.close()
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
