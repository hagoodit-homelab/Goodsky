import Foundation

/// Mirrors WeatherKit's `WeatherSeverity`.
public enum AlertSeverity: String, Codable, Sendable, CaseIterable, Comparable {
    case unknown, minor, moderate, severe, extreme

    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }

    public var symbolName: String {
        switch self {
        case .extreme, .severe: "exclamationmark.triangle.fill"
        case .moderate: "exclamationmark.triangle"
        case .minor, .unknown: "info.circle"
        }
    }
}

/// One active government weather alert (from WeatherKit). Display only; Goodsky never pushes these.
public struct WeatherAlertInfo: Codable, Sendable, Equatable, Identifiable {
    /// "Wind Advisory"
    public var summary: String
    public var severity: AlertSeverity
    /// Issuing agency, e.g. "National Weather Service". WeatherKit's terms require showing it.
    public var source: String
    public var region: String?
    /// Full alert text on Apple's site. WeatherKit's terms require linking to it.
    public var detailsURL: URL

    public var id: String { detailsURL.absoluteString }

    public init(summary: String, severity: AlertSeverity, source: String, region: String?, detailsURL: URL) {
        self.summary = summary
        self.severity = severity
        self.source = source
        self.region = region
        self.detailsURL = detailsURL
    }
}

/// What the alerts banner shows.
public struct AlertBanner: Sendable, Equatable {
    public var lead: WeatherAlertInfo
    /// Number of other active alerts.
    public var others: Int
    /// "Wind Advisory" or "Wind Advisory + 2 more"
    public var title: String
    /// "National Weather Service"
    public var subtitle: String
    public var all: [WeatherAlertInfo]

    /// `nil` when nothing is active. Most severe first; duplicates (same summary) collapsed.
    public init?(alerts: [WeatherAlertInfo]?) {
        var seen = Set<String>()
        let sorted = (alerts ?? [])
            .sorted { $0.severity > $1.severity }
            .filter { seen.insert($0.summary.lowercased()).inserted }
        guard let lead = sorted.first else { return nil }
        self.lead = lead
        self.others = sorted.count - 1
        self.title = others == 0 ? lead.summary : "\(lead.summary) + \(others) more"
        self.subtitle = lead.source
        self.all = sorted
    }
}
