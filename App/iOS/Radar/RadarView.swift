import GoodskyCore
import MapKit
import SwiftUI

/// "Is rain coming at me?" The sentence at the top is the real answer; the map is backup.
struct RadarView: View {
    let report: GoodskyReport

    @State private var frames = RadarTimeline.frames(latestValid: nil)
    @State private var index = RadarTimeline.frames(latestValid: nil).count - 1
    @State private var playing = true
    @State private var now = Date()

    var body: some View {
        VStack(spacing: 12) {
            Label {
                Text(report.nextHour.text).font(.title3.weight(.semibold))
            } icon: {
                Image(systemName: report.nextHour.intensity == nil ? "umbrella" : "cloud.rain.fill")
                    .symbolRenderingMode(.multicolor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            ZStack(alignment: .bottom) {
                RadarMapView(center: CLLocationCoordinate2D(latitude: report.snapshot.latitude,
                                                            longitude: report.snapshot.longitude),
                             frames: frames, visibleIndex: index)
                    .clipShape(.rect(cornerRadius: 24))
                controls.padding(12)
            }
            .padding(.horizontal)

            legend
            Text("\(RadarTimeline.attribution). US only. Past hour; the sentence up top covers what's next.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical)
        .navigationTitle("Radar")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadLatestTime() }
        .task(id: playing) { await play() }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                playing.toggle()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(playing ? "Pause" : "Play")
            VStack(alignment: .leading, spacing: 2) {
                Text(frames[index].label(now: now)).font(.headline.monospacedDigit())
                if let valid = frames[index].validAt {
                    Text(Format.clock(valid, calendar: report.snapshot.calendar))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: .capsule)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(PrecipIntensity.allCases, id: \.self) { level in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(level.radarColor).frame(width: 18, height: 10)
                    Text(level.adjective).font(.caption)
                }
            }
        }
    }

    private func loadLatestTime() async {
        guard let (data, _) = try? await URLSession.shared.data(from: RadarTimeline.statusURL),
              let latest = RadarTimeline.latestValid(fromStatusJSON: data) else { return }
        // Same layers, now with real timestamps, so the map doesn't reload.
        frames = RadarTimeline.frames(latestValid: latest)
        now = .now
    }

    /// Loop through the frames, holding a beat on "now".
    private func play() async {
        guard playing else { return }
        while !Task.isCancelled {
            let isLast = index == frames.count - 1
            try? await Task.sleep(for: .milliseconds(isLast ? 1500 : 450))
            guard !Task.isCancelled else { return }
            index = isLast ? 0 : index + 1
            now = .now
        }
    }
}

extension PrecipIntensity {
    /// Legend swatch matching the repainted tiles.
    var radarColor: Color {
        let c = RadarPalette.rgba(for: self)
        let a = Double(c.a) / 255
        // Tile colors are premultiplied; undo that for SwiftUI.
        return Color(.sRGB, red: Double(c.r) / 255 / a, green: Double(c.g) / 255 / a,
                     blue: Double(c.b) / 255 / a, opacity: a)
    }
}
