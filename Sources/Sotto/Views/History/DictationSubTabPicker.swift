import SwiftUI
import SottoViewModels

/// Native segmented control for the Dictations sub-tabs. The system supplies
/// the platform appearance, including Liquid Glass on supported macOS releases.
struct DictationSubTabPicker: View {
    @Binding var selection: DictationHistoryViewModel.SubTab

    var body: some View {
        Picker("Dictations sub-tab", selection: $selection) {
            Text("History").tag(DictationHistoryViewModel.SubTab.history)
            Text("Stats").tag(DictationHistoryViewModel.SubTab.stats)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Dictations sub-tab")
    }
}
