import GoodskyCore
import SwiftUI

@main
struct GoodskyWatchApp: App {
    @State private var model = WeatherModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(model)
        }
    }
}

/// Minimal watch app. It mainly exists so the complication has a home and a location to use.
/// The full companion app is Phase 2.
struct WatchContentView: View {
    @Environment(WeatherModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let report = model.report, let call = report.call {
                    HStack {
                        Text(call.verdict.emoji).font(.title)
                        Spacer()
                        Text(Format.degrees(report.temperatureF)).font(.title2.bold())
                    }
                    Text(call.verdict.title).font(.headline)
                    Text(call.reason).font(.footnote)
                    Text(report.nextHour.text).font(.footnote).foregroundStyle(.blue)
                    Text(report.snark).font(.footnote.italic()).foregroundStyle(.secondary)
                } else if model.status == .loading {
                    ProgressView()
                }
                if case .failed(let message) = model.status {
                    Text(message).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await model.refreshIfStale() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshIfStale() } }
        }
    }
}
