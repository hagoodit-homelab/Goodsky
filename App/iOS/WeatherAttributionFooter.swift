import GoodskyWeather
import SwiftUI

/// Apple Weather trademark + legal link. Required by the WeatherKit terms; don't remove it.
struct WeatherAttributionFooter: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var info: WeatherAttributionLoader.Info?

    var body: some View {
        VStack(spacing: 6) {
            if let info {
                AsyncImage(url: colorScheme == .dark ? info.darkMarkURL : info.lightMarkURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text("Apple Weather").font(.footnote.bold())
                }
                .frame(height: 14)
                Link("Other data sources", destination: info.legalPageURL)
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .task { info = await WeatherAttributionLoader.load() }
    }
}
