import Foundation

/// User-tunable thresholds for the Jacket Call. Defaults are guesses; Josh tunes them in Settings.
public struct JacketSettings: Codable, Sendable, Equatable {
    /// Coldest feels-like in the window below this → jacket.
    public var jacketBelowF: Double
    /// Coldest feels-like in the window below this → real coat.
    public var coatBelowF: Double
    /// Any hour with at least this precip chance (and a meaningful amount) → rain jacket.
    public var rainChanceThreshold: Double
    /// Minimum expected hourly amount (inches) for a wet hour to count.
    public var minRainAmountIn: Double
    /// Sustained wind at or above this makes "no jacket" borderline days a jacket day.
    public var windyMph: Double
    /// How close (°F) to the jacket threshold a windy day must be to bump it to a jacket.
    public var windyMarginF: Double
    /// "Out and about" window, local hours (0–23). End is exclusive.
    public var windowStartHour: Int
    public var windowEndHour: Int

    public init(jacketBelowF: Double = 62, coatBelowF: Double = 45, rainChanceThreshold: Double = 0.4,
                minRainAmountIn: Double = 0.01, windyMph: Double = 20, windyMarginF: Double = 8,
                windowStartHour: Int = 7, windowEndHour: Int = 19) {
        self.jacketBelowF = jacketBelowF
        self.coatBelowF = coatBelowF
        self.rainChanceThreshold = rainChanceThreshold
        self.minRainAmountIn = minRainAmountIn
        self.windyMph = windyMph
        self.windyMarginF = windyMarginF
        self.windowStartHour = windowStartHour
        self.windowEndHour = windowEndHour
    }

    public static let `default` = JacketSettings()

    /// Clamp nonsense combinations (coat above jacket, inverted window) back into something usable.
    public var sanitized: JacketSettings {
        var s = self
        s.coatBelowF = min(s.coatBelowF, s.jacketBelowF)
        s.rainChanceThreshold = min(max(s.rainChanceThreshold, 0.05), 1)
        s.minRainAmountIn = max(s.minRainAmountIn, 0)
        s.windowStartHour = min(max(s.windowStartHour, 0), 23)
        s.windowEndHour = min(max(s.windowEndHour, s.windowStartHour + 1), 24)
        return s
    }
}
