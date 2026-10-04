import SwiftUI

/// Semantic role for an actionable control. Apply via `.sottoAction(_:)`.
///
/// Replaces ad-hoc `.buttonStyle(.bordered) + .tint(...)` composition with a
/// single intent-carrying modifier. The role drives visual treatment so
/// callsites carry meaning, not styling primitives.
enum SottoActionRole {
    /// Primary action. Portal-green brand accent.
    case primary
    /// The single highest-priority primary CTA on a surface. Portal-green brand accent.
    case primaryProminent
    /// Default action weight. System label color, neutral chrome.
    case secondary
    /// Irreversible action. System destructive red.
    /// Pair with `Button(role: .destructive)` to also carry VoiceOver semantics.
    case destructive
    /// Highest-priority irreversible action. System destructive red.
    /// Pair with `Button(role: .destructive)` to also carry VoiceOver semantics.
    case destructiveProminent
    /// Lower visual weight than `.secondary`. Borderless, secondary label
    /// color. For non-essential actions in dense rows or as inline links.
    case subtle
}

extension View {
    /// Apply a semantic action role to a control.
    @ViewBuilder
    func sottoAction(_ role: SottoActionRole) -> some View {
        switch role {
        case .primary:
            self.buttonStyle(.bordered)
                .tint(DesignSystem.Colors.accent)
        case .primaryProminent:
            self.buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
        case .secondary:
            self.buttonStyle(.bordered)
                .tint(DesignSystem.Colors.tintNeutral)
        case .destructive:
            self.buttonStyle(.bordered)
                .tint(DesignSystem.Colors.errorRed)
        case .destructiveProminent:
            self.buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.errorRed)
        case .subtle:
            self.buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }

    /// Brand-consistent switch styling. Use for every `Toggle` styled as a
    /// switch so its on-state follows the app accent. Keeps sibling toggles consistent.
    func sottoSwitch() -> some View {
        self.toggleStyle(.switch)
            .tint(DesignSystem.Colors.accent)
    }
}
