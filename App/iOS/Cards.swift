import GoodskyCore
import SwiftUI

/// The hero: verdict, why, an insult, and a 👍/👎.
struct JacketCallCard: View {
    let report: GoodskyReport
    /// Model-written when available, template otherwise (see `WeatherModel.snark`).
    let snark: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let call = report.call {
                HStack(alignment: .firstTextBaseline) {
                    Text(call.verdict.emoji).font(.system(size: 56))
                    Text(call.headline)
                        .font(.largeTitle.bold())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                if call.later != nil {
                    let cal = report.snapshot.calendar
                    let phases = call.phases
                    HStack(spacing: phases.count > 2 ? 4 : 10) {
                        ForEach(Array(phases.enumerated()), id: \.offset) { i, phase in
                            if i > 0 {
                                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            PhasePanel(phase: phase,
                                       title: i == 0 ? phase.label(at: report.date, calendar: cal)
                                                     : "From \(Format.hour(phase.start, calendar: cal))",
                                       calendar: cal, compact: phases.count > 2)
                        }
                    }
                    if let plan = call.plan {
                        Label(plan, systemImage: "bag").font(.headline)
                    }
                }
                Text(call.reason)
                    .font(call.later == nil ? .headline : .subheadline)
                if let breakdown = report.coldestBreakdown, let note = breakdown.note {
                    FeelsNoteButton(breakdown: breakdown, note: "\(Format.hour(breakdown.date, calendar: report.snapshot.calendar)) · \(note)",
                                    calendar: report.snapshot.calendar)
                }
                Text(snark)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.default, value: snark)
                Text(windowLabel(call))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Divider().padding(.vertical, 2)
                FeedbackControls(call: call)
            } else {
                Text("🤷 No call yet").font(.title.bold())
                Text("The forecast is missing hours I need. Pull to refresh.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
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
                if let breakdown = report.feelsBreakdown {
                    FeelsLikeButton(breakdown: breakdown, calendar: report.snapshot.calendar)
                } else {
                    Text("Feels \(Format.degrees(report.feelsLikeF))")
                }
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

/// Next-hour sentence. Taps through to the radar.
struct NextHourCard: View {
    let summary: PrecipSummary

    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(summary.text).font(.callout)
            } icon: {
                Image(systemName: summary.intensity == nil ? "umbrella" : "cloud.rain.fill")
                    .symbolRenderingMode(.multicolor)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Text("Radar")
                Image(systemName: "chevron.right")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
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

// MARK: - Now / later

/// One half of the now/later split: "Now · 😎 No jacket · Feels 66°".
struct PhasePanel: View {
    let phase: JacketPhase
    let title: String
    let calendar: Calendar
    /// Three-across layout: drop the word and keep the emoji big.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(compact ? phase.verdict.shortTitle : "\(phase.verdict.emoji) \(phase.verdict.title)")
                .font(compact ? .subheadline.weight(.semibold) : .headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if compact { Text(phase.verdict.emoji).font(.title2) }
            Text(compact ? "Feels \(Format.degrees(phase.minFeelsLikeF))" : detail)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 8 : 10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if let wet = phase.firstWetHour, wet > phase.start {
            return "Feels \(Format.degrees(phase.minFeelsLikeF)) · wet from \(Format.hour(wet, calendar: calendar))"
        }
        return "Feels \(Format.degrees(phase.minFeelsLikeF))"
    }
}

// MARK: - Feels-like breakdown

/// "5 PM · Feels 10° colder than the air: clear sky, wind, damp air". Tap for the full breakdown.
struct FeelsNoteButton: View {
    let breakdown: FeltTemperature.Breakdown
    let note: String
    let calendar: Calendar
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Label(note, systemImage: "thermometer.medium")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows how Goodsky worked out the feels-like temperature")
        .popover(isPresented: $showing) {
            FeelsBreakdownView(breakdown: breakdown, calendar: calendar)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// "Feels 51° ⓘ" on the current-conditions card, with the air-vs-feels gap underneath.
struct FeelsLikeButton: View {
    let breakdown: FeltTemperature.Breakdown
    let calendar: Calendar
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 3) {
                Text("Feels \(Format.degrees(breakdown.totalF))")
                Image(systemName: "info.circle").imageScale(.small)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows how Goodsky worked out the feels-like temperature")
        .popover(isPresented: $showing) {
            FeelsBreakdownView(breakdown: breakdown, calendar: calendar)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Air temperature, each adjustment, and the result, like a receipt.
struct FeelsBreakdownView: View {
    let breakdown: FeltTemperature.Breakdown
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Feels like at \(Format.hour(breakdown.date, calendar: calendar))").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                row("Air temperature", Format.degrees(breakdown.airF))
                ForEach(Array(breakdown.factors.enumerated()), id: \.offset) { _, f in
                    row(f.label, Format.signedDegrees(f.deltaF))
                        .foregroundStyle(f.deltaF < 0 ? .blue : .orange)
                }
                Divider().gridCellColumns(2)
                row("Feels like", Format.degrees(breakdown.totalF)).bold()
            }
            .font(.subheadline)
            .monospacedDigit()
        }
        .padding()
        .frame(minWidth: 240)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
            Text(value).gridColumnAlignment(.trailing)
        }
    }
}
