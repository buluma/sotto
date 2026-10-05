import AppKit
import SwiftUI

/// One backdrop for all main-window destinations. Keep this inside the
/// hosting view so SwiftUI can continue installing the window's toolbar.
struct WindowCanvasBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        WindowCanvasSurface(reduceTransparency: reduceTransparency)
    }
}

/// Resolved accessibility state also makes the native material policy testable.
struct WindowCanvasSurface: View {
    let reduceTransparency: Bool

    var body: some View {
        Group {
            if reduceTransparency {
                DesignSystem.Colors.background
            } else {
                WindowBackdropMaterial()
                    .overlay(DesignSystem.Colors.canvasBackground)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WindowBackdropMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
