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

    /// Jacket thresholds. Saved to the App Group so widgets use the same numbers, and synced to the
    /// other device (phone ↔ watch).
    var settings: JacketSettings {
        didSet {
            guard settings != oldValue else { return }
            store.settings = settings
            if !applyingSyncedSettings {
                let now = Date()
                store.settingsUpdatedAt = now
                SettingsSync.shared.push(settings, updatedAt: now)
            }
            rebuild()
        }
    }

    /// Use Apple's on-device model for the app's snark line. Templates are the fallback either way.
    var aiSnarkEnabled: Bool {
        didSet {
            store.aiSnarkEnabled = aiSnarkEnabled
            aiSnark = nil
            if aiSnarkEnabled { generateAISnarkIfNeeded() }
        }
    }

    /// Model-written line for the current situation, keyed so it only regenerates when the day,
    /// verdict or mood changes.
    private var aiSnark: (key: String, line: String)?
    @ObservationIgnored private var aiSnarkTask: Task<Void, Never>?

    /// Today's 👍/👎, if cast.
    private(set) var todaysFeedback: FeedbackRecord?
    /// Shown after a vote: what changed, plus attitude.
    private(set) var lastTuning: TuningResult?

    private let store = SharedStore()
    private let provider: WeatherProviding
    private let locator = LocationFetcher()
    @ObservationIgnored private var applyingSyncedSettings = false

    init(provider: WeatherProviding = WeatherKitProvider()) {
        self.provider = provider
        self.settings = store.settings
        self.aiSnarkEnabled = store.aiSnarkEnabled
        self.placeName = store.lastLocation?.name
        if let cached = store.snapshot {
            report = GoodskyReport(snapshot: cached, settings: store.settings, at: .now)
        }
        refreshTodaysFeedback()

        SettingsSync.shared.onReceive = { [weak self] settings, updatedAt in
            self?.applySynced(settings, updatedAt: updatedAt)
        }
        SettingsSync.shared.activate()
        // If the other side never heard from us, offer our copy. Newest wins over there.
        if store.settingsUpdatedAt > .distantPast {
            SettingsSync.shared.push(store.settings, updatedAt: store.settingsUpdatedAt)
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
            refreshTodaysFeedback()
            generateAISnarkIfNeeded()
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
        refreshTodaysFeedback()
        generateAISnarkIfNeeded()
    }

    /// Call when Settings closes so widgets pick up new thresholds.
    func settingsDidClose() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Snark

    /// The snark line to show in the app: the model's line when we have one for this exact
    /// situation, otherwise the template line.
    var snark: String {
        guard let report else { return "" }
        if aiSnarkEnabled, let aiSnark, aiSnark.key == snarkKey(for: report) { return aiSnark.line }
        return report.snark
    }

    var snarkIsAI: Bool {
        guard let report, aiSnarkEnabled, let aiSnark else { return false }
        return aiSnark.key == snarkKey(for: report)
    }

    private func snarkKey(for report: GoodskyReport) -> String? {
        report.call.map { SnarkLibrary.cacheKey(for: $0, on: report.date, calendar: report.snapshot.calendar) }
    }

    private func generateAISnarkIfNeeded() {
        guard aiSnarkEnabled, SnarkWriter.isAvailable, let report, let key = snarkKey(for: report) else { return }
        if aiSnark?.key == key || aiSnarkTask != nil { return }
        aiSnarkTask = Task { [weak self] in
            let line = await SnarkWriter.line(for: report)
            guard let self else { return }
            self.aiSnarkTask = nil
            // Templates already showing; only swap in a line that passed the filter.
            if let line { self.aiSnark = (key, line) }
        }
    }

    // MARK: - 👍/👎

    var todayKey: String? {
        report.map { ThresholdTuner.dayKey($0.date, calendar: $0.snapshot.calendar) }
    }

    /// Record a vote on today's call and nudge thresholds. One vote per day; voting again replaces it.
    func submit(_ feedback: JacketFeedback) {
        guard let report, let call = report.call, let day = todayKey else { return }
        // Re-voting the same day: start from the settings before the earlier vote.
        let base = todaysFeedback?.before ?? settings
        let result = ThresholdTuner.apply(feedback, to: call, settings: base)
        let record = FeedbackRecord(date: .now, day: day, verdict: call.verdict, feedback: feedback,
                                    minFeelsLikeF: call.minFeelsLikeF, peakPrecipChance: call.peakPrecipChance,
                                    before: base, after: result.settings)
        store.feedbackLog = store.feedbackLog.filter { $0.day != day } + [record]
        todaysFeedback = record
        lastTuning = result
        settings = result.settings
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Take back today's vote and restore the settings from before it.
    func undoTodaysFeedback() {
        guard let record = todaysFeedback else { return }
        store.feedbackLog = store.feedbackLog.filter { $0.day != record.day }
        todaysFeedback = nil
        lastTuning = nil
        settings = record.before
        WidgetCenter.shared.reloadAllTimelines()
    }

    var feedbackHistory: [FeedbackRecord] { store.feedbackLog }

    func clearFeedbackHistory() {
        store.feedbackLog = []
        todaysFeedback = nil
        lastTuning = nil
    }

    private func refreshTodaysFeedback() {
        guard let day = todayKey else { return }
        if todaysFeedback?.day != day {
            todaysFeedback = store.feedback(forDay: day)
            lastTuning = nil
        }
    }

    // MARK: - Sync

    private func applySynced(_ incoming: JacketSettings, updatedAt: Date) {
        guard updatedAt > store.settingsUpdatedAt else { return }
        store.settingsUpdatedAt = updatedAt
        applyingSyncedSettings = true
        settings = incoming
        applyingSyncedSettings = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Location

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
