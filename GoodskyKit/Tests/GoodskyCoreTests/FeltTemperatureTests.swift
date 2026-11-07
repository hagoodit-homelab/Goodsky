import Foundation
import Testing
@testable import GoodskyCore

@Suite struct FeltTemperatureTests {
    let cal = Fixtures.calendar
    // New York City.
    let lat = 40.71
    let lon = -74.01

    func hour(_ h: Int, temp: Double, feels: Double? = nil, wind: Double = 3, humidity: Double? = 0.6,
              cloud: Double? = 0) -> HourForecast {
        HourForecast(date: Fixtures.date(hour: h), temperatureF: temp, feelsLikeF: feels ?? temp,
                     precipChance: 0, precipAmountIn: 0, precipKind: .none, windMph: wind,
                     humidity: humidity, cloudCover: cloud)
    }

    func felt(_ h: HourForecast, previous: HourForecast? = nil) -> FeltTemperature.Breakdown {
        FeltTemperature.breakdown(h, previous: previous, latitude: lat, longitude: lon, calendar: cal)
    }

    // MARK: Sun position

    @Test func sunIsUpAtNoonAndDownAtMidnight() {
        // Early November in NYC: the sun peaks around 33° (sin ≈ 0.55) just before noon EST.
        let noon = SolarPosition.sinElevation(at: Fixtures.date(hour: 11, minute: 45), latitude: lat, longitude: lon)
        #expect(abs(noon - 0.55) < 0.03)
        #expect(SolarPosition.sinElevation(at: Fixtures.date(hour: 0), latitude: lat, longitude: lon) < 0)
        // Sunrise ~6:30 AM, sunset ~4:50 PM.
        #expect(SolarPosition.sinElevation(at: Fixtures.date(hour: 6), latitude: lat, longitude: lon) < 0)
        #expect(SolarPosition.sinElevation(at: Fixtures.date(hour: 7), latitude: lat, longitude: lon) > 0)
        #expect(SolarPosition.sinElevation(at: Fixtures.date(hour: 16, minute: 30), latitude: lat, longitude: lon) > 0)
        #expect(SolarPosition.sinElevation(at: Fixtures.date(hour: 17, minute: 15), latitude: lat, longitude: lon) < 0)
    }

    // MARK: The whole point

    @Test func sunnyMorning62FeelsWarmerThanBreezyEvening62() {
        // Morning: low sun, calm, warming up.
        let morning = felt(hour(8, temp: 62), previous: hour(7, temp: 60))
        #expect(morning.sun > 3)
        #expect(morning.trend == 1)
        #expect(morning.totalF >= 65)

        // Evening: sun down, clear sky, 8 mph breeze, damp, cooling, end of the day.
        let evening = felt(hour(19, temp: 62, wind: 8, humidity: 0.85), previous: hour(18, temp: 64.5))
        #expect(evening.sun == 0)
        #expect(evening.clearNight == -3)
        #expect(evening.wind == -2.5)
        #expect(evening.damp == -2)
        #expect(evening.trend == -2)
        #expect(evening.evening == -2)
        #expect(evening.totalF == 50.5)
    }

    // MARK: Individual factors

    @Test func cloudsDimTheSun() {
        let clear = felt(hour(12, temp: 60, cloud: 0))
        let overcast = felt(hour(12, temp: 60, cloud: 1))
        #expect(clear.sun > 7)
        #expect(overcast.sun < 2.5)
    }

    @Test func cloudyNightHasNoRadiativePenalty() {
        #expect(felt(hour(22, temp: 60, cloud: 1)).clearNight == 0)
        #expect(felt(hour(22, temp: 60, cloud: 0)).clearNight == -3)
    }

    @Test func windIsCapped() {
        #expect(felt(hour(12, temp: 60, wind: 3)).wind == 0)
        #expect(felt(hour(12, temp: 60, wind: 13)).wind == -5)
        #expect(felt(hour(12, temp: 60, wind: 40)).wind == -8)
    }

    @Test func outsideMildBandUsesWeatherKitForWindAndHumidity() {
        // 30° air, WeatherKit wind chill 22°: start there and don't count the wind twice.
        let b = felt(hour(22, temp: 30, feels: 22, wind: 15, humidity: 0.9, cloud: 1))
        #expect(b.baseF == 22)
        #expect(b.wind == 0)
        #expect(b.damp == 0)
    }

    @Test func missingCloudCoverSkipsSunAndSky() {
        let day = felt(hour(12, temp: 60, cloud: nil))
        let night = felt(hour(23, temp: 60, cloud: nil))
        #expect(day.sun == 0)
        #expect(night.clearNight == 0)
    }

    @Test func eveningPenaltyOnlyAfterDark() {
        #expect(felt(hour(16, temp: 60)).evening == 0)   // sun still up at 4:30
        #expect(felt(hour(18, temp: 60)).evening == -2)
        #expect(felt(hour(4, temp: 60)).evening == 0)    // pre-dawn isn't "end of the day"
    }

    @Test func adjustedUsesPreviousHourForTrend() {
        let hours = [hour(21, temp: 62, cloud: 1), hour(20, temp: 65, cloud: 1)]  // out of order on purpose
        let out = FeltTemperature.adjusted(hours, latitude: lat, longitude: lon, calendar: cal)
        #expect(out.map(\.date) == [Fixtures.date(hour: 20), Fixtures.date(hour: 21)])
        // 9 PM: 62, cooled 3° → −2 trend, −2 evening, overcast so no sky penalty.
        #expect(out[1].feelsLikeF == 58)
    }

    // MARK: Explaining it

    @Test func factorsAddUpAndLeadWithTheBiggest() {
        let evening = felt(hour(19, temp: 62, wind: 8, humidity: 0.85), previous: hour(18, temp: 64.5))
        #expect(evening.gapF == -11.5)
        #expect(evening.factors.first?.label == "Clear night sky")
        #expect(evening.factors.map(\.label).sorted()
                == ["Clear night sky", "Cooling off", "Damp air", "End of the day", "Wind"])
        #expect(abs(evening.factors.map(\.deltaF).reduce(0, +) - evening.gapF) < 0.01)
    }

    @Test func noteNamesTheTopThreeReasons() {
        let evening = felt(hour(19, temp: 62, wind: 8, humidity: 0.85), previous: hour(18, temp: 64.5))
        #expect(evening.note == "Feels 12° colder than the air: clear sky, wind, damp air")

        let morning = felt(hour(10, temp: 62), previous: hour(9, temp: 60))
        #expect(morning.note == "Feels 9° warmer than the air: sun, warming up")
    }

    @Test func noNoteWhenItFeelsLikeTheThermometer() {
        // Overcast, calm, steady, mid-afternoon: within a couple of degrees of the air.
        #expect(felt(hour(14, temp: 60, cloud: 1)).note == nil)
    }

    @Test func windChillShowsAsAFactorOutsideTheMildBand() {
        let b = felt(hour(12, temp: 30, feels: 22, wind: 15, cloud: 1))
        #expect(b.factors.first == .init(label: "Wind chill", deltaF: -8))
    }

    @Test func signedDegrees() {
        #expect(Format.signedDegrees(4.2) == "+4°")
        #expect(Format.signedDegrees(-2.5) == "−3°")
        #expect(Format.signedDegrees(0.3) == "0°")
    }

    // MARK: End to end

    @Test func same62AllDayBecomesJacketLater() throws {
        // 62° from dawn to dusk. WeatherKit would call it "feels like 62" all day → no jacket.
        // Goodsky: sunny and fine in the day, breezy, damp and clear after dark → jacket from 5 PM.
        let now = Fixtures.date(hour: 6)
        let hourly = (0..<36).map { i -> HourForecast in
            let date = Fixtures.date(hour: 0).addingTimeInterval(TimeInterval(i) * 3600)
            let h = cal.component(.hour, from: date)
            let evening = h >= 17
            return HourForecast(date: date, temperatureF: 62, feelsLikeF: 62, precipChance: 0, precipAmountIn: 0,
                                precipKind: .none, windMph: evening ? 8 : 3,
                                humidity: evening ? 0.85 : 0.6, cloudCover: 0)
        }
        let snap = WeatherSnapshot(fetchedAt: now, latitude: lat, longitude: lon, timeZoneIdentifier: "America/New_York",
                                   current: .init(date: now, temperatureF: 62, feelsLikeF: 62, windMph: 3, humidity: 0.6,
                                                  uvIndex: 0, conditionText: "Clear", symbolName: "moon"),
                                   hourly: hourly, daily: [], minutes: [])

        #expect(JacketAdvisor.call(hourly: hourly, now: now, calendar: cal)?.verdict == .noJacket)

        let r = GoodskyReport(snapshot: snap, settings: .default, at: now)
        let call = try #require(r.call)
        #expect(call.verdict == .jacket)
        #expect(call.timing == .later(from: Fixtures.date(hour: 17)))
        #expect(call.headline == "Jacket later")
        #expect(call.minFeelsLikeF == 52.5)

        // The "why" behind the coldest hour, for the UI.
        let why = try #require(r.coldestBreakdown)
        #expect(why.date == Fixtures.date(hour: 17))
        #expect(why.airF == 62)
        #expect(why.note == "Feels 10° colder than the air: clear sky, wind, damp air")
        #expect(r.feltBreakdowns.count == r.feltHourly.count)
    }
}
