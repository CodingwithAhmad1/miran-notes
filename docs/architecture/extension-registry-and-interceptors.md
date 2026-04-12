# Extension registry and command interceptors

## Registration surfaces

1. **`ExtensionRegistry`** (`MiranNotesCore`) — Typed `CommandInterceptorExtension` / `CommandProducerExtension` with `ExtensionDescriptor`. Prefer this for shipped modules and future plugins.
2. **`AppModel.registerCommandInterceptor`** — Closure-based hooks, primarily for tests and app-internal features. Deregister with `removeCommandInterceptor(_:)`.

## Apply pipeline (`AppModel.apply`)

1. Truncate batch to `CommandPipelineContract.maxCommandsPerBatch`.
2. Build `CommandContext(trigger: "appModel.apply", selectionRange: editorTextSelection)`.
3. `extensionRegistry.applyInterceptors` — interceptors sorted by `descriptor.id` (lexicographic).
4. Local closure interceptors — insertion order in `localCommandInterceptorOrder`.
5. `EditCommandEngine.apply` for each command in sequence.

## Semantics

All interceptors receive the **same** `document` snapshot: the active document **before** any command in the batch is applied. They return a **possibly modified command array**. The document is **not** recomputed between interceptor calls; chaining is **command-list transformation only**.

## Capability checks

Use `ExtensionCompatibility.supports(descriptor:requiredVersion:requiredCapabilities:)` before relying on optional behavior.
