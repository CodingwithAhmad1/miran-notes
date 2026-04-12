import Foundation

public enum ExtensionCompatibility {
    public static func supports(
        descriptor: ExtensionDescriptor,
        requiredVersion: ExtensionContractVersion,
        requiredCapabilities: Set<ExtensionCapability>
    ) -> Bool {
        guard descriptor.version >= requiredVersion.major else { return false }
        return requiredCapabilities.isSubset(of: descriptor.capabilities)
    }
}
