import GoodskyCore
import GoodskyWeather
import SwiftUI
import WidgetKit

// Shared by the iPhone widget extension and the watchOS widget extension (complications / Smart Stack).

@main
struct GoodskyWidgetBundle: WidgetBundle {
    var body: some Widget {
        JacketWidget()
    }
}

struct JacketEntry: TimelineEntry {
    let date: Date
    let report: GoodskyReport?
}

struct JacketProvider: TimelineProvider {
    func placeholder(in context: Context) -> JacketEntry {
        JacketEntry(date: .now, report: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (JacketEntry) -> Void) {
        let store = SharedStore()
        let report = store.snapshot.map { GoodskyReport(snapshot: $0, settings: store.settings, at: .now) }
        completion(JacketEntry(date: .now, report: report))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JacketEntry>) -> Void) {
        Task {
            let store = SharedStore()
            let snapshot = await WidgetLoader.snapshot(store: store)
            let settings = store.settings
            let now = Date()
            let hourStart = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now

            // One entry now, then one per hour so the call/temperature move forward even without a refetch.
            var dates = [now]
            dates += (1...6).map { hourStart.addingTimeInterval(TimeInterval($0) * 3600) }
            let entries = dates.map { date in
                JacketEntry(date: date, report: snapshot.map { GoodskyReport(snapshot: $0, settings: settings, at: date) })
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }
}

struct JacketWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JacketCall", provider: JacketProvider()) { entry in
            JacketWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Jacket Call")
        .description("Jacket, rain jacket, or nothing. Plus some attitude.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
        #else
        [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}

struct JacketWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: JacketEntry

    var body: some View {
        if let report = entry.report, let call = report.call {
            content(report: report, call: call)
        } else {
            empty
        }
    }

    @ViewBuilder
    private func content(report: GoodskyReport, call: JacketCall) -> some View {
        let temp = Format.degrees(report.temperatureF)
        switch family {
        case .accessoryInline:
            Text("\(call.verdict.emoji) \(call.shortHeadline) · \(temp)")

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(call.verdict.emoji).font(.title3)
                    Text(temp).font(.caption.bold())
                }
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(call.verdict.emoji) \(call.headline)")
                    .font(.headline)
                    .widgetAccentable()
                Text("\(temp) · \(shortReason(call, report: report))")
                    .font(.caption)
                Text(report.snark)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        #if os(watchOS)
        case .accessoryCorner:
            Text(call.verdict.emoji)
                .font(.title2)
                .widgetLabel("\(call.shortHeadline) · \(temp)")
        #endif

        case .systemMedium:
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(call.verdict.emoji).font(.system(size: 40))
                    Text(call.headline).font(.headline)
                    Text(temp).font(.title2.bold())
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let banner = report.alertBanner {
                        Label(banner.title, systemImage: banner.lead.severity.symbolName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    if let split = call.splitSummary(at: report.date, calendar: report.snapshot.calendar) {
                        Text(split).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    Text(call.reason).font(.caption).lineLimit(3)
                    Text(report.snark).font(.caption.italic()).foregroundStyle(.secondary).lineLimit(report.alertBanner == nil ? 3 : 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default: // .systemSmall
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(call.verdict.emoji).font(.system(size: 32))
                    Spacer()
                    Text(temp).font(.title2.bold())
                }
                Text(call.headline).font(.headline)
                Text(call.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var empty: some View {
        VStack(spacing: 2) {
            Text("🤷")
            if family != .accessoryCircular && family != .accessoryInline {
                Text("Open Goodsky once").font(.caption2)
            }
        }
    }

    /// Fits the rectangular complication's middle line: "rain 3 PM", "feels 48°", "need by 5 PM".
    private func shortReason(_ call: JacketCall, report: GoodskyReport) -> String {
        let cal = report.snapshot.calendar
        switch call.timing {
        case .later(let from) where call.firstWetHour != from:
            return "need by \(Format.hour(from, calendar: cal))"
        case .nowOnly(let until):
            return "ditch by \(Format.hour(until, calendar: cal))"
        default:
            break
        }
        if let wet = call.firstWetHour {
            let noun = call.precipKind.noun
            return wet <= report.date ? "\(noun) now" : "\(noun) \(Format.hour(wet, calendar: cal))"
        }
        return "feels \(Format.degrees(call.minFeelsLikeF))"
    }
}
