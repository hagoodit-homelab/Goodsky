#if canImport(WeatherKit)
import CoreLocation
import Foundation

/// One-shot "where am I?" using CoreLocation. Asks for when-in-use permission on first use.
@MainActor
public final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    public enum LocationError: Error { case denied, unavailable }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    public var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    /// Last location CoreLocation already knows, without waiting. Handy in widgets.
    public var cachedLocation: CLLocation? { manager.location }

    public func currentLocation() async throws -> CLLocation {
        if let pending = continuation {
            continuation = nil
            pending.resume(throwing: CancellationError())
        }
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()   // continues in didChangeAuthorization
            case .denied, .restricted:
                finish(.failure(LocationError.denied))
            default:
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch self.manager.authorizationStatus {
            case .notDetermined: break
            case .denied, .restricted: self.finish(.failure(LocationError.denied))
            default: self.manager.requestLocation()
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.finish(.success(loc)) }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }
}
#endif
