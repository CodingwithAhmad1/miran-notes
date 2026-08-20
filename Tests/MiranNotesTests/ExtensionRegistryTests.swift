import XCTest

@testable import MiranNotesCore

private struct NoopInterceptor: CommandInterceptorExtension {
    let descriptor: ExtensionDescriptor

    func intercept(commands: [EditCommand], document: NoteDocument, context: CommandContext) -> [EditCommand] {
        _ = document
        _ = context
        return commands
    }
}

private struct PrefixInterceptor: CommandInterceptorExtension {
    let descriptor: ExtensionDescriptor
    let prefix: String

    func intercept(commands: [EditCommand], document: NoteDocument, context: CommandContext) -> [EditCommand] {
        _ = document
        _ = context
        guard case let .replaceText(r, rep) = commands.first, commands.count == 1 else { return commands }
        return [.replaceText(range: r, replacement: prefix + rep)]
    }
}

final class ExtensionRegistryTests: XCTestCase {
    func testRegistryTracksDescriptors() {
        let registry = ExtensionRegistry()
        let interceptor = NoopInterceptor(
            descriptor: ExtensionDescriptor(
                id: "builtin.guardrail",
                version: 1,
                capabilities: [.commandInterception]
            )
        )

        registry.registerInterceptor(interceptor)

        let interceptors = registry.interceptorList()
        XCTAssertEqual(interceptors.map(\.id), ["builtin.guardrail"])
    }

    func testApplyInterceptorsSortedById() {
        let registry = ExtensionRegistry()
        registry.registerInterceptor(PrefixInterceptor(
            descriptor: ExtensionDescriptor(id: "z_last", version: 1, capabilities: [.commandInterception]),
            prefix: "Z"
        ))
        registry.registerInterceptor(PrefixInterceptor(
            descriptor: ExtensionDescriptor(id: "a_first", version: 1, capabilities: [.commandInterception]),
            prefix: "A"
        ))
        let doc = NoteDocument(text: "hi", metadata: .empty)
        let ctx = CommandContext(trigger: "test", selectionRange: nil)
        let out = registry.applyInterceptors(
            to: [.replaceText(range: TextRange(start: 0, length: 0), replacement: "x")],
            document: doc,
            context: ctx
        )
        guard case let .replaceText(_, rep) = out.first else {
            return XCTFail("expected replaceText")
        }
        XCTAssertEqual(rep, "ZAx", "a_first runs first (A), then z_last (Z)")
    }
}
