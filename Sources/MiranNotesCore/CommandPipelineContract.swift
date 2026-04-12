import Foundation

public struct ExtensionContractVersion: Codable, Equatable, Sendable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public static let v1 = ExtensionContractVersion(major: 1, minor: 0)
}

public struct CommandPipelineContract: Equatable, Sendable {
    public let version: ExtensionContractVersion
    public let maxCommandsPerBatch: Int

    public init(version: ExtensionContractVersion = .v1, maxCommandsPerBatch: Int = 128) {
        self.version = version
        self.maxCommandsPerBatch = max(1, maxCommandsPerBatch)
    }
}
