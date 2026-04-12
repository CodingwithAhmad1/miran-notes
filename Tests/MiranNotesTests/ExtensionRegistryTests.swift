import XCTest

@testable import MiranNotesCore

private struct NoopProducer: CommandProducerExtension {
    let descriptor: ExtensionDescriptor

    func makeCommands(document: NoteDocument, context: CommandContext) -> [EditCommand] {
        _ = document
        _ = context
        return []
    }
}

private struct NoopInterceptor: CommandInterceptorExtension {
    let descriptor: ExtensionDescriptor

    func intercept(commands: [EditCommand], document: NoteDocument, context: CommandContext) -> [EditCommand] {
        _ = document
        _ = context
        return commands
    }
}

final class ExtensionRegistryTests: XCTestCase {
    func testRegistryTracksDescriptors() async throws {
        let registry = ExtensionRegistry()
        let producer = NoopProducer(
            descriptor: ExtensionDescriptor(
                id: "builtin.slash",
                version: 1,
                capabilities: [.commandProduction]
            )
        )
        let interceptor = NoopInterceptor(
            descriptor: ExtensionDescriptor(
                id: "builtin.guardrail",
                version: 1,
                capabilities: [.commandInterception]
            )
        )

        await registry.registerProducer(producer)
        await registry.registerInterceptor(interceptor)

        let producers = await registry.producerList()
        let interceptors = await registry.interceptorList()
        XCTAssertEqual(producers.map(\.id), ["builtin.slash"])
        XCTAssertEqual(interceptors.map(\.id), ["builtin.guardrail"])
    }
}
