import Foundation

/// The one thing Goodsky exists to answer.
public enum JacketVerdict: String, Codable, Sendable, CaseIterable {
    case noJacket, jacket, realCoat, rainJacket

    public var emoji: String {
        switch self {
        case .noJacket: "😎"
        case .jacket: "🧥"
        case .realCoat: "❄️"
        case .rainJacket: "🧥☔"
        }
    }

    public var title: String {
        switch self {
        case .noJacket: "No jacket"
        case .jacket: "Jacket"
        case .realCoat: "Real coat"
        case .rainJacket: "Rain jacket"
        }
    }

    /// Short form for tight spots (inline complications).
    public var shortTitle: String {
        switch self {
        case .noJacket: "No jacket"
        case .jacket: "Jacket"
        case .realCoat: "Coat"
        case .rainJacket: "Rain jkt"
        }
    }
}

/// The verdict plus the facts behind it.
public struct JacketCall: Codable, Sendable, Equatable {
    public var verdict: JacketVerdict
    /// One line explaining why, e.g. "Rain likely from 3 PM (70%). Feels like 48° at the coldest."
    public var reason: String
    public var windowStart: Date
    public var windowEnd: Date
    public var minFeelsLikeF: Double
    public var maxFeelsLikeF: Double
    public var coldestHour: Date
    /// First hour in the window that counts as wet, if any.
    public var firstWetHour: Date?
    public var peakPrecipChance: Double
    public var precipKind: PrecipKind
    public var maxWindMph: Double
    /// True when wind alone bumped a "no jacket" day to a jacket.
    public var windBumped: Bool
}

public enum JacketAdvisor {
    /// The "out and about" window to judge, given the current time.
    ///
    /// - Before the window starts today: today's full window.
    /// - During the window with at least an hour left: now → window end.
    /// - Otherwise (late evening, overnight): the next 12 hours.
    public static func window(at now: Date, settings: JacketSettings, calendar: Calendar) -> DateInterval {
        let s = settings.sanitized
        let startOfDay = calendar.startOfDay(for: now)
        let start = startOfDay.addingTimeInterval(TimeInterval(s.windowStartHour) * 3600)
        let end = startOfDay.addingTimeInterval(TimeInterval(s.windowEndHour) * 3600)
        if now < start {
            return DateInterval(start: start, end: end)
        }
        if now < end.addingTimeInterval(-3600) {
            return DateInterval(start: now, end: end)
        }
        return DateInterval(start: now, duration: 12 * 3600)
    }

    /// Make the Jacket Call for the rest of today. Returns `nil` when the forecast has no hours in the window.
    public static func call(hourly: [HourForecast], now: Date, settings: JacketSettings = .default,
                            calendar: Calendar = .current) -> JacketCall? {
        let s = settings.sanitized
        let window = window(at: now, settings: s, calendar: calendar)
        let hours = hourly
            .filter { $0.date < window.end && $0.date.addingTimeInterval(3600) > window.start }
            .sorted { $0.date < $1.date }
        guard let coldest = hours.min(by: { $0.feelsLikeF < $1.feelsLikeF }),
              let warmest = hours.max(by: { $0.feelsLikeF < $1.feelsLikeF }) else { return nil }

        let wetHours = hours.filter {
            $0.precipChance >= s.rainChanceThreshold && $0.precipAmountIn >= s.minRainAmountIn
        }
        let firstWet = wetHours.first
        let peakChance = hours.map(\.precipChance).max() ?? 0
        let maxWind = hours.map(\.windMph).max() ?? 0
        let minFeels = coldest.feelsLikeF
        let wetKind = wetHours.max(by: { $0.precipChance < $1.precipChance })?.precipKind ?? .none
        let frozen = wetKind.isFrozen

        var verdict: JacketVerdict
        var windBumped = false
        if firstWet != nil {
            // Rain beats jacket. Frozen stuff on a cold day means a real coat, not a shell.
            verdict = (frozen && minFeels < s.jacketBelowF) ? .realCoat : .rainJacket
        } else if minFeels < s.coatBelowF {
            verdict = .realCoat
        } else if minFeels < s.jacketBelowF {
            verdict = .jacket
        } else if maxWind >= s.windyMph && minFeels < s.jacketBelowF + s.windyMarginF {
            verdict = .jacket
            windBumped = true
        } else {
            verdict = .noJacket
        }

        let reason = reasonLine(verdict: verdict, window: window, coldest: coldest, warmest: warmest,
                                firstWet: firstWet, wetKind: wetKind, maxWind: maxWind,
                                windBumped: windBumped, settings: s, calendar: calendar)

        return JacketCall(verdict: verdict, reason: reason, windowStart: window.start, windowEnd: window.end,
                          minFeelsLikeF: minFeels, maxFeelsLikeF: warmest.feelsLikeF,
                          coldestHour: coldest.date, firstWetHour: firstWet?.date,
                          peakPrecipChance: peakChance, precipKind: wetKind,
                          maxWindMph: maxWind, windBumped: windBumped)
    }

    // MARK: - Reason text

    static func reasonLine(verdict: JacketVerdict, window: DateInterval, coldest: HourForecast,
                           warmest: HourForecast, firstWet: HourForecast?, wetKind: PrecipKind,
                           maxWind: Double, windBumped: Bool, settings: JacketSettings,
                           calendar: Calendar) -> String {
        let lo = Format.degrees(coldest.feelsLikeF)
        let hi = Format.degrees(warmest.feelsLikeF)

        if let wet = firstWet {
            let noun = wetKind.noun.capitalizedFirst
            let pct = Format.percent(wet.precipChance)
            let when = wet.date <= window.start
                ? "\(noun) likely when you head out (\(pct))."
                : "\(noun) likely from \(Format.hour(wet.date, calendar: calendar)) (\(pct))."
            if coldest.feelsLikeF < settings.coatBelowF && verdict == .rainJacket {
                return "\(when) Feels like \(lo) at the coldest, so layer up under it."
            }
            return "\(when) Feels like \(lo) at the coldest."
        }

        switch verdict {
        case .noJacket:
            return lo == hi
                ? "Feels like \(lo) and it stays dry."
                : "Feels like \(lo)–\(hi) and it stays dry."
        case .jacket where windBumped:
            return "Feels like \(lo), but wind up to \(Format.mph(maxWind)) makes it feel worse."
        case .jacket, .realCoat:
            var line = "Feels like \(lo) at its coldest, around \(Format.hour(coldest.date, calendar: calendar))."
            if maxWind >= settings.windyMph { line += " Wind up to \(Format.mph(maxWind))." }
            return line
        case .rainJacket:
            return "Feels like \(lo) at the coldest."
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
