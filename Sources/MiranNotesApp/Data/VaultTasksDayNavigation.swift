import Foundation

enum VaultTasksDayNavigation {
    /// Nearest day strictly before `selected` that exists in `knownSorted` (ascending).
    static func previous(before selected: VaultTasksCalendarDay, knownSorted: [VaultTasksCalendarDay]) -> VaultTasksCalendarDay? {
        knownSorted.last { $0 < selected }
    }

    /// Nearest day strictly after `selected` that exists in `knownSorted` (ascending).
    static func next(after selected: VaultTasksCalendarDay, knownSorted: [VaultTasksCalendarDay]) -> VaultTasksCalendarDay? {
        knownSorted.first { $0 > selected }
    }
}
