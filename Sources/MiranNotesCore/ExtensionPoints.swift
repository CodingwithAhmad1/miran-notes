import Foundation

// MARK: - Phase 6 — documented extension hooks

/// Placeholder for a future **rich inline** model (beyond plain UTF-16 + sidecar spans). Implementations would define a canonical serialization independent of `NSTextView` quirks.
public protocol RichInlineCanonicalRepresentable: Sendable {
    associatedtype CanonicalSnapshot: Equatable & Sendable
    var canonicalSnapshot: CanonicalSnapshot { get }
}

/// Outline / nested blocks are not first-class yet; this tags future tree-shaped block hierarchies vs the flat `[Block]` list today.
public enum TreeBlockStructurePlaceholder: Sendable {
    case flatListOnly
    case futureNestedOutline
}

/// Heavy structured artifacts (tables, databases) may need **auxiliary files** or dedicated sidecar sections; this documents intent without prescribing storage.
public enum StructuredArtifactPlaceholder: Sendable {
    case table
    case embeddedDatabase
}

/// Sync and multi-device transport are **non-goals** for the core editor today; this enum exists so roadmap docs can refer to a single type name.
public enum SyncTransportRoadmap: Sendable {
    case localVaultOnly
    case futureNetworkTransport
}

/// Runtime wiring lives in `ExtensionRegistry`; these placeholders remain as durable roadmap anchors used in docs.
