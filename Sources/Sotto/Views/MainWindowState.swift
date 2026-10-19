import Foundation
import SottoCore
import SottoViewModels

@MainActor
@Observable
final class MainWindowState {
    private let askWorkspaceAvailable: Bool
    private var navigationRevision: UInt64 = 0
    private var latestTranscriptionOpen: UUID?

    var selectedItem: SidebarItem = .transcribe {
        didSet {
            if selectedItem == .ask, !askWorkspaceAvailable {
                selectedItem = .library
            }
            if selectedItem != oldValue {
                navigationRevision &+= 1
            }
        }
    }

    var requestedSettingsTab: SettingsTab?
    var requestedSettingsAnchor: String?
    var requestedSettingsTabRevision = 0
    var showingProgressDetail = false

    init(askWorkspaceAvailable: Bool = AppFeatures.isAskWorkspaceAvailable()) {
        self.askWorkspaceAvailable = askWorkspaceAvailable
    }

    func navigateToSettings(tab: SettingsTab? = nil, anchor: String? = nil) {
        requestedSettingsTab = tab
        requestedSettingsAnchor = anchor
        if tab != nil || anchor != nil {
            requestedSettingsTabRevision += 1
        }
        selectedItem = .settings
    }

    func navigate(to item: SidebarItem) {
        selectedItem = item
    }

    /// Sidebar clicks route here because `List(selection:)` does not report
    /// re-selecting the current row. Clicking the current section again
    /// returns it to its top level, matching the detail view's back button.
    func selectSidebarItem(
        _ item: SidebarItem,
        in viewModel: TranscriptionViewModel,
        library: TranscriptionLibraryViewModel? = nil
    ) {
        if item == selectedItem {
            switch item {
            case .library:
                // Same precedence as the Library detail: Dictations renders first.
                if let library, library.filter == .dictations {
                    library.filter = .all
                } else if viewModel.currentTranscription != nil {
                    viewModel.showInputPortal()
                }
            case .meetings:
                if showsMeetingDetail(viewModel.currentTranscription) {
                    viewModel.showInputPortal()
                }
                meetingsDetailID = nil
            default:
                break
            }
        }
        selectedItem = item
    }

    func navigateToAsk() {
        selectedItem = .ask
    }

    /// Capture the user's intent before scheduling the load. Library and
    /// Meetings share this boundary so a newer open, selection, or navigation
    /// invalidates an older fetch, including leaving and returning to a tab.
    @discardableResult
    func openTranscription(
        from tab: SidebarItem,
        in viewModel: TranscriptionViewModel,
        load: @escaping @MainActor () async -> Transcription?
    ) -> Task<Bool, Never> {
        let requestID = UUID()
        latestTranscriptionOpen = requestID
        let navigation = navigationRevision
        let selection = viewModel.currentTranscriptionRevision
        return Task {
            let isCurrent = {
                !Task.isCancelled
                    && self.latestTranscriptionOpen == requestID
                    && self.navigationRevision == navigation
                    && self.selectedItem == tab
                    && viewModel.currentTranscriptionRevision == selection
            }
            guard isCurrent(), let stored = await load(), isCurrent()
            else { return false }
            viewModel.currentTranscription = stored
            navigateToTranscription(from: tab, id: stored.id)
            return true
        }
    }

    func startNewTranscription() {
        selectedItem = .transcribe
        showingProgressDetail = false
    }

    func beginCreatingTransform() {
        editingTransform = nil
        isCreatingTransform = true
        selectedItem = .transforms
    }

    func consumeRequestedSettingsTab() {
        requestedSettingsTab = nil
        requestedSettingsAnchor = nil
    }

    /// Transforms tab — pending sheet state (ADR-022). When non-nil the
    /// editor sheet appears for that Transform.
    var editingTransform: Prompt?
    /// True when the Create-your-own sheet should be presented.
    var isCreatingTransform: Bool = false

    /// The transcript open in the Meetings workspace, if any. Meetings opened
    /// there stay there so the sidebar keeps showing where the user came from.
    private(set) var meetingsDetailID: UUID?

    func showsMeetingDetail(_ transcription: Transcription?) -> Bool {
        guard let transcription else { return false }
        return transcription.id == meetingsDetailID
    }

    func closeMeetingDetail() {
        meetingsDetailID = nil
    }

    /// Reveal the open transcription. A meeting opened from the Meetings
    /// workspace stays there; everything else surfaces in Library, the
    /// universal archive. The Transcribe tab is only the capture surface.
    func navigateToTranscription(from current: SidebarItem? = nil, id: UUID? = nil) {
        if current == .meetings, let id {
            meetingsDetailID = id
            selectedItem = .meetings
        } else {
            meetingsDetailID = nil
            selectedItem = .library
        }
    }
}

extension Notification.Name {
    /// Posted after a Transforms save/delete/reset so the
    /// `TransformsCoordinator` can reload bindings into the hotkey
    /// registry.
    static let transformsBindingsChanged = Notification.Name("com.sotto.transforms.bindingsChanged")
    /// Posted after a successful Transform is saved to local history so the
    /// Transforms tab can refresh if it is visible.
    static let transformHistoryChanged = Notification.Name("com.sotto.transforms.historyChanged")
}
