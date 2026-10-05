import SwiftUI
import SottoViewModels

/// Keep tab labels and the search field usable when the sidebar leaves a narrow pane.
struct SettingsHeaderView: View {
    @Binding var activeTab: SettingsTab
    let tabBadges: [SettingsTab: SettingsStatusChip.Status]
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.md) {
                tabs
                search
                    .frame(minWidth: 200, maxWidth: 280)
                    .layoutPriority(1)
            }
            VStack(spacing: DesignSystem.Spacing.sm) {
                tabs
                search
            }
        }
    }

    private var tabs: some View {
        SettingsTabBar(activeTab: $activeTab, tabBadges: tabBadges)
    }

    private var search: some View {
        SettingsSearchField(query: $query, isFocused: isFocused)
    }
}
