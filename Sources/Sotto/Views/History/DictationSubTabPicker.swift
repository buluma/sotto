import SwiftUI
import SottoViewModels

/// Capsule picker for the Dictations sub-tabs. Its selected tab uses a tinted
/// Liquid Glass pill on macOS 26+, with the accent capsule retained on older
/// systems. A `matchedGeometryEffect` slides the selection between options.
struct DictationSubTabPicker: View {
    @Binding var selection: DictationHistoryViewModel.SubTab
    @Namespace private var pillNamespace
    @State private var hoveredTab: DictationHistoryViewModel.SubTab?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DictationHistoryViewModel.SubTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictations sub-tab")
    }

    @ViewBuilder
    private func tabButton(_ tab: DictationHistoryViewModel.SubTab) -> some View {
        let isSelected = selection == tab
        let isHovered = hoveredTab == tab
        Button {
            withAnimation(DesignSystem.Animation.contentSwap) {
                selection = tab
            }
        } label: {
            Text(label(for: tab))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    isSelected ? DesignSystem.Colors.onAccent : Color.primary.opacity(isHovered ? 0.85 : 0.65))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(minWidth: 70)
                .background {
                    selectionIndicator(isSelected: isSelected)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(for: tab))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            hoveredTab = hovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
        }
    }

    @ViewBuilder
    private func selectionIndicator(isSelected: Bool) -> some View {
        if isSelected {
            if #available(macOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(
                        .regular.tint(DesignSystem.Colors.accent).interactive(),
                        in: Capsule()
                    )
                    .matchedGeometryEffect(id: "pill", in: pillNamespace)
            } else {
                Capsule()
                    .fill(DesignSystem.Colors.accent)
                    .shadow(color: DesignSystem.Colors.accent.opacity(0.30), radius: 6, x: 0, y: 2)
                    .matchedGeometryEffect(id: "pill", in: pillNamespace)
            }
        }
    }

    private func label(for tab: DictationHistoryViewModel.SubTab) -> String {
        switch tab {
        case .history: return "History"
        case .stats: return "Stats"
        }
    }
}
