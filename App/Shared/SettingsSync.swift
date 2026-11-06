import Foundation
import GoodskyCore
import WatchConnectivity

/// Keeps Jacket Call thresholds in sync between the iPhone and the Watch.
///
/// The App Group only shares data on one device, so without this the watch would keep the default
/// thresholds forever. Each side sends `(settings, updatedAt)` as WatchConnectivity application
/// context; the receiver keeps whichever is newer. Works in both directions, so 👍/👎 on the
/// watch tunes the phone too.
@MainActor
final class SettingsSync: NSObject {
    static let shared = SettingsSync()

    /// Called on the main actor with newer settings from the other device.
    var onReceive: ((JacketSettings, Date) -> Void)?

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var pending: (JacketSettings, Date)?

    func activate() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// Send our settings to the other device. Queued until the session is active.
    func push(_ settings: JacketSettings, updatedAt: Date) {
        guard let session, session.activationState == .activated else {
            pending = (settings, updatedAt)
            return
        }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? session.updateApplicationContext([
            Key.settings: data,
            Key.updatedAt: updatedAt.timeIntervalSince1970,
        ])
    }

    private func handle(_ context: [String: Any]) {
        guard let data = context[Key.settings] as? Data,
              let stamp = context[Key.updatedAt] as? Double,
              let settings = try? JSONDecoder().decode(JacketSettings.self, from: data) else { return }
        deliver(settings, Date(timeIntervalSince1970: stamp))
    }

    private func deliver(_ settings: JacketSettings, _ updatedAt: Date) {
        onReceive?(settings, updatedAt)
    }

    private func activated() {
        if let pending {
            self.pending = nil
            push(pending.0, updatedAt: pending.1)
        }
    }

    private enum Key {
        static let settings = "jacketSettings"
        static let updatedAt = "updatedAt"
    }
}

extension SettingsSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        // Pull out plain values before hopping actors; the context dictionary isn't Sendable.
        let context = session.receivedApplicationContext
        let data = context[Key.settings] as? Data
        let stamp = context[Key.updatedAt] as? Double
        Task { @MainActor in
            if let data, let stamp { self.handle([Key.settings: data, Key.updatedAt: stamp]) }
            if state == .activated { self.activated() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let data = context[Key.settings] as? Data
        let stamp = context[Key.updatedAt] as? Double
        Task { @MainActor in
            if let data, let stamp { self.handle([Key.settings: data, Key.updatedAt: stamp]) }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Happens when switching watches. Reactivate for the new one.
        session.activate()
    }
    #endif
}
