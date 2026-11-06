import GoodskyCore
import SwiftUI

/// The hero: verdict, why, and an insult.
struct JacketCallCard: View {
    let report: GoodskyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let call = report.call {
                HStack(alignment: .firstTextBaseline) {
                    Text(call.verdict.emoji).font(.system(size: 56))
                    Text(call.verdict.title)
                        .font(.largeTitle.bold())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Text(call.reason)
                    .font(.headline)
                Text(report.snark)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                Text(windowLabel(call))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("🤷 No call yet").font(.title.bold())
                Text("The forecast is missing hours I need. Pull to refresh.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func windowLabel(_ call: JacketCall) -> String {
        let cal = report.snapshot.calendar
        return "Judging \(Format.hour(call.windowStart, calendar: cal))–\(Format.hour(call.windowEnd, calendar: cal))"
    }
}

struct CurrentConditionsCard: View {
    let report: GoodskyReport

    var body: some View {
        let now = report.snapshot.current
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: now.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 44))
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.degrees(now.temperatureF)).font(.system(size: 44, weight: .semibold, design: .rounded))
                Text(now.conditionText).font(.subheadline)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Feels \(Format.degrees(now.feelsLikeF))")
                if let hl = report.todayHighLow {
                    Text("H \(Format.degrees(hl.high))  L \(Format.degrees(hl.low))")
                }
                Text("Wind \(Format.mph(now.windMph))")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }
}

struct NextHourCard: View {
    let summary: PrecipSummary

    var body: some View {
        Label {
            Text(summary.text).font(.callout)
        } icon: {
            Image(systemName: summary.intensity == nil ? "umbrella" : "cloud.rain.fill")
                .symbolRenderingMode(.multicolor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }
}

struct HourlyStrip: View {
    let report: GoodskyReport

    var body: some View {
        let cal = report.snapshot.calendar
        let hours = report.snapshot.hourly
            .filter { $0.date.addingTimeInterval(3600) > report.date }
            .prefix(48)

        VStack(alignment: .leading, spacing: 8) {
            Text("Next 48 hours").font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(hours.enumerated()), id: \.element.date) { index, hour in
                        VStack(spacing: 6) {
                            Text(index == 0 ? "Now" : Format.hour(hour.date, calendar: cal))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: hour.symbolName)
                                .symbolRenderingMode(.multicolor)
                                .frame(height: 22)
                            Text(Format.degrees(hour.temperatureF)).font(.callout.weight(.semibold))
                            Text(hour.precipChance >= 0.2 ? Format.percent(hour.precipChance) : " ")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        .frame(minWidth: 40)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }
}

struct DailyList: View {
    let report: GoodskyReport

    var body: some View {
        let cal = report.snapshot.calendar
        let days = report.snapshot.daily
        let lowest = days.map(\.lowF).min() ?? 0
        let highest = days.map(\.highF).max() ?? 100

        VStack(alignment: .leading, spacing: 10) {
            Text("10 days").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(days, id: \.date) { day in
                HStack(spacing: 12) {
                    Text(cal.isDate(day.date, inSameDayAs: report.date) ? "Today" : Format.weekday(day.date, calendar: cal))
                        .frame(width: 48, alignment: .leading)
                    Image(systemName: day.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 28)
                    Text(day.precipChance >= 0.2 ? Format.percent(day.precipChance) : "")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .frame(width: 36, alignment: .leading)
                    Text(Format.degrees(day.lowF)).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                    TemperatureBar(low: day.lowF, high: day.highF, rangeLow: lowest, rangeHigh: highest)
                    Text(Format.degrees(day.highF)).frame(width: 36, alignment: .leading)
                }
                .font(.callout)
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }
}

struct TemperatureBar: View {
    let low: Double, high: Double, rangeLow: Double, rangeHigh: Double

    var body: some View {
        GeometryReader { geo in
            let span = max(rangeHigh - rangeLow, 1)
            let x0 = (low - rangeLow) / span * geo.size.width
            let x1 = (high - rangeLow) / span * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(x1 - x0, 6))
                    .offset(x: x0)
            }
        }
        .frame(height: 6)
    }
}
