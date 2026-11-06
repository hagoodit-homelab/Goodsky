#if canImport(WeatherKit)
import CoreLocation
import Foundation
import GoodskyCore

/// Fetch-or-cache logic for widget/complication timelines.
///
/// Widgets can't prompt for location, so they use the last location the app saved to the App Group
/// (falling back to CoreLocation's cached fix when the widget is authorized for location).
public enum WidgetLoader {
    /// Reuse a cached snapshot younger than this instead of spending a WeatherKit call.
    public static let freshness: TimeInterval = 20 * 60

    public static func snapshot(store: SharedStore = SharedStore(),
                                provider: WeatherProviding = WeatherKitProvider()) async -> WeatherSnapshot? {
        let cached = store.snapshot
        if let cached, Date().timeIntervalSince(cached.fetchedAt) < freshness { return cached }

        let coordinate: SharedStore.Coordinate? = store.lastLocation ?? CLLocationManager().location.map {
            .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        guard let coordinate else { return cached }

        do {
            let fresh = try await provider.snapshot(latitude: coordinate.latitude, longitude: coordinate.longitude)
            store.snapshot = fresh
            return fresh
        } catch {
            return cached
        }
    }
}
#endif
