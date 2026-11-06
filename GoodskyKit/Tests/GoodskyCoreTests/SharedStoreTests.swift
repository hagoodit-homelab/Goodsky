import Foundation
import Testing
@testable import GoodskyCore

@Suite struct SharedStoreTests {
    @Test func roundTripsSettingsAndLocation() throws {
        let suite = "goodsky.tests.\(UUID().uuidString)"
        let store = SharedStore(defaults: UserDefaults(suiteName: suite))
        #expect(store.settings == .default)
        var s = JacketSettings.default
        s.jacketBelowF = 58
        store.settings = s
        store.lastLocation = .init(latitude: 40.1, longitude: -75.2, name: "Home")
        #expect(store.settings.jacketBelowF == 58)
        #expect(store.lastLocation?.name == "Home")
        store.lastLocation = nil
        #expect(store.lastLocation == nil)
    }

    @Test func reportBuildsFromSnapshot() {
        let now = Fixtures.date(hour: 6)
        let hourly = Fixtures.hours { _ in .init(feels: 50) }
        let snap = WeatherSnapshot(fetchedAt: now, latitude: 0, longitude: 0, timeZoneIdentifier: "America/New_York",
                                   current: .init(date: now, temperatureF: 49, feelsLikeF: 47, windMph: 5, humidity: 0.5,
                                                  uvIndex: 0, conditionText: "Clear", symbolName: "sun.max"),
                                   hourly: hourly, daily: [], minutes: [])
        let r = GoodskyReport(snapshot: snap, settings: .default, at: now)
        #expect(r.call?.verdict == .jacket)
        #expect(!r.snark.isEmpty)
        #expect(r.temperatureF == 50)
    }
}
