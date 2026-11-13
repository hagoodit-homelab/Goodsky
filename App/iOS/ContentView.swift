import GoodskyCore
import SwiftUI

struct ContentView: View {
    @Environment(WeatherModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let report = model.report {
                        if let banner = report.alertBanner {
                            AlertBannerView(banner: banner)
                        }
                        if horizontalSizeClass == .regular {
                            // iPhone Duo inner display (and any other regular-width space): two equal
                            // columns. Equal widths put the gutter down the middle, over the fold.
                            HStack(alignment: .top, spacing: 24) {
                                VStack(spacing: 16) { callColumn(report) }
                                    .frame(maxWidth: .infinity)
                                VStack(spacing: 16) { forecastColumn(report) }
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            callColumn(report)
                            forecastColumn(report)
                        }
                    } else if model.status == .loading {
                        ProgressView("Interrogating the sky…")
                            .frame(maxWidth: .infinity, minHeight: 300)
                    }

                    if case .failed(let message) = model.status {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.thinMaterial, in: .rect(cornerRadius: 16))
                    }

                    WeatherAttributionFooter()
                }
                // One column stays phone-width (e.g. landscape on the outer display); two columns can spread out.
                .frame(maxWidth: horizontalSizeClass == .regular ? 1100 : 640)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .background(SkyBackground(verdict: model.report?.call?.verdict))
            .navigationTitle(model.placeName ?? "Goodsky")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "slider.horizontal.3") { showingSettings = true }
                }
            }
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showingSettings, onDismiss: { model.settingsDidClose() }) {
                SettingsView()
            }
        }
        .task { await model.refreshIfStale() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshIfStale() } }
        }
    }

    /// The answer: Jacket Call, what it's like now, and the next hour.
    @ViewBuilder
    private func callColumn(_ report: GoodskyReport) -> some View {
        JacketCallCard(report: report, snark: model.snark)
        CurrentConditionsCard(report: report)
        NavigationLink {
            RadarView(report: report)
        } label: {
            NextHourCard(summary: report.nextHour)
        }
        .buttonStyle(.plain)
    }

    /// The detail: 48 hours and 10 days.
    @ViewBuilder
    private func forecastColumn(_ report: GoodskyReport) -> some View {
        HourlyStrip(report: report)
        DailyList(report: report)
    }
}

/// Soft gradient tinted by the verdict.
struct SkyBackground: View {
    let verdict: JacketVerdict?

    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private var colors: [Color] {
        switch verdict {
        case .noJacket: [.orange.opacity(0.35), .yellow.opacity(0.1)]
        case .jacket: [.teal.opacity(0.35), .blue.opacity(0.1)]
        case .realCoat: [.indigo.opacity(0.4), .cyan.opacity(0.1)]
        case .rainJacket: [.blue.opacity(0.45), .gray.opacity(0.15)]
        case nil: [.blue.opacity(0.2), .clear]
        }
    }
}
