import AppKit
import SwiftUI

@MainActor
final class MeetingActivityPromptController {
    private var panel: NSPanel?
    private var outcome: ((Bool) -> Void)?

    func show(displayName: String, onOutcome: @escaping (Bool) -> Void) {
        close()
        outcome = onOutcome
        let content = MeetingActivityPromptView(
            displayName: displayName,
            onRecord: { [weak self] in self?.outcome?(true) },
            onDecline: { [weak self] in self?.outcome?(false) }
        )
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 116)
        let panel = NSPanel(
            contentRect: hosting.frame, styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 356, y: frame.maxY - 132))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        outcome = nil
    }
}

private struct MeetingActivityPromptView: View {
    let displayName: String
    let onRecord: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "record.circle")
                    .foregroundStyle(DesignSystem.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record this meeting?").font(DesignSystem.Typography.sectionTitle)
                    Text("Meeting activity in \(displayName).")
                        .font(DesignSystem.Typography.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Not now", action: onDecline).sottoAction(.secondary)
                Button("Record", action: onRecord).sottoAction(.primaryProminent)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(width: 340)
        .background(DesignSystem.Colors.cardBackground, in: RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius))
    }
}
