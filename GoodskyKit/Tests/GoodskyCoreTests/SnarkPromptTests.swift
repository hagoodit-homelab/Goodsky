import Foundation
import Testing
@testable import GoodskyCore

@Suite struct SnarkPromptTests {
    @Test func promptCarriesTheFacts() {
        let call = Fixtures.call(.rainJacket, min: 48, max: 60, wet: true, chance: 0.7, kind: .rain, wind: 18)
        let p = SnarkPrompt.prompt(for: call, current: nil, example: "Bring the damn rain jacket.",
                                   calendar: Fixtures.calendar)
        #expect(p.contains("Verdict: rain jacket."))
        #expect(p.contains("Rain from 3 PM, up to 70% chance."))
        #expect(p.contains("Wind up to 18 mph."))
        #expect(p.contains("Bring the damn rain jacket."))
    }

    @Test func acceptsAGoodLine() {
        #expect(SnarkPrompt.accept("Grab a jacket, you shivering little gremlin.", for: .jacket)
                == "Grab a jacket, you shivering little gremlin.")
    }

    @Test func cleansQuotesLabelsAndExtraLines() {
        #expect(SnarkPrompt.accept("\"Rain's coming, genius. Dress like it.\"\nHope that helps!", for: .rainJacket)
                == "Rain's coming, genius. Dress like it.")
        #expect(SnarkPrompt.accept("Line: It's cold as hell, wear the big coat.", for: .realCoat)
                == "It's cold as hell, wear the big coat.")
    }

    @Test func rejectsRefusalsAndTameFiller() {
        #expect(SnarkPrompt.accept("I'm sorry, but I can't write insulting content.", for: .jacket) == nil)
        #expect(SnarkPrompt.accept("Bring a jacket and have a great day!", for: .jacket) == nil)
        #expect(SnarkPrompt.accept("Remember to bring a light jacket today.", for: .jacket) == nil)
        #expect(SnarkPrompt.accept("Brr!", for: .jacket) == nil)  // too short
        #expect(SnarkPrompt.accept(String(repeating: "damn ", count: 40), for: .jacket) == nil)  // too long
    }

    @Test func rejectsLinesThatArgueWithTheVerdict() {
        #expect(SnarkPrompt.accept("Leave the jacket at home, it's balmy.", for: .jacket) == nil)
        #expect(SnarkPrompt.accept("Wear a jacket, it's nippy out there.", for: .noJacket) == nil)
        #expect(SnarkPrompt.accept("It stays dry, so skip the umbrella drama.", for: .rainJacket) == nil)
    }

    @Test func cacheKeyMatchesTemplatePickInputs() {
        let call = Fixtures.call(.jacket)
        let a = SnarkLibrary.cacheKey(for: call, on: Fixtures.date(hour: 7), calendar: Fixtures.calendar)
        let b = SnarkLibrary.cacheKey(for: call, on: Fixtures.date(hour: 18), calendar: Fixtures.calendar)
        #expect(a == b)
        #expect(a == "2026-11-6|jacket|-")
    }
}
