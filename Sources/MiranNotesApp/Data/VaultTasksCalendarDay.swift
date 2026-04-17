import Foundation

/// Calendar-day identity for vault task pages. Storage key is ISO `yyyy-MM-dd` in the vault’s wall-clock calendar.
struct VaultTasksCalendarDay: Hashable, Comparable, Sendable {
    /// Normalized `yyyy-MM-dd`.
    let storageKey: String

    init?(storageKey: String) {
        let trimmed = storageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidStorageKey(trimmed) else { return nil }
        self.storageKey = trimmed
    }

    init(validatedStorageKey: String) {
        precondition(Self.isValidStorageKey(validatedStorageKey))
        self.storageKey = validatedStorageKey
    }

    static func today(calendar: Calendar, referenceDate: Date = Date()) -> VaultTasksCalendarDay {
        let normalized = calendar.startOfDay(for: referenceDate)
        let key = Self.storageKey(forStartOfDay: normalized, calendar: calendar)
        return VaultTasksCalendarDay(validatedStorageKey: key)
    }

    static func storageKey(forStartOfDay startOfDay: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: startOfDay)
        let y = c.year ?? 0
        let m = c.month ?? 0
        let d = c.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    func startOfDayDate(calendar: Calendar) -> Date? {
        var parts = storageKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        return calendar.date(from: c).map { calendar.startOfDay(for: $0) }
    }

    /// Fixed-width `yy/MM/dd` for the vault tasks header (e.g. `26/04/17`).
    func displayShortYYMMDD(calendar: Calendar) -> String {
        guard let date = startOfDayDate(calendar: calendar) else { return storageKey }
        var cal = calendar
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = cal.timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yy/MM/dd"
        return fmt.string(from: date)
    }

    static func < (lhs: VaultTasksCalendarDay, rhs: VaultTasksCalendarDay) -> Bool {
        lhs.storageKey < rhs.storageKey
    }

    private static func isValidStorageKey(_ s: String) -> Bool {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
            parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
            y >= 1, m >= 1, m <= 12, d >= 1, d <= 31
        else { return false }
        return true
    }
}
