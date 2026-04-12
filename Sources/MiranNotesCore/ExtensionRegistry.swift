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
    public let selectionRange: TextRange?

    public init(trigger: String, selectionRange: TextRange?) {
        self.trigger = trigger
        self.selectionRange = selectionRange
    }
}

public actor ExtensionRegistry {
    private var commandProducers: [String: any CommandProducerExtension] = [:]
    private var commandInterceptors: [String: any CommandInterceptorExtension] = [:]

    public init() {}

    public func registerProducer(_ producer: any CommandProducerExtension) {
        commandProducers[producer.descriptor.id] = producer
    }

    public func registerInterceptor(_ interceptor: any CommandInterceptorExtension) {
        commandInterceptors[interceptor.descriptor.id] = interceptor
    }

    public func producerList() -> [ExtensionDescriptor] {
        commandProducers.values.map(\.descriptor).sorted { $0.id < $1.id }
    }

    public func interceptorList() -> [ExtensionDescriptor] {
        commandInterceptors.values.map(\.descriptor).sorted { $0.id < $1.id }
    }

    public func applyInterceptors(
        to commands: [EditCommand],
        document: NoteDocument,
        context: CommandContext
    ) -> [EditCommand] {
        commandInterceptors.values
            .sorted { $0.descriptor.id < $1.descriptor.id }
            .reduce(commands) { partial, interceptor in
                interceptor.intercept(commands: partial, document: document, context: context)
            }
    }
}
