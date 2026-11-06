import Foundation

/// Simplified three-step intensity scale (shared with the future radar color scale).
public enum PrecipIntensity: String, Codable, Sendable, Comparable, CaseIterable {
    case light, moderate, heavy

    /// Standard-ish rain-rate bands in mm/h.
    public init(mmPerHour: Double) {
        switch mmPerHour {
        case ..<2.5: self = .light
        case ..<7.6: self = .moderate
        default: self = .heavy
        }
    }

    public var adjective: String { rawValue.capitalizedFirst }

    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

public struct PrecipSummary: Codable, Sendable, Equatable {
    public var text: String
    public var isPrecipitatingNow: Bool
    public var startsAt: Date?
    public var endsAt: Date?
    public var intensity: PrecipIntensity?
    public var kind: PrecipKind
}

/// Turns WeatherKit's minute-by-minute forecast into one plain-English sentence.
public enum PrecipSummarizer {
    /// A minute counts as wet at or above both of these.
    public static let wetChance = 0.4
    public static let wetIntensityMmPerHour = 0.1
    /// Dry minutes in a row needed to call an episode over (avoids flicker).
    public static let dryRunToEnd = 5

    public static func isWet(_ m: MinuteForecast) -> Bool {
        m.precipChance >= wetChance && m.intensityMmPerHour >= wetIntensityMmPerHour
    }

    /// Summary from minute data. Returns `nil` if there's no usable minute data.
    public static func summarize(minutes: [MinuteForecast], now: Date, calendar: Calendar) -> PrecipSummary? {
        let ms = minutes.filter { $0.date >= now.addingTimeInterval(-60) }.sorted { $0.date < $1.date }
        guard let first = ms.first else { return nil }
        let wet = ms.map(isWet)

        // End of an episode starting at `from`: first index where `dryRunToEnd` dry minutes in a row begin.
        func episodeEnd(from: Int) -> Int? {
            var i = from
            while i < ms.count {
                if !wet[i] {
                    let run = wet[i..<min(i + dryRunToEnd, ms.count)]
                    if run.count == dryRunToEnd && !run.contains(true) { return i }
                }
                i += 1
            }
            return nil
        }

        func describe(_ range: Range<Int>) -> (PrecipIntensity, PrecipKind) {
            let slice = ms[range]
            let peak = slice.map(\.intensityMmPerHour).max() ?? 0
            let kind = slice.first(where: isWet)?.precipKind ?? .rain
            return (PrecipIntensity(mmPerHour: peak), kind == .none ? .rain : kind)
        }

        if wet[0] {
            let end = episodeEnd(from: 0)
            let (intensity, kind) = describe(0..<(end ?? ms.count))
            let lead = "\(intensity.adjective) \(kind.noun) now"
            guard let end else {
                return PrecipSummary(text: "\(lead), and it's not stopping this hour.", isPrecipitatingNow: true,
                                     startsAt: first.date, endsAt: nil, intensity: intensity, kind: kind)
            }
            let endDate = ms[end].date
            return PrecipSummary(text: "\(lead), stopping around \(Format.clock(endDate, calendar: calendar)).",
                                 isPrecipitatingNow: true, startsAt: first.date, endsAt: endDate,
                                 intensity: intensity, kind: kind)
        }

        guard let start = wet.firstIndex(of: true) else {
            return PrecipSummary(text: "No rain for the next hour.", isPrecipitatingNow: false,
                                 startsAt: nil, endsAt: nil, intensity: nil, kind: .none)
        }
        let end = episodeEnd(from: start)
        let (intensity, kind) = describe(start..<(end ?? ms.count))
        let startDate = ms[start].date
        let lead = "\(intensity.adjective) \(kind.noun) reaches you around \(Format.clock(startDate, calendar: calendar))"
        guard let end else {
            return PrecipSummary(text: "\(lead) and sticks around past the hour.", isPrecipitatingNow: false,
                                 startsAt: startDate, endsAt: nil, intensity: intensity, kind: kind)
        }
        let endDate = ms[end].date
        let minutesLong = endDate.timeIntervalSince(startDate) / 60
        return PrecipSummary(text: "\(lead), \(durationPhrase(minutes: minutesLong)).", isPrecipitatingNow: false,
                             startsAt: startDate, endsAt: endDate, intensity: intensity, kind: kind)
    }

    /// "lasts about 40 minutes" (rounded to 5), or "lasts only a few minutes".
    static func durationPhrase(minutes: Double) -> String {
        if minutes < 8 { return "lasts only a few minutes" }
        let rounded = max(5, Int((minutes / 5).rounded()) * 5)
        return "lasts about \(rounded) minutes"
    }

    /// For places without minute data: use the next hourly slot.
    public static func fallback(hourly: [HourForecast], now: Date) -> PrecipSummary {
        let next = hourly
            .filter { $0.date.addingTimeInterval(3600) > now }
            .min(by: { $0.date < $1.date })
        guard let next, next.precipChance >= 0.15 else {
            return PrecipSummary(text: "No rain expected in the next hour.", isPrecipitatingNow: false,
                                 startsAt: nil, endsAt: nil, intensity: nil, kind: .none)
        }
        let kind = next.precipKind == .none ? PrecipKind.rain : next.precipKind
        return PrecipSummary(text: "Next hour: \(Format.percent(next.precipChance)) chance of \(kind.noun).",
                             isPrecipitatingNow: false, startsAt: nil, endsAt: nil, intensity: nil, kind: kind)
    }

    /// Minute summary when available, hourly fallback otherwise.
    public static func summary(for snapshot: WeatherSnapshot, now: Date, calendar: Calendar) -> PrecipSummary {
        if let minutes = snapshot.minutes,
           let s = summarize(minutes: minutes, now: now, calendar: calendar) {
            return s
        }
        return fallback(hourly: snapshot.hourly, now: now)
    }
}
