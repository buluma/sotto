import Foundation

public protocol LicenseAPI: Sendable {
    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation
    func validate(licenseKey: String, instanceID: String?) async throws -> LicenseValidation
    func deactivate(licenseKey: String, instanceID: String) async throws
}

public struct LicenseActivation: Sendable {
    public let licenseKey: String
    public let instanceID: String
    public let variantID: Int?
}

public struct LicenseValidation: Sendable {
    public let valid: Bool
    public let variantID: Int?
}

/// No licensing transport exists in the personal fork.
public struct DisabledLicenseAPI: LicenseAPI {
    public init() {}

    public func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation {
        throw EntitlementsError.configuration("License activation is unavailable in this personal fork.")
    }

    public func validate(licenseKey: String, instanceID: String?) async throws -> LicenseValidation {
        throw EntitlementsError.configuration("License validation is unavailable in this personal fork.")
    }

    public func deactivate(licenseKey: String, instanceID: String) async throws {
        throw EntitlementsError.configuration("License deactivation is unavailable in this personal fork.")
    }
}
