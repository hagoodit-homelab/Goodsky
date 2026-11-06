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

/// When during the window the verdict actually applies.
///
/// The verdict is always "what to bring" for the whole window. Timing says whether you need it
/// the moment you step out, only later, or only for the first stretch.
public enum JacketTiming: Codable, Sendable, Equatable {
    /// Same need the whole time (or no need at all).
    case allDay
    /// Fine without it now; you'll want it from `from`.
    case later(from: Date)
    /// Need it now; you can ditch it from `until` on.
    case nowOnly(until: Date)
    /// Need `now` right away, then something heavier/different (the verdict) from `at`.
    case stepUp(now: JacketVerdict, at: Date)
}

/// The verdict plus the facts behind it.
public struct JacketCall: Codable, Sendable, Equatable {
    /// What to bring for the whole window.
    public var verdict: JacketVerdict
    /// Whether you need it right away or only later. See `JacketTiming`.
    public var timing: JacketTiming = .allDay
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

    /// Headline for the hero spot: "Jacket", "Jacket later", "Jacket for now".
    public var headline: String { verdict.title + timingSuffix }

    /// Short headline for tight spots: "Rain jkt later".
    public var shortHeadline: String { verdict.shortTitle + timingSuffix }

    private var timingSuffix: String {
        guard verdict != .noJacket else { return "" }
        switch timing {
        case .later: return " later"
        case .nowOnly: return " for now"
        case .allDay, .stepUp: return ""
        }
    }
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

    /// How long "now" is: the first stretch of the window, when you're stepping out.
    public static let nowSpan: TimeInterval = 2 * 3600
    /// A "ditch it by" call needs at least this much jacket-free time left in the window to be worth saying.
    static let minFreeTail: TimeInterval = 2 * 3600

    /// Make the Jacket Call for the rest of today. Returns `nil` when the forecast has no hours in the window.
    public static func call(hourly: [HourForecast], now: Date, settings: JacketSettings = .default,
                            calendar: Calendar = .current) -> JacketCall? {
        let s = settings.sanitized
        let window = window(at: now, settings: s, calendar: calendar)
        let hours = hourly
            .filter { $0.date < window.end && $0.date.addingTimeInterval(3600) > window.start }
            .sorted { $0.date < $1.date }
        guard let all = assess(hours, settings: s) else { return nil }

        let timing = timing(hours: hours, overall: all.verdict, window: window, settings: s)
        let reason = reasonLine(verdict: all.verdict, timing: timing, headingOut: now < window.start,
                                window: window, coldest: all.coldest, warmest: all.warmest,
                                firstWet: all.firstWet, wetKind: all.wetKind, maxWind: all.maxWind,
                                windBumped: all.windBumped, settings: s, calendar: calendar)

        return JacketCall(verdict: all.verdict, timing: timing, reason: reason,
                          windowStart: window.start, windowEnd: window.end,
                          minFeelsLikeF: all.coldest.feelsLikeF, maxFeelsLikeF: all.warmest.feelsLikeF,
                          coldestHour: all.coldest.date, firstWetHour: all.firstWet?.date,
                          peakPrecipChance: all.peakChance, precipKind: all.wetKind,
                          maxWindMph: all.maxWind, windBumped: all.windBumped)
    }

    // MARK: - Verdict

    /// The facts and verdict for a run of hours. All temperature decisions use feels-like
    /// (WeatherKit's apparent temperature, which already folds in wind chill and humidity).
    struct Assessment {
        var verdict: JacketVerdict
        var windBumped: Bool
        var coldest: HourForecast
        var warmest: HourForecast
        var firstWet: HourForecast?
        var wetKind: PrecipKind
        var peakChance: Double
        var maxWind: Double
    }

    static func assess(_ hours: [HourForecast], settings s: JacketSettings) -> Assessment? {
        guard let coldest = hours.min(by: { $0.feelsLikeF < $1.feelsLikeF }),
              let warmest = hours.max(by: { $0.feelsLikeF < $1.feelsLikeF }) else { return nil }

        let wetHours = hours.filter { isWet($0, s) }
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
        return Assessment(verdict: verdict, windBumped: windBumped, coldest: coldest, warmest: warmest,
                          firstWet: firstWet, wetKind: wetKind, peakChance: peakChance, maxWind: maxWind)
    }

    static func isWet(_ h: HourForecast, _ s: JacketSettings) -> Bool {
        h.precipChance >= s.rainChanceThreshold && h.precipAmountIn >= s.minRainAmountIn
    }

    /// The verdict for a single hour.
    static func verdict(for hour: HourForecast, settings s: JacketSettings) -> JacketVerdict {
        assess([hour], settings: s)?.verdict ?? .noJacket
    }

    // MARK: - Timing

    /// Now vs later: compares the first `nowSpan` of the window against the hour-by-hour need.
    static func timing(hours: [HourForecast], overall: JacketVerdict, window: DateInterval,
                       settings s: JacketSettings) -> JacketTiming {
        guard overall != .noJacket else { return .allDay }
        let nowEnd = window.start.addingTimeInterval(nowSpan)
        let nowHours = hours.filter { $0.date < nowEnd }
        let laterHours = hours.filter { $0.date >= nowEnd }
        // Window too short to have a "later" (e.g. last hour of the day): nothing to split.
        guard !laterHours.isEmpty, let nowVerdict = assess(nowHours, settings: s)?.verdict else { return .allDay }

        let perHour = hours.map { (hour: $0, verdict: verdict(for: $0, settings: s)) }

        // Fine right now; the need shows up later.
        if nowVerdict == .noJacket {
            guard let first = perHour.first(where: { $0.hour.date >= nowEnd && $0.verdict != .noJacket })
            else { return .allDay }
            return .later(from: max(first.hour.date, window.start))
        }

        // Need something now, and something heavier/different later (jacket now, rain from 3 PM).
        if nowVerdict != overall,
           let first = perHour.first(where: { $0.hour.date >= nowEnd && $0.verdict == overall }) {
            return .stepUp(now: nowVerdict, at: first.hour.date)
        }

        // Need it now, but it warms up / dries out and stays that way.
        if let lastNeed = perHour.last(where: { $0.verdict != .noJacket }) {
            let freeFrom = lastNeed.hour.date.addingTimeInterval(3600)
            if window.end.timeIntervalSince(freeFrom) >= minFreeTail {
                return .nowOnly(until: freeFrom)
            }
        }
        return .allDay
    }

    // MARK: - Reason text

    static func reasonLine(verdict: JacketVerdict, timing: JacketTiming, headingOut: Bool,
                           window: DateInterval, coldest: HourForecast,
                           warmest: HourForecast, firstWet: HourForecast?, wetKind: PrecipKind,
                           maxWind: Double, windBumped: Bool, settings: JacketSettings,
                           calendar: Calendar) -> String {
        let base = conditionsLine(verdict: verdict, window: window, coldest: coldest, warmest: warmest,
                                  firstWet: firstWet, wetKind: wetKind, maxWind: maxWind,
                                  windBumped: windBumped, settings: settings, calendar: calendar)
        let now = headingOut ? "when you head out" : "now"
        let item = verdict == .realCoat ? "the coat" : "it"
        switch timing {
        case .allDay:
            return base
        case .later(let from):
            // The rain line already says "from 3 PM"; don't say the time twice.
            if let wet = firstWet, wet.date == from {
                return "Fine without one \(now), but bring \(item). \(base)"
            }
            return "Fine without one \(now), but you'll want \(item) by \(Format.hour(from, calendar: calendar)). \(base)"
        case .nowOnly(let until):
            return "Wear \(item) \(now); you can ditch it by \(Format.hour(until, calendar: calendar)). \(base)"
        case .stepUp(let nowVerdict, let at):
            return "\(nowVerdict.title) \(now), \(verdict.title.lowercased()) by \(Format.hour(at, calendar: calendar)). \(base)"
        }
    }

    /// The weather facts behind the verdict, without timing.
    static func conditionsLine(verdict: JacketVerdict, window: DateInterval, coldest: HourForecast,
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
