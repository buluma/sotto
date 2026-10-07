import SwiftUI
import SottoCore
import SottoViewModels

struct QuickAccessSidebarCard: View {
    let meetings: [Transcription]
    let isLoading: Bool
    let microphoneGranted: Bool
    let speechEngine: SpeechEnginePreference
    let engineStatus: EngineSettingsViewModel.LocalModelStatus
    let onOpenMeeting: (Transcription) -> Void
    let onRecordMeeting: () -> Void
    let onOpenSettings: () -> Void

    private var recentMeetings: [Transcription] {
        Array(meetings.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)

                Text("Quick access")
                    .font(DesignSystem.Typography.bodySmall.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer(minLength: 0)

                if !recentMeetings.isEmpty {
                    recordButton(compact: true)
                }
            }

            if isLoading && recentMeetings.isEmpty {
                Text("Loading recent meetings…")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.vertical, DesignSystem.Spacing.xs)
            } else if recentMeetings.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Your saved meetings will show up here.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    recordButton(compact: false)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(recentMeetings) { meeting in
                        Button {
                            onOpenMeeting(meeting)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: meeting.effectiveDisplayTitle)
                                    .font(DesignSystem.Typography.caption.weight(.medium))
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Text(meeting.createdAt, style: .relative)
                                    .font(DesignSystem.Typography.micro)
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .sottoAction(.subtle)
                        .accessibilityLabel("Open meeting \(meeting.effectiveDisplayTitle)")
                        .accessibilityIdentifier("sidebar-recent-meeting-\(meeting.id.uuidString)")
                    }
                }
            }

            Divider()
                .padding(.vertical, 2)

            Button(action: onOpenSettings) {
                readinessRow(
                    icon: "mic.fill",
                    title: "Mic",
                    status: microphoneGranted ? "Ready" : "Needs access",
                    isReady: microphoneGranted,
                    isUnavailable: false
                )
            }
            .sottoAction(.subtle)
            .help("Open meeting capture settings")
            .accessibilityLabel(
                microphoneGranted ? "Microphone ready. Open capture settings" : "Microphone access needed. Open capture settings"
            )

            readinessRow(
                icon: "waveform",
                title: speechEngine.displayName,
                status: engineStatusLabel,
                isReady: engineIsAvailable,
                isUnavailable: engineStatus == .failed
            )
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.surfaceElevated.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .strokeBorder(DesignSystem.Colors.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .accessibilityIdentifier("sidebar-quick-access")
    }

    @ViewBuilder
    private func recordButton(compact: Bool) -> some View {
        Button(action: onRecordMeeting) {
            if compact {
                Image(systemName: "record.circle")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            } else {
                Label("Record a meeting", systemImage: "record.circle")
                    .font(DesignSystem.Typography.caption.weight(.medium))
            }
        }
        .sottoAction(.subtle)
        .help("Record a meeting")
        .accessibilityLabel("Record a meeting")
        .accessibilityIdentifier("sidebar-record-meeting")
    }

    private var engineStatusLabel: String {
        switch engineStatus {
        case .ready: "Ready"
        case .notLoaded: "Installed"
        case .notDownloaded: "Setup needed"
        case .checking, .unknown: "Checking"
        case .preparing, .repairing: "Loading"
        case .failed: "Unavailable"
        }
    }

    private var engineIsAvailable: Bool {
        engineStatus == .ready || engineStatus == .notLoaded
    }

    private func readinessRow(
        icon: String,
        title: String,
        status: String,
        isReady: Bool,
        isUnavailable: Bool
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 14)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text(title)
                .font(DesignSystem.Typography.micro)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)

            Spacer(minLength: DesignSystem.Spacing.xs)

            Text(status)
                .font(DesignSystem.Typography.micro.weight(.medium))
                .foregroundStyle(
                    isUnavailable
                        ? DesignSystem.Colors.errorRed
                        : (isReady ? DesignSystem.Colors.successGreen : DesignSystem.Colors.warningAmber)
                )
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
