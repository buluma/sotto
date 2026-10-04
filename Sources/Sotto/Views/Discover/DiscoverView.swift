import SwiftUI
import AppKit
import SottoCore
import SottoViewModels

struct DiscoverView: View {
    let viewModel: DiscoverViewModel

    @State private var hoveredItemId: String?
    @State private var copiedItemId: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                headerSection

                ForEach(viewModel.allItems) { item in
                    discoverCard(item)
                }

            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Discover")
                    .font(DesignSystem.Typography.heroTitle)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                RoundedRectangle(cornerRadius: 1)
                    .fill(DesignSystem.Colors.accent)
                    .frame(width: 32, height: 3)
            }

            Text("Rick & Morty, between takes. A little interdimensional banter for your voice workspace.")
                .font(DesignSystem.Typography.bodyLarge)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textSelection(.enabled)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text("Original fan-written dialogue, not quotes from the show. All cards live on this Mac.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .textSelection(.enabled)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, DesignSystem.Spacing.md)
    }

    // MARK: - Card

    private func discoverCard(_ item: DiscoverItem) -> some View {
        let isHovered = hoveredItemId == item.id
        let isCopied = copiedItemId == item.id
        
        return ZStack(alignment: .bottomTrailing) {
            // Sacred geometry watermark
            SacredGeometryView(
                pattern: sacredGeometryPattern(forIcon: item.icon.isEmpty ? iconForType(item) : item.icon),
                size: 120,
                color: DesignSystem.Colors.accent.opacity(isHovered ? 0.14 : 0.08),
                lineWidth: 0.8
            )
            .offset(x: 24, y: 24)
            .blur(radius: 0.5)
            .clipped()

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .top) {
                    Text(item.title)
                        .font(DesignSystem.Typography.sectionTitle)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        copyItem(item)
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(isCopied ? DesignSystem.Colors.successGreen : DesignSystem.Colors.textTertiary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .help(isCopied ? "Copied" : "Copy to clipboard")
                    .opacity(isHovered || isCopied ? 1 : 0)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {

                    Text(item.body)
                        .font(bodyFont(for: item.type))
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.9))
                        .textSelection(.enabled)
                        .lineSpacing(item.type == .quote || item.type == .affirmation ? 4 : 3)
                }

                if let attribution = item.attribution {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Rectangle()
                            .fill(DesignSystem.Colors.accent.opacity(0.4))
                            .frame(width: 12, height: 1)
                        
                        Text(attribution)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .textSelection(.enabled)
                    }
                    .padding(.top, DesignSystem.Spacing.xs)
                }

                if let urlString = item.url,
                   let url = URL(string: urlString),
                   url.scheme == "https" {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Text(item.type == .sponsored ? "Learn More" : "Verify")
                                .font(DesignSystem.Typography.bodySmall)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.accent)
                        .foregroundStyle(DesignSystem.Colors.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.buttonCornerRadius))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, DesignSystem.Spacing.sm)
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .fill(DesignSystem.Colors.cardBackground)
                .cardShadow(isHovered ? DesignSystem.Shadows.cardHover : DesignSystem.Shadows.cardRest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(
                    isHovered ? DesignSystem.Colors.accent.opacity(0.2) : DesignSystem.Colors.border.opacity(0.6),
                    lineWidth: 0.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius))
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.hoverTransition) {
                hoveredItemId = hovering ? item.id : nil
            }
        }
    }

    // MARK: - Actions

    private func copyItem(_ item: DiscoverItem) {
        var text = item.title + "\n\n" + item.body
        if let attribution = item.attribution {
            text += "\n\n— " + attribution
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Telemetry.send(.copyToClipboard(source: .discover))

        withAnimation {
            copiedItemId = item.id
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                if copiedItemId == item.id {
                    copiedItemId = nil
                }
            }
        }
    }

    private func bodyFont(for type: DiscoverContentType) -> Font {
        switch type {
        case .quote: return .system(size: 16, weight: .regular, design: .serif)
        case .affirmation: return .system(size: 16, weight: .regular, design: .rounded)
        default: return DesignSystem.Typography.bodyLarge
        }
    }

    // MARK: - Helpers

    private func iconForType(_ item: DiscoverItem) -> String {
        switch item.type {
        case .tip: return "lightbulb.fill"
        case .quote: return "quote.bubble"
        case .affirmation: return "sparkles"
        case .sponsored: return item.icon
        }
    }

}
