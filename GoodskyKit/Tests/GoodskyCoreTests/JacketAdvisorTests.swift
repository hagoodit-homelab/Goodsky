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
        #expect(call.reason == "Feels like 50° at its coldest, around 7 AM.")
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
        #expect(call.reason == "Rain likely from 3 PM (70%). Feels like 50° at the coldest.")
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

    @Test func emptyForecastIsNil() {
        #expect(JacketAdvisor.call(hourly: [], now: Fixtures.date(hour: 6), calendar: cal) == nil)
    }

    @Test func sanitizedFixesInvertedSettings() {
        let s = JacketSettings(jacketBelowF: 50, coatBelowF: 60, windowStartHour: 20, windowEndHour: 8).sanitized
        #expect(s.coatBelowF == 50)
        #expect(s.windowEndHour == 21)
    }
}
