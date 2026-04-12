import Foundation

/// Future-facing hook for interactive block chrome (drag handles, per-block menus). No runtime wiring yet; keeps a stable symbol for modules that will extend editor UX.
public protocol BlockChromeInteraction: Sendable {}
