import Foundation

/// Small, deterministic formatters (fixed en_US_POSIX locale so strings are stable in tests and widgets).
public enum Format {
    public static func degrees(_ f: Double) -> String { "\(Int(f.rounded()))°" }

    public static func percent(_ p: Double) -> String { "\(Int((p * 100).rounded()))%" }

    public static func mph(_ v: Double) -> String { "\(Int(v.rounded())) mph" }

    /// "3 PM"
    public static func hour(_ date: Date, calendar: Calendar) -> String {
        formatter("h a", calendar: calendar).string(from: date)
    }

    /// "4:15"
    public static func clock(_ date: Date, calendar: Calendar) -> String {
        formatter("h:mm", calendar: calendar).string(from: date)
    }

    /// "Tue"
    public static func weekday(_ date: Date, calendar: Calendar) -> String {
        formatter("EEE", calendar: calendar).string(from: date)
    }

    private static func formatter(_ pattern: String, calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = pattern
        return f
    }
}
