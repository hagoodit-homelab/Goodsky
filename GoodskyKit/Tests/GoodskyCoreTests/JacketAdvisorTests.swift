import Foundation
import Testing
@testable import GoodskyCore

@Suite struct JacketAdvisorTests {
    let cal = Fixtures.calendar

    // MARK: Window

    @Test func windowBeforeStartIsFullDay() {
        let w = JacketAdvisor.window(at: Fixtures.date(hour: 5), settings: .default, calendar: cal)
        #expect(w.start == Fixtures.date(hour: 7))
        #expect(w.end == Fixtures.date(hour: 19))
    }

    @Test func windowMidDayStartsNow() {
        let now = Fixtures.date(hour: 13, minute: 20)
        let w = JacketAdvisor.window(at: now, settings: .default, calendar: cal)
        #expect(w.start == now)
        #expect(w.end == Fixtures.date(hour: 19))
    }

    @Test func windowLateEveningIsNextTwelveHours() {
        let now = Fixtures.date(hour: 18, minute: 30)
        let w = JacketAdvisor.window(at: now, settings: .default, calendar: cal)
        #expect(w.start == now)
        #expect(w.duration == 12 * 3600)
    }

    // MARK: Verdicts

    @Test func warmAndDryIsNoJacket() throws {
        let hourly = Fixtures.hours { _ in .init(feels: 72) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.verdict == .noJacket)
        #expect(call.reason == "Feels like 72° and it stays dry.")
    }

    @Test func coolMorningIsJacket() throws {
        let hourly = Fixtures.hours { h in .init(feels: h < 10 ? 50 : 66) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.verdict == .jacket)
        #expect(call.minFeelsLikeF == 50)
        #expect(call.timing == .nowOnly(until: Fixtures.date(hour: 10)))
        #expect(call.headline == "Jacket for now")
        #expect(call.reason == "Wear it when you head out; you can ditch it by 10 AM. Feels like 50° at its coldest, around 7 AM.")
    }

    @Test func coldIsRealCoat() throws {
        let hourly = Fixtures.hours { _ in .init(feels: 30) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.verdict == .realCoat)
    }

    @Test func rainBeatsJacket() throws {
        let hourly = Fixtures.hours { h in
            h >= 15 ? .init(feels: 50, chance: 0.7, amount: 0.05, kind: .rain) : .init(feels: 50)
        }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.verdict == .rainJacket)
        #expect(call.firstWetHour == Fixtures.date(hour: 15))
        #expect(call.timing == .stepUp(now: .jacket, at: Fixtures.date(hour: 15)))
        #expect(call.headline == "Rain jacket")
        #expect(call.reason == "Jacket when you head out, rain jacket by 3 PM. Rain likely from 3 PM (70%). Feels like 50° at the coldest.")
    }

    @Test func rainAlreadyFallingSaysWhenYouHeadOut() throws {
        let hourly = Fixtures.hours { _ in .init(feels: 66, chance: 0.9, amount: 0.1, kind: .rain) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.reason.hasPrefix("Rain likely when you head out (90%)."))
    }

    @Test func lowChanceOrTraceAmountIsNotRain() throws {
        let lowChance = Fixtures.hours { _ in .init(feels: 70, chance: 0.3, amount: 0.1, kind: .rain) }
        let trace = Fixtures.hours { _ in .init(feels: 70, chance: 0.8, amount: 0.001, kind: .rain) }
        #expect(JacketAdvisor.call(hourly: lowChance, now: Fixtures.date(hour: 6), calendar: cal)?.verdict == .noJacket)
        #expect(JacketAdvisor.call(hourly: trace, now: Fixtures.date(hour: 6), calendar: cal)?.verdict == .noJacket)
    }

    @Test func rainOutsideWindowIsIgnored() throws {
        let hourly = Fixtures.hours { h in
            h >= 21 ? .init(feels: 70, chance: 0.9, amount: 0.2, kind: .rain) : .init(feels: 70)
        }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.verdict == .noJacket)
    }

    @Test func coldRainSaysLayerUp() throws {
        let hourly = Fixtures.hours { _ in .init(feels: 38, chance: 0.6, amount: 0.05, kind: .rain) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.verdict == .rainJacket)
        #expect(call.reason.hasSuffix("so layer up under it."))
    }

    @Test func snowOnColdDayIsRealCoat() throws {
        let hourly = Fixtures.hours { _ in .init(feels: 25, chance: 0.8, amount: 0.1, kind: .snow) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.verdict == .realCoat)
        #expect(call.reason.hasPrefix("Snow likely"))
    }

    @Test func windBumpsBorderlineDay() throws {
        let hourly = Fixtures.hours { _ in .init(feels: 65, wind: 24) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.verdict == .jacket)
        #expect(call.windBumped)
        #expect(call.reason == "Feels like 65°, but wind up to 24 mph makes it feel worse.")
    }

    @Test func windDoesNotBumpWarmDay() throws {
        let hourly = Fixtures.hours { _ in .init(feels: 78, wind: 30) }
        #expect(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal)?.verdict == .noJacket)
    }

    @Test func customThresholdsApply() throws {
        let hourly = Fixtures.hours { _ in .init(feels: 58) }
        var s = JacketSettings.default
        s.jacketBelowF = 55
        #expect(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), settings: s, calendar: cal)?.verdict == .noJacket)
    }

    // MARK: Now vs later

    @Test func steadyColdIsAllDay() throws {
        let hourly = Fixtures.hours { _ in .init(feels: 50) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.timing == .allDay)
        #expect(call.headline == "Jacket")
        #expect(call.reason == "Feels like 50° at its coldest, around 7 AM.")
    }

    @Test func warmNowColdEveningIsJacketLater() throws {
        let hourly = Fixtures.hours { h in .init(feels: h >= 17 ? 54 : 70) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 12), calendar: cal))
        #expect(call.verdict == .jacket)
        #expect(call.timing == .later(from: Fixtures.date(hour: 17)))
        #expect(call.headline == "Jacket later")
        #expect(call.shortHeadline == "Jacket later")
        #expect(call.reason == "Fine without one now, but you'll want it by 5 PM. Feels like 54° at its coldest, around 5 PM.")
    }

    @Test func dryNowRainLaterDoesNotRepeatTheTime() throws {
        let hourly = Fixtures.hours { h in
            h >= 15 ? .init(feels: 70, chance: 0.7, amount: 0.05, kind: .rain) : .init(feels: 70)
        }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 9), calendar: cal))
        #expect(call.verdict == .rainJacket)
        #expect(call.timing == .later(from: Fixtures.date(hour: 15)))
        #expect(call.headline == "Rain jacket later")
        #expect(call.reason == "Fine without one now, but bring it. Rain likely from 3 PM (70%). Feels like 70° at the coldest.")
    }

    @Test func coldLaterSaysTheCoat() throws {
        let hourly = Fixtures.hours { h in .init(feels: h >= 16 ? 40 : 66) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.verdict == .realCoat)
        #expect(call.timing == .later(from: Fixtures.date(hour: 16)))
        #expect(call.reason.hasPrefix("Fine without one when you head out, but you'll want the coat by 4 PM."))
    }

    @Test func coldMorningAndEveningIsAllDay() throws {
        // Cold at both ends: keep it with you even though midday is warm.
        let hourly = Fixtures.hours { h in .init(feels: (h < 10 || h >= 17) ? 50 : 68) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.timing == .allDay)
    }

    @Test func needEndingNearWindowEndIsAllDay() throws {
        // Only an hour of jacket-free time left: not worth a "ditch it" call.
        let hourly = Fixtures.hours { h in .init(feels: h < 18 ? 50 : 66) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.timing == .allDay)
    }

    @Test func timingUsesFeelsLikeNotAirTemp() throws {
        // Air temp is a mild 64° all day, but wind chill drags feels-like to 50° in the evening.
        let hourly = (0..<36).map { i -> HourForecast in
            let h = i % 24
            return HourForecast(date: Fixtures.date(hour: 0).addingTimeInterval(TimeInterval(i) * 3600),
                                temperatureF: 64, feelsLikeF: h >= 17 ? 50 : 64,
                                precipChance: 0, precipAmountIn: 0, precipKind: .none, windMph: 5)
        }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 12), calendar: cal))
        #expect(call.verdict == .jacket)
        #expect(call.timing == .later(from: Fixtures.date(hour: 17)))
    }

    @Test func lastHourOfWindowHasNoLater() throws {
        let hourly = Fixtures.hours { h in .init(feels: h >= 18 ? 50 : 70) }
        // 17:30: window is now → 19:00, entirely inside the "now" span.
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 17, minute: 30), calendar: cal))
        #expect(call.timing == .allDay)
    }

    @Test func noJacketHasNoTimingSuffix() throws {
        let hourly = Fixtures.hours { _ in .init(feels: 72) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.timing == .allDay)
        #expect(call.headline == "No jacket")
    }

    @Test func emptyForecastIsNil() {
        #expect(JacketAdvisor.call(hourly: [], now: Fixtures.date(hour: 6), calendar: cal) == nil)
    }

    @Test func sanitizedFixesInvertedSettings() {
        let s = JacketSettings(jacketBelowF: 50, coatBelowF: 60, windowStartHour: 20, windowEndHour: 8).sanitized
        #expect(s.coatBelowF == 50)
        #expect(s.windowEndHour == 21)
    }
}
