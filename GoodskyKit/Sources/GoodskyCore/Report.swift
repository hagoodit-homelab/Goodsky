import Foundation

/// Everything the UI shows for one moment in time, derived from a snapshot.
/// The app, the iPhone widgets and the watch complications all build one of these.
public struct GoodskyReport: Codable, Sendable, Equatable {
    public var date: Date
    public var snapshot: WeatherSnapshot
    public var call: JacketCall?
    public var snark: String
    public var nextHour: PrecipSummary

    public init(snapshot: WeatherSnapshot, settings: JacketSettings, at date: Date) {
        let calendar = snapshot.calendar
        self.date = date
        self.snapshot = snapshot
        self.call = JacketAdvisor.call(hourly: snapshot.hourly, now: date, settings: settings, calendar: calendar)
        self.snark = call.map { SnarkLibrary.line(for: $0, on: date, calendar: calendar) } ?? ""
        self.nextHour = PrecipSummarizer.summary(for: snapshot, now: date, calendar: calendar)
    }

    /// Best guess at the temperature at `date`: the hourly slot covering it, else current conditions.
    public var temperatureF: Double {
        snapshot.hourly.last(where: { $0.date <= date && $0.date.addingTimeInterval(3600) > date })?.temperatureF
            ?? snapshot.current.temperatureF
    }

    public var symbolName: String {
        snapshot.hourly.last(where: { $0.date <= date && $0.date.addingTimeInterval(3600) > date })?.symbolName
            ?? snapshot.current.symbolName
    }

    /// Active alerts banner, if any.
    public var alertBanner: AlertBanner? { AlertBanner(alerts: snapshot.alerts) }

    /// Today's high/low from the daily forecast, if present.
    public var todayHighLow: (high: Double, low: Double)? {
        let calendar = snapshot.calendar
        guard let today = snapshot.daily.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) else { return nil }
        return (today.highF, today.lowF)
    }
}

/// App Group storage shared by the app, widgets and complications.
public struct SharedStore: @unchecked Sendable {
    public static let appGroup = "group.com.hagoodit.goodsky"

    let defaults: UserDefaults

    public init(defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup)) {
        self.defaults = defaults ?? .standard
    }

    private enum Key {
        static let snapshot = "snapshot.v1"
        static let settings = "jacketSettings.v1"
        static let location = "lastLocation.v1"
        static let settingsUpdatedAt = "jacketSettingsUpdatedAt.v1"
        static let feedback = "feedbackLog.v1"
        static let aiSnark = "aiSnarkEnabled.v1"
    }

    public struct Coordinate: Codable, Sendable, Equatable {
        public var latitude: Double
        public var longitude: Double
        public var name: String?
        public init(latitude: Double, longitude: Double, name: String? = nil) {
            self.latitude = latitude
            self.longitude = longitude
            self.name = name
        }
    }

    public var snapshot: WeatherSnapshot? {
        get { decode(Key.snapshot) }
        nonmutating set { encode(newValue, Key.snapshot) }
    }

    public var settings: JacketSettings {
        get { decode(Key.settings) ?? .default }
        nonmutating set { encode(newValue, Key.settings) }
    }

    public var lastLocation: Coordinate? {
        get { decode(Key.location) }
        nonmutating set { encode(newValue, Key.location) }
    }

    /// When `settings` last changed on this device. Used to sync phone ↔ watch (newest wins).
    public var settingsUpdatedAt: Date {
        get { decode(Key.settingsUpdatedAt) ?? .distantPast }
        nonmutating set { encode(newValue, Key.settingsUpdatedAt) }
    }

    /// 👍/👎 history, newest last. Capped at `feedbackLimit`.
    public var feedbackLog: [FeedbackRecord] {
        get { decode(Key.feedback) ?? [] }
        nonmutating set { encode(Array(newValue.suffix(Self.feedbackLimit)), Key.feedback) }
    }

    public static let feedbackLimit = 120

    /// Use Apple's on-device model for the app's snark line (falls back to templates). Default on.
    public var aiSnarkEnabled: Bool {
        get { decode(Key.aiSnark) ?? true }
        nonmutating set { encode(newValue, Key.aiSnark) }
    }

    /// The vote already cast for a day, if any.
    public func feedback(forDay day: String) -> FeedbackRecord? {
        feedbackLog.last(where: { $0.day == day })
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
