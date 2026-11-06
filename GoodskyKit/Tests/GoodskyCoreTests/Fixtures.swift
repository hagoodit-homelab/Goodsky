import Foundation
@testable import GoodskyCore

enum Fixtures {
    static let tz = TimeZone(identifier: "America/New_York")!
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    /// 2026-11-06 at the given local hour/minute.
    static func date(hour: Int, minute: Int = 0, day: Int = 6) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// 36 hours of forecast starting at local midnight, built by a per-hour closure.
    static func hours(_ build: (Int) -> HourForecast.Partial) -> [HourForecast] {
        (0..<36).map { i in
            let p = build(i % 24)
            return HourForecast(date: date(hour: 0).addingTimeInterval(TimeInterval(i) * 3600),
                                temperatureF: p.feels, feelsLikeF: p.feels, precipChance: p.chance,
                                precipAmountIn: p.amount, precipKind: p.kind, windMph: p.wind)
        }
    }

    static func minutes(_ build: (Int) -> (chance: Double, mmh: Double), start: Date) -> [MinuteForecast] {
        (0..<60).map { i in
            let v = build(i)
            return MinuteForecast(date: start.addingTimeInterval(TimeInterval(i) * 60),
                                  precipChance: v.chance, intensityMmPerHour: v.mmh)
        }
    }
}

extension HourForecast {
    struct Partial {
        var feels: Double
        var chance: Double = 0
        var amount: Double = 0
        var kind: PrecipKind = .none
        var wind: Double = 5
    }
}

extension Fixtures {
    static func call(_ verdict: JacketVerdict, min: Double = 55, max: Double = 70, wet: Bool = false,
                     chance: Double = 0, kind: PrecipKind = .none, wind: Double = 5,
                     bumped: Bool = false) -> JacketCall {
        JacketCall(verdict: verdict, reason: "Feels like \(Int(min))° at the coldest.",
                   windowStart: date(hour: 7), windowEnd: date(hour: 19), minFeelsLikeF: min,
                   maxFeelsLikeF: max, coldestHour: date(hour: 7), firstWetHour: wet ? date(hour: 15) : nil,
                   peakPrecipChance: chance, precipKind: kind, maxWindMph: wind, windBumped: bumped)
    }
}
