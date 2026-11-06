import Foundation
import Testing
@testable import GoodskyCore

@Suite struct ThresholdTunerTests {
    let s = JacketSettings.default   // jacket < 62, coat < 45, rain 40%, windy 20

    @Test func thumbsUpChangesNothing() {
        let r = ThresholdTuner.apply(.right, to: Fixtures.call(.noJacket, min: 65), settings: s)
        #expect(r.settings == s)
        #expect(r.changes.isEmpty)
    }

    @Test func coldOnNoJacketDayRaisesJacketThreshold() {
        // Feels 66°, said no jacket, he was cold. Target 67, gap 5 → step 2.5 → 64.5 → rounds to 65.
        let r = ThresholdTuner.apply(.tooCold, to: Fixtures.call(.noJacket, min: 66), settings: s)
        #expect(r.settings.jacketBelowF == 65)
        #expect(r.settings.coatBelowF == 45)
        #expect(r.changes == ["Jacket below 62° → 65°"])
    }

    @Test func stepIsCapped() {
        let r = ThresholdTuner.apply(.tooCold, to: Fixtures.call(.noJacket, min: 79), settings: s)
        #expect(r.settings.jacketBelowF == 66)   // +4 max
    }

    @Test func stepHasAFloor() {
        let r = ThresholdTuner.apply(.tooCold, to: Fixtures.call(.noJacket, min: 62), settings: s)
        #expect(r.settings.jacketBelowF == 63)   // gap 1 → step 1
    }

    @Test func coldOnJacketDayRaisesCoatThreshold() {
        let r = ThresholdTuner.apply(.tooCold, to: Fixtures.call(.jacket, min: 50), settings: s)
        #expect(r.settings.coatBelowF == 48)     // target 51, gap 6 → +3
        #expect(r.settings.jacketBelowF == 62)
    }

    @Test func coatNeverPassesJacket() {
        var tight = s
        tight.coatBelowF = 60
        let r = ThresholdTuner.apply(.tooCold, to: Fixtures.call(.jacket, min: 61), settings: tight)
        #expect(r.settings.coatBelowF <= r.settings.jacketBelowF)
    }

    @Test func warmOnJacketDayLowersJacketThreshold() {
        let r = ThresholdTuner.apply(.tooWarm, to: Fixtures.call(.jacket, min: 58), settings: s)
        #expect(r.settings.jacketBelowF == 60)   // target 57, gap 5 → -2.5 → 59.5 → 60
    }

    @Test func warmOnCoatDayLowersCoatThreshold() {
        let r = ThresholdTuner.apply(.tooWarm, to: Fixtures.call(.realCoat, min: 40), settings: s)
        #expect(r.settings.coatBelowF == 42)     // target 39, gap 6 → -3
    }

    @Test func warmOnWindBumpedDayRaisesWindThreshold() {
        let r = ThresholdTuner.apply(.tooWarm, to: Fixtures.call(.jacket, min: 66, wind: 22, bumped: true), settings: s)
        #expect(r.settings.windyMph == 22)
        #expect(r.settings.jacketBelowF == 62)
    }

    @Test func rainFeedbackMovesRainThreshold() {
        let wet = ThresholdTuner.apply(.gotWet, to: Fixtures.call(.jacket, chance: 0.3), settings: s)
        #expect(wet.settings.rainChanceThreshold == 0.35)
        let dry = ThresholdTuner.apply(.stayedDry, to: Fixtures.call(.rainJacket, wet: true, chance: 0.5), settings: s)
        #expect(dry.settings.rainChanceThreshold == 0.45)
        #expect(dry.changes == ["Rain jacket at 40% → 45%"])
    }

    @Test func limitsHold() {
        var edge = s
        edge.rainChanceThreshold = 0.9
        let r = ThresholdTuner.apply(.stayedDry, to: Fixtures.call(.rainJacket, wet: true, chance: 0.95), settings: edge)
        #expect(r.settings.rainChanceThreshold == 0.9)
        #expect(r.changes.isEmpty)
        #expect(r.message.contains("limit"))
    }

    @Test func consistentFeedbackConvergesInAboutAWeek() {
        // He keeps saying 68° "no jacket" days are cold.
        var cur = s
        for _ in 0..<7 {
            cur = ThresholdTuner.apply(.tooCold, to: Fixtures.call(.noJacket, min: 68), settings: cur).settings
        }
        #expect(cur.jacketBelowF == 69)
        #expect(JacketAdvisor.call(hourly: Fixtures.hours { _ in .init(feels: 68) }, now: Fixtures.date(hour: 6),
                                   settings: cur, calendar: Fixtures.calendar)?.verdict == .jacket)
    }

    @Test func complaintsFitTheVerdict() {
        #expect(JacketFeedback.complaints(for: Fixtures.call(.noJacket)) == [.tooCold, .gotWet])
        #expect(JacketFeedback.complaints(for: Fixtures.call(.realCoat)) == [.tooWarm, .gotWet])
        #expect(JacketFeedback.complaints(for: Fixtures.call(.rainJacket, wet: true)) == [.tooCold, .tooWarm, .stayedDry])
    }

    @Test func dayKey() {
        #expect(ThresholdTuner.dayKey(Fixtures.date(hour: 23, minute: 59), calendar: Fixtures.calendar) == "2026-11-06")
    }
}
