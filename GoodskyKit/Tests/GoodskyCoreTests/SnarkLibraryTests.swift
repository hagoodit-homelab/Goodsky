import Foundation
import Testing
@testable import GoodskyCore

@Suite struct SnarkLibraryTests {
    let cal = Fixtures.calendar

    func call(_ verdict: JacketVerdict, min: Double = 55, max: Double = 70, wet: Bool = false,
              chance: Double = 0, kind: PrecipKind = .none, wind: Double = 5, bumped: Bool = false) -> JacketCall {
        JacketCall(verdict: verdict, reason: "", windowStart: .now, windowEnd: .now, minFeelsLikeF: min,
                   maxFeelsLikeF: max, coldestHour: .now, firstWetHour: wet ? .now : nil,
                   peakPrecipChance: chance, precipKind: kind, maxWindMph: wind, windBumped: bumped)
    }

    @Test func everyVerdictAndMoodHasLines() {
        for v in JacketVerdict.allCases { #expect((SnarkLibrary.verdictLines[v] ?? []).count >= 4) }
        for m in SnarkLibrary.Mood.allCases { #expect((SnarkLibrary.moodLines[m] ?? []).count >= 4) }
    }

    @Test func moods() {
        #expect(SnarkLibrary.mood(for: call(.realCoat, min: 25, wet: true, chance: 0.8, kind: .snow)) == .snow)
        #expect(SnarkLibrary.mood(for: call(.realCoat, min: 10)) == .freezing)
        #expect(SnarkLibrary.mood(for: call(.rainJacket, wet: true, chance: 0.9, kind: .rain)) == .downpour)
        #expect(SnarkLibrary.mood(for: call(.jacket, bumped: true)) == .windy)
        #expect(SnarkLibrary.mood(for: call(.noJacket, min: 80, max: 95)) == .scorching)
        #expect(SnarkLibrary.mood(for: call(.noJacket, min: 68, max: 76)) == .perfect)
        #expect(SnarkLibrary.mood(for: call(.jacket)) == nil)
    }

    @Test func lineIsStableWithinADay() {
        let c = call(.rainJacket, wet: true, chance: 0.5, kind: .rain)
        let a = SnarkLibrary.line(for: c, on: Fixtures.date(hour: 7), calendar: cal)
        let b = SnarkLibrary.line(for: c, on: Fixtures.date(hour: 17), calendar: cal)
        #expect(a == b)
        #expect(SnarkLibrary.verdictLines[.rainJacket]!.contains(a))
    }

    @Test func lineVariesAcrossDays() {
        let c = call(.jacket)
        let lines = Set((1...20).map { SnarkLibrary.line(for: c, on: Fixtures.date(hour: 9, day: $0), calendar: cal) })
        #expect(lines.count > 1)
    }
}
