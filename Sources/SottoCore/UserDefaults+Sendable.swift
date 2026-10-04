import Foundation

// UserDefaults is Foundation's thread-safe preference store, and Sotto
// intentionally injects isolated suites across app, CLI, and test boundaries.
extension UserDefaults: @unchecked @retroactive Sendable {}
