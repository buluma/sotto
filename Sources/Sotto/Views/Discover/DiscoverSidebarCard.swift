import SwiftUI
import SottoCore
import SottoViewModels

struct DiscoverSidebarCard: View {
    let viewModel: DiscoverViewModel
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        if let item = viewModel.sidebarItem {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: item.icon.isEmpty ? "sparkles" : item.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(DesignSystem.Colors.accent.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("Discover")
                            .font(DesignSystem.Typography.micro.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.accent)

                        Text(verbatim: item.title)
                            .font(DesignSystem.Typography.bodySmall.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(verbatim: item.body.isEmpty ? item.title : item.body)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("discover-sidebar-dialogue")
                    }
                }
                .padding(DesignSystem.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                        .fill(isSelected ? DesignSystem.Colors.accentLight : (isHovered ? DesignSystem.Colors.surfaceElevated : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                        .strokeBorder(
                            isSelected ? DesignSystem.Colors.accent.opacity(0.4) : .clear,
                            lineWidth: 0.5
                        )
                )
            }
            .buttonStyle(.plain)
            .help("\(item.title). \(item.body)")
            .accessibilityLabel("Discover: \(item.title). \(item.body)")
            .onHover { hovering in
                withAnimation(DesignSystem.Animation.hoverTransition) {
                    isHovered = hovering
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.bottom, DesignSystem.Spacing.sm)
        }
    }
}
