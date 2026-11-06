import Charts
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

/// Watch companion: swipe (or crown) down through Jacket Call → next hour → hourly → 10 days.
struct WatchContentView: View {
    @Environment(WeatherModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if let report = model.report {
                    TabView {
                        CallPage(report: report).navigationTitle(model.placeName ?? "Goodsky")
                        NextHourPage(report: report).navigationTitle("Next hour")
                        HourlyPage(report: report).navigationTitle("Hourly")
                        DailyPage(report: report).navigationTitle("10 days")
                    }
                    .tabViewStyle(.verticalPage)
                } else if model.status == .loading {
                    ProgressView("Asking the sky…")
                } else {
                    StatusMessage()
                }
            }
        }
        .task { await model.refreshIfStale() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshIfStale() } }
        }
    }
}

// MARK: - Pages

private struct CallPage: View {
    @Environment(WeatherModel.self) private var model
    let report: GoodskyReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let banner = report.alertBanner {
                    Label(banner.title, systemImage: banner.lead.severity.symbolName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(banner.lead.severity >= .severe ? .red : .orange)
                }
                if let call = report.call {
                    HStack(alignment: .firstTextBaseline) {
                        Text(call.verdict.emoji).font(.title)
                        Spacer()
                        Text(Format.degrees(report.temperatureF)).font(.title2.bold())
                    }
                    Text(call.verdict.title).font(.headline)
                    Text(call.reason).font(.footnote)
                    Text(model.snark).font(.footnote.italic()).foregroundStyle(.secondary)
                    FeedbackControls(call: call).padding(.top, 4)
                } else {
                    Text("🤷 No call yet").font(.headline)
                }
                StatusMessage()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NextHourPage: View {
    let report: GoodskyReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(report.nextHour.text).font(.footnote)
                if let points = MinutePoint.points(report), points.contains(where: { $0.mmPerHour > 0 }) {
                    Chart(points) { p in
                        BarMark(x: .value("Minute", p.minute), y: .value("Rain", min(p.mmPerHour, 10)))
                            .foregroundStyle(PrecipIntensity(mmPerHour: p.mmPerHour).watchColor)
                    }
                    .chartXAxis {
                        AxisMarks(values: [0, 15, 30, 45, 60]) { v in
                            AxisValueLabel { Text(v.as(Int.self).map { $0 == 0 ? "now" : "\($0)m" } ?? "") }
                        }
                    }
                    .chartYAxis(.hidden)
                    .chartYScale(domain: 0...10)
                    .frame(height: 70)
                }
                if let banner = report.alertBanner {
                    Text("\(banner.subtitle): \(banner.title)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HourlyPage: View {
    let report: GoodskyReport

    var body: some View {
        let cal = report.snapshot.calendar
        let hours = report.snapshot.hourly.filter { $0.date.addingTimeInterval(3600) > report.date }.prefix(12)
        List(Array(hours.enumerated()), id: \.element.date) { i, hour in
            HStack {
                Text(i == 0 ? "Now" : Format.hour(hour.date, calendar: cal)).frame(width: 46, alignment: .leading)
                Image(systemName: hour.symbolName).symbolRenderingMode(.multicolor).frame(width: 24)
                Spacer()
                if hour.precipChance >= 0.2 {
                    Text(Format.percent(hour.precipChance)).font(.caption2).foregroundStyle(.blue)
                }
                Text(Format.degrees(hour.temperatureF)).bold()
            }
            .font(.footnote)
        }
    }
}

private struct DailyPage: View {
    let report: GoodskyReport

    var body: some View {
        let cal = report.snapshot.calendar
        List(report.snapshot.daily, id: \.date) { day in
            HStack {
                Text(cal.isDate(day.date, inSameDayAs: report.date) ? "Today" : Format.weekday(day.date, calendar: cal))
                    .frame(width: 46, alignment: .leading)
                Image(systemName: day.symbolName).symbolRenderingMode(.multicolor).frame(width: 24)
                Spacer()
                Text(Format.degrees(day.lowF)).foregroundStyle(.secondary)
                Text(Format.degrees(day.highF)).bold()
            }
            .font(.footnote)
        }
    }
}

private struct StatusMessage: View {
    @Environment(WeatherModel.self) private var model

    var body: some View {
        if case .failed(let message) = model.status {
            Text(message).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Helpers

private struct MinutePoint: Identifiable {
    let id: Int
    let minute: Int
    let mmPerHour: Double

    /// Next 60 minutes of intensity, or nil without minute data.
    static func points(_ report: GoodskyReport) -> [MinutePoint]? {
        guard let minutes = report.snapshot.minutes, !minutes.isEmpty else { return nil }
        return minutes
            .filter { $0.date >= report.date.addingTimeInterval(-60) }
            .prefix(60)
            .enumerated()
            .map { i, m in
                let offset = Int(m.date.timeIntervalSince(report.date) / 60)
                return MinutePoint(id: i, minute: max(offset, 0),
                                   mmPerHour: PrecipSummarizer.isWet(m) ? m.intensityMmPerHour : 0)
            }
    }
}

private extension PrecipIntensity {
    var watchColor: Color {
        switch self {
        case .light: .cyan
        case .moderate: .blue
        case .heavy: .purple
        }
    }
}
