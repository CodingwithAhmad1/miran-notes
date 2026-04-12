import Foundation

public enum ExtensionCapability: String, Codable, Hashable, Sendable {
    case commandProduction
    case commandInterception
    case visualStyling
    case auxiliaryArtifacts
    case syncHooks
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

public protocol CommandProducerExtension: Sendable {
    var descriptor: ExtensionDescriptor { get }
    func makeCommands(document: NoteDocument, context: CommandContext) -> [EditCommand]
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

/// Stable registration surface for command producers and interceptors. Thread-safe; safe to call from `AppModel.apply` synchronously.
///
/// **Interceptor order:** `applyInterceptors` runs registered interceptors sorted by `descriptor.id`, then `AppModel` runs
/// closure-based interceptors in registration order. All interceptors see the **same** pre-`EditCommandEngine` `NoteDocument`
/// snapshot; each transforms the command batch only (document is not re-read between interceptors).
public final class ExtensionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var commandProducers: [String: any CommandProducerExtension] = [:]
    private var commandInterceptors: [String: any CommandInterceptorExtension] = [:]

    public init() {}

    public func registerProducer(_ producer: any CommandProducerExtension) {
        lock.lock()
        defer { lock.unlock() }
        commandProducers[producer.descriptor.id] = producer
    }

    public func registerInterceptor(_ interceptor: any CommandInterceptorExtension) {
        lock.lock()
        defer { lock.unlock() }
        commandInterceptors[interceptor.descriptor.id] = interceptor
    }

    public func producerList() -> [ExtensionDescriptor] {
        lock.lock()
        let values = commandProducers.values.map(\.descriptor).sorted { $0.id < $1.id }
        lock.unlock()
        return values
    }

    public func interceptorList() -> [ExtensionDescriptor] {
        lock.lock()
        let values = commandInterceptors.values.map(\.descriptor).sorted { $0.id < $1.id }
        lock.unlock()
        return values
    }

    public func applyInterceptors(
        to commands: [EditCommand],
        document: NoteDocument,
        context: CommandContext
    ) -> [EditCommand] {
        lock.lock()
        let interceptors = commandInterceptors.values.sorted { $0.descriptor.id < $1.descriptor.id }
        lock.unlock()
        return interceptors.reduce(commands) { partial, interceptor in
            interceptor.intercept(commands: partial, document: document, context: context)
        }
    }
}
