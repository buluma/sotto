import AppKit
import Foundation

/// Request foreground activation, fall back to opening the running app, and
/// verify that macOS actually made the process frontmost before reporting success.
public enum VoiceControlAppActivation {
    @MainActor
    public static func runningApplication(matching name: String) -> NSRunningApplication? {
        let wanted = name.lowercased()
        return NSWorkspace.shared.runningApplications.first { app in
            let bundle = app.bundleIdentifier?.lowercased() ?? ""
            let label = app.localizedName?.lowercased() ?? ""
            return bundle == wanted || label == wanted || label.contains(wanted)
                || (wanted.contains("chrome") && bundle == "com.google.chrome")
        }
    }

    public static func bringForward(processID: Int32) async -> Bool {
        guard let app = await MainActor.run(body: {
            NSRunningApplication(processIdentifier: processID)
                ?? NSWorkspace.shared.runningApplications.first { $0.processIdentifier == processID }
        })
        else { return false }
        return await bringForward(app)
    }

    public static func bringForward(_ app: NSRunningApplication) async -> Bool {
        await MainActor.run {
            app.unhide()
            _ = app.activate(options: [.activateAllWindows])
        }
        if await isFrontmost(app) { return true }
        if let url = await MainActor.run(body: { app.bundleURL }) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        for _ in 0..<10 {
            if await isFrontmost(app) { return true }
            try? await Task.sleep(for: .milliseconds(120))
            await MainActor.run {
                _ = app.activate(options: [.activateAllWindows])
            }
        }
        return await isFrontmost(app)
    }

    public static func launch(bundleIdentifier: String) async -> NSRunningApplication? {
        guard let url = await MainActor.run(body: {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        })
        else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func isFrontmost(_ app: NSRunningApplication) async -> Bool {
        await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        }
    }
}
