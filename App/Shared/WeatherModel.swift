import CoreLocation
import Foundation
import GoodskyCore
import GoodskyWeather
import Observation
import WidgetKit

/// App state shared by the iPhone and Watch apps: location → WeatherKit → GoodskyReport.
@Observable
@MainActor
final class WeatherModel {
    enum Status: Equatable {
        case idle
        case loading
        case failed(String)
    }

    private(set) var report: GoodskyReport?
    private(set) var status: Status = .idle
    private(set) var placeName: String?

    /// Jacket thresholds. Saved to the App Group so widgets use the same numbers.
    var settings: JacketSettings {
        didSet {
            store.settings = settings
            rebuild()
        }
    }

    private let store = SharedStore()
    private let provider: WeatherProviding
    private let locator = LocationFetcher()

    init(provider: WeatherProviding = WeatherKitProvider()) {
        self.provider = provider
        self.settings = store.settings
        self.placeName = store.lastLocation?.name
        if let cached = store.snapshot {
            report = GoodskyReport(snapshot: cached, settings: store.settings, at: .now)
        }
    }

    var isStale: Bool {
        guard let fetched = report?.snapshot.fetchedAt else { return true }
        return Date().timeIntervalSince(fetched) > 10 * 60
    }

    func refreshIfStale() async {
        if isStale { await refresh() } else { rebuild() }
    }

    func refresh() async {
        guard status != .loading else { return }
        status = .loading
        do {
            let coordinate = try await resolveLocation()
            let snapshot = try await provider.snapshot(latitude: coordinate.latitude, longitude: coordinate.longitude)
            store.snapshot = snapshot
            report = GoodskyReport(snapshot: snapshot, settings: settings, at: .now)
            status = .idle
            WidgetCenter.shared.reloadAllTimelines()
        } catch LocationFetcher.LocationError.denied {
            status = .failed("Location is off. Turn it on in Settings so I can judge your outfit.")
        } catch {
            status = .failed("Couldn't get the weather: \(error.localizedDescription)")
        }
    }

    /// Re-run the Jacket Call against the cached snapshot (new settings, or time has passed).
    func rebuild() {
        guard let snapshot = report?.snapshot else { return }
        report = GoodskyReport(snapshot: snapshot, settings: settings, at: .now)
    }

    /// Call when Settings closes so widgets pick up new thresholds.
    func settingsDidClose() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func resolveLocation() async throws -> SharedStore.Coordinate {
        do {
            let location = try await locator.currentLocation()
            let name = await Self.placeName(for: location)
            let coordinate = SharedStore.Coordinate(latitude: location.coordinate.latitude,
                                                    longitude: location.coordinate.longitude,
                                                    name: name ?? store.lastLocation?.name)
            store.lastLocation = coordinate
            placeName = coordinate.name
            return coordinate
        } catch {
            // Fall back to the last known spot so a GPS hiccup doesn't blank the app.
            if let last = store.lastLocation, !(error is LocationFetcher.LocationError) { return last }
            throw error
        }
    }

    private static func placeName(for location: CLLocation) async -> String? {
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        return placemark?.locality ?? placemark?.name
    }
}
