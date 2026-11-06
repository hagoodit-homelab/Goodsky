import SwiftUI

@main
struct GoodskyApp: App {
    @State private var model = WeatherModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}
