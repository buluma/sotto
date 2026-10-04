import AppKit

/// Loads Sotto’s S monogram for the menu bar and inline brand marks.
enum SottoIcon {

    /// Menu bar icon state variants.
    enum MenuBarState: Equatable {
        case idle
        case recording
        case processing
    }

    /// Load the Sotto mark silhouette as a **template** NSImage for menu bar use.
    /// The image is stored as a processed SwiftPM resource (menubar-icon.png / @2x).
    /// Template images adapt to light/dark mode automatically.
    static func menuBarIcon(pointSize: CGFloat = 18, state: MenuBarState = .idle) -> NSImage {
        let baseIcon = loadBaseMenuBarIcon(pointSize: pointSize)

        switch state {
        case .idle:
            return baseIcon
        case .recording:
            return compositeIcon(base: baseIcon, pointSize: pointSize, badgeColor: .systemRed)
        case .processing:
            return compositeIcon(base: baseIcon, pointSize: pointSize, badgeColor: .systemOrange)
        }
    }

    private static func loadBaseMenuBarIcon(pointSize: CGFloat) -> NSImage {
        // Try loading from SwiftPM resource bundle first, then fall back to main bundle.
        if let url = Bundle.module.url(forResource: "menubar-icon@2x", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        {
            image.size = NSSize(width: pointSize, height: pointSize)
            image.isTemplate = true
            return image
        }

        // Fallback: 1x version
        if let url = Bundle.module.url(forResource: "menubar-icon", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        {
            image.size = NSSize(width: pointSize, height: pointSize)
            image.isTemplate = true
            return image
        }

        // Last resort: return a system symbol
        let fallback =
            NSImage(systemSymbolName: "waveform", accessibilityDescription: "Sotto")
            ?? NSImage()
        fallback.size = NSSize(width: pointSize, height: pointSize)
        fallback.isTemplate = true
        return fallback
    }

    /// Composite the base icon with a colored status dot in the bottom-right corner.
    /// The resulting image is NOT a template (so the dot renders in color).
    /// The base icon is drawn using the menu bar's label color so it matches
    /// the idle template appearance in both light and dark mode.
    private static func compositeIcon(base: NSImage, pointSize: CGFloat, badgeColor: NSColor) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            // Use the base icon alpha channel as a mask, filled with the menu bar
            // foreground color. This replicates template-image rendering while keeping
            // isTemplate=false so the colored dot isn't tinted by the system.
            // NSStatusBar items use controlTextColor which is white on dark menu bars
            // and black on light ones (pre-Sonoma or accessibility settings).
            if let cgBase = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
                let ctx = NSGraphicsContext.current?.cgContext
            {
                ctx.saveGState()
                ctx.clip(to: rect, mask: cgBase)
                NSColor.controlTextColor.setFill()
                ctx.fill(rect)
                ctx.restoreGState()
            }

            // Draw colored dot (bottom-right, 5pt diameter)
            let dotSize: CGFloat = 5
            let dotRect = NSRect(
                x: rect.maxX - dotSize - 0.5,
                y: 0.5,
                width: dotSize,
                height: dotSize
            )
            badgeColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        // NOT a template — the dot must render in color
        image.isTemplate = false
        return image
    }

    /// Load the transparent S monogram as a template image for inline tinting.
    static func brandMark(pointSize: CGFloat = 18) -> NSImage {
        guard let url = Bundle.module.url(forResource: "sotto-mark", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else {
            return NSImage(size: NSSize(width: pointSize, height: pointSize))
        }
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = true
        return image
    }

    /// The bundled personal app icon, with a matching fallback for raw builds.
    static func appIcon(size: CGFloat = 512) -> NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            image.size = NSSize(width: size, height: size)
            return image
        }
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(calibratedRed: 0.12, green: 0.10, blue: 0.22, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()
            let mark = brandMark(pointSize: size)
            mark.isTemplate = false
            mark.draw(in: rect)
            return true
        }
    }
}
