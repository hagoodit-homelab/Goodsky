import GoodskyCore
import SwiftUI

struct SettingsView: View {
    @Environment(WeatherModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $model.settings.jacketBelowF, in: 35...80, step: 1) {
                        LabeledContent("Jacket below", value: Format.degrees(model.settings.jacketBelowF))
                    }
                    Stepper(value: $model.settings.coatBelowF, in: 0...model.settings.jacketBelowF, step: 1) {
                        LabeledContent("Real coat below", value: Format.degrees(model.settings.coatBelowF))
                    }
                    VStack(alignment: .leading) {
                        LabeledContent("Rain jacket at", value: "\(Format.percent(model.settings.rainChanceThreshold)) chance")
                        Slider(value: $model.settings.rainChanceThreshold, in: 0.1...0.9, step: 0.05)
                    }
                    Stepper(value: $model.settings.windyMph, in: 10...40, step: 1) {
                        LabeledContent("Windy at", value: Format.mph(model.settings.windyMph))
                    }
                } header: {
                    Text("Jacket call")
                } footer: {
                    Text("Uses the coldest feels-like temperature in your out-and-about window. Rain beats jacket.")
                }

                Section("Out and about") {
                    Picker("From", selection: $model.settings.windowStartHour) {
                        ForEach(0..<23, id: \.self) { Text(hourLabel($0)).tag($0) }
                    }
                    Picker("Until", selection: $model.settings.windowEndHour) {
                        ForEach((model.settings.windowStartHour + 1)...24, id: \.self) { Text(hourLabel($0)).tag($0) }
                    }
                }

                Section("Units") {
                    LabeledContent("Temperature", value: "°F")
                }

                Section {
                    Button("Reset to defaults", role: .destructive) {
                        model.settings = .default
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: model.settings.windowStartHour) { _, start in
                if model.settings.windowEndHour <= start { model.settings.windowEndHour = start + 1 }
            }
            .onChange(of: model.settings.jacketBelowF) { _, jacket in
                if model.settings.coatBelowF > jacket { model.settings.coatBelowF = jacket }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0, 24: "Midnight"
        case 12: "Noon"
        case ..<12: "\(hour) AM"
        default: "\(hour - 12) PM"
        }
    }
}
