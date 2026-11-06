#if canImport(WeatherKit)
import CoreLocation
import Foundation
import GoodskyCore
import WeatherKit

/// Live weather from Apple's WeatherKit, mapped into GoodskyCore models (°F, mph, inches, mm/h).
public struct WeatherKitProvider: WeatherProviding {
    public init() {}

    public func snapshot(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let now = Date()
        let hourStart = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        let hourEnd = hourStart.addingTimeInterval(48 * 3600)

        let (current, hourly, daily, minute) = try await WeatherService.shared.weather(
            for: location,
            including: .current, .hourly(startDate: hourStart, endDate: hourEnd), .daily, .minute
        )

        return WeatherSnapshot(
            fetchedAt: now,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: TimeZone.current.identifier,
            current: CurrentConditions(
                date: current.date,
                temperatureF: current.temperature.converted(to: .fahrenheit).value,
                feelsLikeF: current.apparentTemperature.converted(to: .fahrenheit).value,
                windMph: current.wind.speed.converted(to: .milesPerHour).value,
                humidity: current.humidity,
                uvIndex: current.uvIndex.value,
                conditionText: current.condition.description,
                symbolName: current.symbolName
            ),
            hourly: hourly.forecast.map { h in
                HourForecast(
                    date: h.date,
                    temperatureF: h.temperature.converted(to: .fahrenheit).value,
                    feelsLikeF: h.apparentTemperature.converted(to: .fahrenheit).value,
                    precipChance: h.precipitationChance,
                    precipAmountIn: h.precipitationAmount.converted(to: .inches).value,
                    precipKind: PrecipKind(h.precipitation),
                    windMph: h.wind.speed.converted(to: .milesPerHour).value,
                    symbolName: h.symbolName,
                    conditionText: h.condition.description
                )
            },
            daily: daily.forecast.map { d in
                DayForecast(
                    date: d.date,
                    highF: d.highTemperature.converted(to: .fahrenheit).value,
                    lowF: d.lowTemperature.converted(to: .fahrenheit).value,
                    precipChance: d.precipitationChance,
                    precipKind: PrecipKind(d.precipitation),
                    symbolName: d.symbolName,
                    conditionText: d.condition.description
                )
            },
            minutes: minute?.forecast.map { m in
                MinuteForecast(
                    date: m.date,
                    precipChance: m.precipitationChance,
                    // UnitSpeed has no mm/h; 1 km/h == 1,000,000 mm/h.
                    intensityMmPerHour: m.precipitationIntensity.converted(to: .kilometersPerHour).value * 1_000_000,
                    precipKind: PrecipKind(m.precipitation)
                )
            }
        )
    }
}

extension PrecipKind {
    init(_ p: Precipitation) {
        switch p {
        case .none: self = .none
        case .rain: self = .rain
        case .snow: self = .snow
        case .sleet: self = .sleet
        case .hail: self = .hail
        case .mixed: self = .mixed
        @unknown default: self = .rain
        }
    }
}

/// Apple Weather attribution (required by WeatherKit's terms wherever its data is shown).
public enum WeatherAttributionLoader {
    public struct Info: Sendable {
        public var lightMarkURL: URL
        public var darkMarkURL: URL
        public var legalPageURL: URL
    }

    public static func load() async -> Info? {
        guard let a = try? await WeatherService.shared.attribution else { return nil }
        return Info(lightMarkURL: a.combinedMarkLightURL, darkMarkURL: a.combinedMarkDarkURL, legalPageURL: a.legalPageURL)
    }
}
#endif
