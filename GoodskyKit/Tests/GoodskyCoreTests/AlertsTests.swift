import Foundation
import Testing
@testable import GoodskyCore

@Suite struct AlertsTests {
    func alert(_ summary: String, _ severity: AlertSeverity, id: Int) -> WeatherAlertInfo {
        WeatherAlertInfo(summary: summary, severity: severity, source: "National Weather Service",
                         region: "Delaware County", detailsURL: URL(string: "https://weatherkit.apple.com/alert/\(id)")!)
    }

    @Test func noAlertsNoBanner() {
        #expect(AlertBanner(alerts: nil) == nil)
        #expect(AlertBanner(alerts: []) == nil)
    }

    @Test func mostSevereLeads() throws {
        let b = try #require(AlertBanner(alerts: [alert("Frost Advisory", .minor, id: 1),
                                                  alert("Wind Advisory", .moderate, id: 2),
                                                  alert("Tornado Warning", .extreme, id: 3)]))
        #expect(b.lead.summary == "Tornado Warning")
        #expect(b.title == "Tornado Warning + 2 more")
        #expect(b.subtitle == "National Weather Service")
        #expect(b.all.map(\.summary) == ["Tornado Warning", "Wind Advisory", "Frost Advisory"])
    }

    @Test func duplicatesCollapse() throws {
        let b = try #require(AlertBanner(alerts: [alert("Wind Advisory", .moderate, id: 1),
                                                  alert("Wind Advisory", .moderate, id: 2)]))
        #expect(b.title == "Wind Advisory")
        #expect(b.others == 0)
    }

    @Test func oldSnapshotsWithoutAlertsStillDecode() throws {
        let now = Fixtures.date(hour: 6)
        let snap = WeatherSnapshot(fetchedAt: now, latitude: 0, longitude: 0, timeZoneIdentifier: "America/New_York",
                                   current: .init(date: now, temperatureF: 49, feelsLikeF: 47, windMph: 5, humidity: 0.5,
                                                  uvIndex: 0, conditionText: "Clear", symbolName: "sun.max"),
                                   hourly: [], daily: [], minutes: nil)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snap)) as! [String: Any]
        json.removeValue(forKey: "alerts")
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.alerts == nil)
        #expect(decoded.current.temperatureF == 49)
    }
}
