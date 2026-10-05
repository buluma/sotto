import SwiftUI

/// The hero interaction — a warm card with merkaba that responds to file dragging.
/// "Portal" effect: lifts, glows, particles drift on hover; contracts on file drop.
struct PortalDropZone: View {
    @Binding var isDragging: Bool
    let onDrop: ([NSItemProvider]) -> Bool
    let onBrowse: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Card background
            RoundedRectangle(cornerRadius: DesignSystem.Layout.dropZoneCornerRadius)
                .fill(isDragging ? AnyShapeStyle(DesignSystem.Colors.accentLight) : AnyShapeStyle(DesignSystem.Colors.cardGradient))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Layout.dropZoneCornerRadius)
                        .strokeBorder(
                            isDragging ? DesignSystem.Colors.accent.opacity(0.4) : Color.clear,
                            lineWidth: 1
                        )
                )
                .cardShadow(isDragging ? DesignSystem.Shadows.portalLift : DesignSystem.Shadows.cardRest)

            // Content
            VStack(spacing: DesignSystem.Spacing.md) {
                // Merkaba — state-reactive
                ZStack {
                    if isDragging && !reduceMotion {
                        ParticleField(
                            particleCount: 6,
                            tintColor: DesignSystem.Colors.accent,
                            opacity: 0.25,
                            driftDirection: .up
                        )
                        .frame(width: 120, height: 120)
                    }

                    MeditativeMerkabaView(
                        size: 80,
                        revolutionDuration: 6.0,
                        tintColor: DesignSystem.Colors.accent
                    )
                    .opacity(isDragging ? 0.9 : 0.7)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isDragging)
                }

                // Call to action
                Text("Drop a file to transcribe")
                    .font(DesignSystem.Typography.sectionTitle)
                    .foregroundStyle(isDragging ? DesignSystem.Colors.accent : .primary)

                // Browse button
                Button(action: onBrowse) {
                    Label("Browse Files", systemImage: "folder")
                }
                .sottoAction(.secondary)
                .accessibilityLabel("Browse files")
                .accessibilityHint("Opens a file picker to choose audio or video files")

                // Supported formats
                Text("Audio and video files · MP3, WAV, M4A, MP4, and more")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(.vertical, DesignSystem.Spacing.xl)
        }
        .frame(minHeight: 220)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            onDrop(providers)
        }
        .animation(reduceMotion ? nil : DesignSystem.Animation.portalLift, value: isDragging)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File drop zone")
        .accessibilityHint("Drop an audio or video file to start transcription")
    }
}
