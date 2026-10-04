import AppKit
import SwiftUI

/// Sotto’s S monogram for inline assistant and status surfaces.
/// Uses the bundled template asset so consumers can tint the mark consistently.
struct SottoLogo: View {
    var size: CGFloat = 18
    var tint: Color = DesignSystem.Colors.accent
    var opacity: Double = 1.0

    var body: some View {
        Image(nsImage: Self.cachedMark)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .frame(width: size, height: size)
            .foregroundStyle(tint.opacity(opacity))
            .accessibilityHidden(true)
    }

    /// Process-lifetime cache. The template NSImage is built once at first
    /// access; subsequent SottoLogo instances reuse the same alpha
    /// raster and only re-tint via SwiftUI. Rendered at 18pt logical so the
    /// 4× source (72px) covers any 12-24pt display without re-rasterization.
    private static let cachedMark: NSImage = SottoIcon.brandMark(pointSize: 18)
}
