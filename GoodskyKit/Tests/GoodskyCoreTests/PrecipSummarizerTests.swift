import Foundation
import Testing
@testable import GoodskyCore

@Suite struct PrecipSummarizerTests {
    let cal = Fixtures.calendar
    let now = Fixtures.date(hour: 15, minute: 50)

    @Test func dryHour() throws {
        let ms = Fixtures.minutes({ _ in (0, 0) }, start: now)
        let s = try #require(PrecipSummarizer.summarize(minutes: ms, now: now, calendar: cal))
        #expect(s.text == "No rain for the next hour.")
        #expect(s.intensity == nil)
    }

    @Test func rainArrivesAndStops() throws {
        // Wet from +25 to +50: 25 minutes.
        let ms = Fixtures.minutes({ i in (25..<50).contains(i) ? (0.9, 1.0) : (0, 0) }, start: now)
        let s = try #require(PrecipSummarizer.summarize(minutes: ms, now: now, calendar: cal))
        #expect(s.text == "Light rain reaches you around 4:15, lasts about 25 minutes.")
        #expect(s.startsAt == now.addingTimeInterval(25 * 60))
    }

    @Test func rainArrivesAndStays() throws {
        let ms = Fixtures.minutes({ i in i >= 25 ? (0.9, 5.0) : (0, 0) }, start: now)
        let s = try #require(PrecipSummarizer.summarize(minutes: ms, now: now, calendar: cal))
        #expect(s.text == "Moderate rain reaches you around 4:15 and sticks around past the hour.")
    }

    @Test func rainingNowAndStopping() throws {
        let ms = Fixtures.minutes({ i in i < 20 ? (0.9, 10) : (0, 0) }, start: now)
        let s = try #require(PrecipSummarizer.summarize(minutes: ms, now: now, calendar: cal))
        #expect(s.isPrecipitatingNow)
        #expect(s.text == "Heavy rain now, stopping around 4:10.")
    }

    @Test func rainingAllHour() throws {
        let ms = Fixtures.minutes({ _ in (0.9, 1) }, start: now)
        let s = try #require(PrecipSummarizer.summarize(minutes: ms, now: now, calendar: cal))
        #expect(s.text == "Light rain now, and it's not stopping this hour.")
    }

    @Test func briefDryGapDoesNotEndEpisode() throws {
        // Wet 10..<30 with a 2-minute gap at 18-19, then dry.
        let ms = Fixtures.minutes({ i in (10..<30).contains(i) && !(18...19).contains(i) ? (0.9, 1) : (0, 0) }, start: now)
        let s = try #require(PrecipSummarizer.summarize(minutes: ms, now: now, calendar: cal))
        #expect(s.endsAt == now.addingTimeInterval(30 * 60))
    }

    @Test func shortShower() throws {
        let ms = Fixtures.minutes({ i in (10..<14).contains(i) ? (0.9, 1) : (0, 0) }, start: now)
        let s = try #require(PrecipSummarizer.summarize(minutes: ms, now: now, calendar: cal))
        #expect(s.text.hasSuffix("lasts only a few minutes."))
    }

    @Test func emptyMinutesFallsBackToHourly() {
        let hourly = [HourForecast(date: Fixtures.date(hour: 15), temperatureF: 60, feelsLikeF: 60,
                                   precipChance: 0.35, precipAmountIn: 0.02, precipKind: .rain, windMph: 5)]
        let snap = WeatherSnapshot(fetchedAt: now, latitude: 0, longitude: 0, timeZoneIdentifier: "America/New_York",
                                   current: .init(date: now, temperatureF: 60, feelsLikeF: 60, windMph: 5, humidity: 0.5,
                                                  uvIndex: 1, conditionText: "Cloudy", symbolName: "cloud"),
                                   hourly: hourly, daily: [], minutes: nil)
        #expect(PrecipSummarizer.summary(for: snap, now: now, calendar: cal).text == "Next hour: 35% chance of rain.")
    }

    @Test func intensityBands() {
        #expect(PrecipIntensity(mmPerHour: 0.5) == .light)
        #expect(PrecipIntensity(mmPerHour: 4) == .moderate)
        #expect(PrecipIntensity(mmPerHour: 12) == .heavy)
    }
}
