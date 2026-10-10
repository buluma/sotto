import AppKit
import SwiftUI

/// AppKit owns this window's toolbar. Read its layout so every destination
/// reserves the same header space, including those without a search field.
struct WindowToolbarGeometry: NSViewRepresentable {
    var onHeightChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ToolbarGeometryView {
        let view = ToolbarGeometryView()
        view.onHeightChange = onHeightChange
        return view
    }

    func updateNSView(_ view: ToolbarGeometryView, context: Context) {
        view.onHeightChange = onHeightChange
    }

    final class ToolbarGeometryView: NSView {
        var onHeightChange: ((CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?
        private var lastHeight: CGFloat?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = window?.observe(\.contentLayoutRect, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.reportHeight() }
            }
        }

        override func layout() {
            super.layout()
            reportHeight()
        }

        private func reportHeight() {
            guard let window, let contentView = window.contentView else { return }
            let height = max(0, contentView.bounds.height - window.contentLayoutRect.height)
            guard height > 0, height != lastHeight else { return }
            lastHeight = height
            let callback = onHeightChange
            Task { @MainActor in callback?(height) }
        }
    }
}
