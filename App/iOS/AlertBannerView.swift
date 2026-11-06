import GoodskyCore
import SwiftUI

/// Active government weather alerts, display only. Tapping shows each alert with its source and a
/// link to the full text (both required by WeatherKit's terms).
struct AlertBannerView: View {
    let banner: AlertBanner
    @State private var showingDetails = false

    var body: some View {
        Button { showingDetails = true } label: {
            HStack(spacing: 12) {
                Image(systemName: banner.lead.severity.symbolName)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title).font(.subheadline.weight(.semibold))
                    Text(banner.subtitle).font(.caption).opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(banner.lead.severity.tint.gradient, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows alert details")
        .sheet(isPresented: $showingDetails) {
            AlertDetailsSheet(alerts: banner.all)
        }
    }
}

private struct AlertDetailsSheet: View {
    let alerts: [WeatherAlertInfo]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(alerts) { alert in
                VStack(alignment: .leading, spacing: 6) {
                    Label(alert.summary, systemImage: alert.severity.symbolName)
                        .font(.headline)
                        .foregroundStyle(alert.severity.tint)
                    if let region = alert.region, !region.isEmpty {
                        Text(region).font(.subheadline)
                    }
                    Text(alert.source).font(.caption).foregroundStyle(.secondary)
                    Link("Read the full alert", destination: alert.detailsURL)
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Weather alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension AlertSeverity {
    var tint: Color {
        switch self {
        case .extreme: .red
        case .severe: .orange
        case .moderate: .yellow.mix(with: .orange, by: 0.5)
        case .minor, .unknown: .gray
        }
    }
}
