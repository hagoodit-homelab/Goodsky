import Foundation
import Testing
@testable import GoodskyCore

/// Now vs later: the split panels, the on-the-way-out plan, and the one-liner for tight spots.
@Suite struct JacketPhaseTests {
    let cal = Fixtures.calendar

    @Test func sameAllDayHasNoSplit() throws {
        let hourly = Fixtures.hours { _ in .init(feels: 50) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.timing == .allDay)
        #expect(call.now == JacketPhase(verdict: .jacket, start: Fixtures.date(hour: 7), end: Fixtures.date(hour: 19),
                                        minFeelsLikeF: 50))
        #expect(call.later == nil)
        #expect(call.plan == nil)
        #expect(call.splitSummary(at: Fixtures.date(hour: 6), calendar: cal) == nil)
    }

    @Test func fineNowJacketLater() throws {
        let hourly = Fixtures.hours { h in .init(feels: h >= 17 ? 52 : 66) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 9), calendar: cal))
        #expect(call.timing == .later(from: Fixtures.date(hour: 17)))
        #expect(call.now == JacketPhase(verdict: .noJacket, start: Fixtures.date(hour: 9), end: Fixtures.date(hour: 17),
                                        minFeelsLikeF: 66))
        #expect(call.later == JacketPhase(verdict: .jacket, start: Fixtures.date(hour: 17), end: Fixtures.date(hour: 19),
                                          minFeelsLikeF: 52))
        #expect(call.plan == "Bring a jacket for later.")
        #expect(call.splitSummary(at: Fixtures.date(hour: 9), calendar: cal) == "😎 Now · 🧥 5 PM")
    }

    @Test func beforeYouHeadOutTheNowPanelSaysWhen() throws {
        let hourly = Fixtures.hours { h in .init(feels: h >= 17 ? 52 : 66) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        let now = try #require(call.now)
        #expect(now.label(at: Fixtures.date(hour: 6), calendar: cal) == "7 AM")
        #expect(now.label(at: Fixtures.date(hour: 7), calendar: cal) == "Now")
        #expect(call.splitSummary(at: Fixtures.date(hour: 6), calendar: cal) == "😎 7 AM · 🧥 5 PM")
    }

    @Test func jacketNowStashItLater() throws {
        let hourly = Fixtures.hours { h in .init(feels: h < 10 ? 50 : 66) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.timing == .nowOnly(until: Fixtures.date(hour: 10)))
        #expect(call.now?.verdict == .jacket)
        #expect(call.now?.minFeelsLikeF == 50)
        #expect(call.later?.verdict == .noJacket)
        #expect(call.later?.start == Fixtures.date(hour: 10))
        #expect(call.later?.minFeelsLikeF == 66)
        #expect(call.plan == "Wear a jacket out, then stash it.")
    }

    @Test func jacketNowRainJacketLater() throws {
        let hourly = Fixtures.hours { h in
            h >= 15 ? .init(feels: 50, chance: 0.7, amount: 0.05, kind: .rain) : .init(feels: 50)
        }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 6), calendar: cal))
        #expect(call.now?.verdict == .jacket)
        #expect(call.now?.firstWetHour == nil)
        #expect(call.later?.verdict == .rainJacket)
        #expect(call.later?.firstWetHour == Fixtures.date(hour: 15))
        #expect(call.plan == "Wear a jacket, and bring a rain jacket for later.")
        #expect(call.splitSummary(at: Fixtures.date(hour: 6), calendar: cal) == "🧥 7 AM · 🧥☔ 3 PM")
    }

    @Test func coatLaterSaysCoat() throws {
        let hourly = Fixtures.hours { h in .init(feels: h >= 16 ? 40 : 66) }
        let call = try #require(JacketAdvisor.call(hourly: hourly, now: Fixtures.date(hour: 9), calendar: cal))
        #expect(call.later?.verdict == .realCoat)
        #expect(call.plan == "Bring a real coat for later.")
    }

    @Test func oldCachedCallsWithoutPhasesStillDecode() throws {
        // Calls encoded before phases existed have no "now"/"later" keys.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Fixtures.call(.jacket))) as! [String: Any]
        json.removeValue(forKey: "now")
        json.removeValue(forKey: "later")
        let call = try JSONDecoder().decode(JacketCall.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(call.now == nil && call.later == nil && call.plan == nil)
    }
}
