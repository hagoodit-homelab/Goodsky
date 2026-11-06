import Foundation

/// Kind of precipitation, mirrored from WeatherKit's `Precipitation` so the core stays platform-free.
public enum PrecipKind: String, Codable, Sendable, CaseIterable {
    case none, rain, snow, sleet, hail, mixed

    /// Word used in user-facing text ("rain", "snow"...).
    public var noun: String {
        switch self {
        case .none, .rain: "rain"
        case .snow: "snow"
        case .sleet: "sleet"
        case .hail: "hail"
        case .mixed: "wintry mix"
        }
    }

    public var isFrozen: Bool { self == .snow || self == .sleet || self == .mixed }
}

/// Current conditions. Temperatures in °F, wind in mph.
public struct CurrentConditions: Codable, Sendable, Equatable {
    public var date: Date
    public var temperatureF: Double
    public var feelsLikeF: Double
    public var windMph: Double
    public var humidity: Double          // 0...1
    public var uvIndex: Int
    public var conditionText: String     // "Mostly Cloudy"
    public var symbolName: String        // SF Symbol name from WeatherKit

    public init(date: Date, temperatureF: Double, feelsLikeF: Double, windMph: Double,
                humidity: Double, uvIndex: Int, conditionText: String, symbolName: String) {
        self.date = date
        self.temperatureF = temperatureF
        self.feelsLikeF = feelsLikeF
        self.windMph = windMph
        self.humidity = humidity
        self.uvIndex = uvIndex
        self.conditionText = conditionText
        self.symbolName = symbolName
    }
}

/// One hour of forecast. `date` is the start of the hour.
public struct HourForecast: Codable, Sendable, Equatable {
    public var date: Date
    public var temperatureF: Double
    public var feelsLikeF: Double
    public var precipChance: Double      // 0...1
    public var precipAmountIn: Double    // expected amount for the hour, inches
    public var precipKind: PrecipKind
    public var windMph: Double
    public var symbolName: String
    public var conditionText: String

    public init(date: Date, temperatureF: Double, feelsLikeF: Double, precipChance: Double,
                precipAmountIn: Double, precipKind: PrecipKind, windMph: Double,
                symbolName: String = "cloud", conditionText: String = "") {
        self.date = date
        self.temperatureF = temperatureF
        self.feelsLikeF = feelsLikeF
        self.precipChance = precipChance
        self.precipAmountIn = precipAmountIn
        self.precipKind = precipKind
        self.windMph = windMph
        self.symbolName = symbolName
        self.conditionText = conditionText
    }
}

/// One minute of the next-hour precipitation forecast.
public struct MinuteForecast: Codable, Sendable, Equatable {
    public var date: Date
    public var precipChance: Double      // 0...1
    public var intensityMmPerHour: Double
    public var precipKind: PrecipKind

    public init(date: Date, precipChance: Double, intensityMmPerHour: Double, precipKind: PrecipKind = .rain) {
        self.date = date
        self.precipChance = precipChance
        self.intensityMmPerHour = intensityMmPerHour
        self.precipKind = precipKind
    }
}

/// One day of the 10-day forecast.
public struct DayForecast: Codable, Sendable, Equatable {
    public var date: Date
    public var highF: Double
    public var lowF: Double
    public var precipChance: Double
    public var precipKind: PrecipKind
    public var symbolName: String
    public var conditionText: String

    public init(date: Date, highF: Double, lowF: Double, precipChance: Double,
                precipKind: PrecipKind, symbolName: String, conditionText: String) {
        self.date = date
        self.highF = highF
        self.lowF = lowF
        self.precipChance = precipChance
        self.precipKind = precipKind
        self.symbolName = symbolName
        self.conditionText = conditionText
    }
}

/// Everything the app and widgets need from one weather fetch.
public struct WeatherSnapshot: Codable, Sendable, Equatable {
    public var fetchedAt: Date
    public var latitude: Double
    public var longitude: Double
    public var timeZoneIdentifier: String
    public var current: CurrentConditions
    public var hourly: [HourForecast]
    public var daily: [DayForecast]
    /// `nil` when WeatherKit has no minute-by-minute data for this location.
    public var minutes: [MinuteForecast]?
    /// Active weather alerts. `nil` in snapshots cached before alerts existed, or when unavailable.
    public var alerts: [WeatherAlertInfo]?

    public init(fetchedAt: Date, latitude: Double, longitude: Double, timeZoneIdentifier: String,
                current: CurrentConditions, hourly: [HourForecast], daily: [DayForecast],
                minutes: [MinuteForecast]?, alerts: [WeatherAlertInfo]? = nil) {
        self.fetchedAt = fetchedAt
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.current = current
        self.hourly = hourly
        self.daily = daily
        self.minutes = minutes
        self.alerts = alerts
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    /// Gregorian calendar in the forecast's time zone; use it for all display formatting.
    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }
}

/// Abstraction over the weather source so the app can be driven by mocks in tests and previews.
public protocol WeatherProviding: Sendable {
    func snapshot(latitude: Double, longitude: Double) async throws -> WeatherSnapshot
}
