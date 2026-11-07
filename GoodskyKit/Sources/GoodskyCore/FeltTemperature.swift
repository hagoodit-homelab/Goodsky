import Foundation

/// Goodsky's own feels-like temperature.
///
/// WeatherKit's apparent temperature is basically wind chill below ~50°F and heat index above ~80°F.
/// In between it mostly repeats the air temperature, so a sunny 62° morning and a clear, breezy 62°
/// evening come out the same even though they feel ~15° apart. This adds what it leaves out:
///
/// | Factor | Adjustment |
/// |---|---|
/// | Sun on you, scaled by sun height and cloud cover | up to +8° |
/// | Sun down, clear sky (body radiates heat to the sky) | up to −3° |
/// | Wind (50–80°F only; WeatherKit covers it outside that band) | −0.5° per mph over 3, max −8° |
/// | Damp air (humidity ≥ 80%, below 65°F, 50–80°F band) | −2° |
/// | Temperature falling ≥ 2° in the hour | −2° |
/// | Temperature rising ≥ 1° in the hour | +1° |
/// | Evening after dark (5 PM–midnight): you've been out all day | −2° |
///
/// The numbers are starting estimates, loosely based on Steadman's apparent temperature. The 👍/👎
/// tuner moves the jacket thresholds if they run warm or cold for you.
/// Pure and deterministic: the same forecast always gives the same number.
public enum FeltTemperature {
    /// The mild band where we build feels-like from air temperature ourselves.
    static let mildBand: ClosedRange<Double> = 50...80

    public struct Breakdown: Sendable, Equatable {
        /// What we started from: air temperature in the mild band, WeatherKit's feels-like outside it.
        public var baseF: Double
        public var sun: Double = 0
        public var clearNight: Double = 0
        public var wind: Double = 0
        public var damp: Double = 0
        public var trend: Double = 0
        public var evening: Double = 0

        public var totalF: Double { baseF + sun + clearNight + wind + damp + trend + evening }
    }

    /// Copies of `hourly` with `feelsLikeF` replaced by Goodsky's feels-like.
    /// Hours are taken in date order; each hour's trend compares against the hour before it.
    public static func adjusted(_ hourly: [HourForecast], latitude: Double, longitude: Double,
                                calendar: Calendar) -> [HourForecast] {
        let sorted = hourly.sorted { $0.date < $1.date }
        return sorted.indices.map { i in
            var h = sorted[i]
            let prev = i > 0 && sorted[i].date.timeIntervalSince(sorted[i - 1].date) <= 3600 ? sorted[i - 1] : nil
            h.feelsLikeF = breakdown(h, previous: prev, latitude: latitude, longitude: longitude,
                                     calendar: calendar).totalF
            return h
        }
    }

    public static func breakdown(_ h: HourForecast, previous: HourForecast?, latitude: Double,
                                 longitude: Double, calendar: Calendar) -> Breakdown {
        let mild = mildBand.contains(h.temperatureF)
        var b = Breakdown(baseF: mild ? h.temperatureF : h.feelsLikeF)

        // Judge the sun at the middle of the hour.
        let sinElev = SolarPosition.sinElevation(at: h.date.addingTimeInterval(1800),
                                                 latitude: latitude, longitude: longitude)
        let sunUp = sinElev > 0

        // Sun and sky need cloud cover. Old cached snapshots don't have it; skip rather than guess.
        if let cloud = h.cloudCover.map({ min(max($0, 0), 1) }) {
            if sunUp {
                // Kasten–Czeplak: how much sunlight gets through the clouds.
                let clear = 1 - 0.75 * pow(cloud, 3.4)
                // Sun ~30° up (sin 0.5) or higher counts as full strength.
                b.sun = 8 * min(1, sinElev / 0.5) * clear
            } else {
                b.clearNight = -3 * (1 - cloud)
            }
        }

        if mild {
            b.wind = -min(8, max(0, h.windMph - 3) * 0.5)
            if let rh = h.humidity, rh >= 0.8, h.temperatureF < 65 { b.damp = -2 }
        }

        if let p = previous {
            let delta = h.temperatureF - p.temperatureF
            if delta <= -2 { b.trend = -2 } else if delta >= 1 { b.trend = 1 }
        }

        let hour = calendar.component(.hour, from: h.date)
        if !sunUp && hour >= 17 { b.evening = -2 }

        return b
    }
}

/// Where the sun is in the sky. NOAA's general solar position equations; good to well under a degree.
public enum SolarPosition {
    /// Sine of the sun's elevation above the horizon (negative when it's down).
    public static func sinElevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let dayOfYear = Double(utc.ordinality(of: .day, in: .year, for: date) ?? 1)
        let c = utc.dateComponents([.hour, .minute, .second], from: date)
        let hourUTC = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600

        let g = 2 * Double.pi / 365 * (dayOfYear - 1 + (hourUTC - 12) / 24)
        let eqTimeMin = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g)
            - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g)
            + 0.000907 * sin(2 * g) - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)

        let trueSolarMin = hourUTC * 60 + eqTimeMin + 4 * longitude
        let hourAngle = (trueSolarMin / 4 - 180) * .pi / 180
        let lat = latitude * .pi / 180
        return sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle)
    }
}
