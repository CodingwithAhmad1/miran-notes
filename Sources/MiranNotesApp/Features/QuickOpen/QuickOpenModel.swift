import Foundation
import Observation

/// State for the centered quick-open palette (⌘P). Owned by ``AppModel``; results come from
/// `AppModel.quickOpenResults(query:)` so ranking matches vault search.
@MainActor
@Observable
final class QuickOpenModel {
    var isPresented = false
    var query = ""
    var highlightedIndex = 0

    func present() {
        query = ""
        highlightedIndex = 0
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }

    func toggle() {
        if isPresented { dismiss() } else { present() }
    }
}
