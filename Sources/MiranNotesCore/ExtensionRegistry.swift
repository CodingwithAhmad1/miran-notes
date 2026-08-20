import Foundation
import os

public enum ExtensionCapability: String, Codable, Hashable, Sendable {
    case commandInterception
    case visualStyling
}

public struct ExtensionDescriptor: Equatable, Sendable {
    public let id: String
    public let version: Int
    public let capabilities: Set<ExtensionCapability>

    public init(id: String, version: Int, capabilities: Set<ExtensionCapability>) {
        self.id = id
        self.version = version
        self.capabilities = capabilities
    }
}

public protocol CommandInterceptorExtension: Sendable {
    var descriptor: ExtensionDescriptor { get }
    func intercept(commands: [EditCommand], document: NoteDocument, context: CommandContext) -> [EditCommand]
}

public struct CommandContext: Sendable {
    public let trigger: String
    /// UTF-16 range in the document text when known (e.g. editor selection).
    public let selectionRange: TextRange?

    public init(trigger: String, selectionRange: TextRange?) {
        self.trigger = trigger
        self.selectionRange = selectionRange
    }
}

/// Stable registration surface for command interceptors. Thread-safe; safe to call from `AppModel.apply` synchronously.
///
/// **Interceptor order:** `applyInterceptors` runs registered interceptors sorted by `descriptor.id`, then `AppModel` runs
/// closure-based interceptors in registration order. All interceptors see the **same** pre-`EditCommandEngine` `NoteDocument`
/// snapshot; each transforms the command batch only (document is not re-read between interceptors).
public final class ExtensionRegistry: Sendable {
    private final class Storage: @unchecked Sendable {
        var commandInterceptors: [String: any CommandInterceptorExtension] = [:]
    }

    private let lock = OSAllocatedUnfairLock(initialState: Storage())

    public init() {}

    public func registerInterceptor(_ interceptor: any CommandInterceptorExtension) {
        lock.withLock { storage in
            storage.commandInterceptors[interceptor.descriptor.id] = interceptor
        }
    }

    public func interceptorList() -> [ExtensionDescriptor] {
        lock.withLock { storage in
            storage.commandInterceptors.values.map(\.descriptor).sorted { $0.id < $1.id }
        }
    }

    public func applyInterceptors(
        to commands: [EditCommand],
        document: NoteDocument,
        context: CommandContext
    ) -> [EditCommand] {
        let interceptors = lock.withLock { storage in
            storage.commandInterceptors.values.sorted { $0.descriptor.id < $1.descriptor.id }
        }
        return interceptors.reduce(commands) { partial, interceptor in
            interceptor.intercept(commands: partial, document: document, context: context)
        }
    }
}
