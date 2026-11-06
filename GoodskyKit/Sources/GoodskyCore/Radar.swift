import Foundation

// Minimal radar ("is rain coming at me?"): frame timeline, tile URLs, and the simplified color scale.
//
// Source: Iowa Environmental Mesonet (IEM) NEXRAD N0Q base-reflectivity composite, served as
// web-mercator tiles. Public domain, US only, no API key. It has the past hour in 5-minute steps
// but no nowcast; the minute-by-minute WeatherKit summary covers the future.
// RainViewer was ruled out: since Jan 2026 its free tier caps zoom at 7 (too coarse for a metro
// view) and dropped nowcast.

extension PrecipIntensity {
    /// Reflectivity below this is drizzle, ground clutter or virga. Not worth showing.
    public static let minimumRadarDBZ = 15.0

    /// Map radar reflectivity to the same light/moderate/heavy bands the next-hour summary uses,
    /// via the Marshall-Palmer Z-R relation (Z = 200 R^1.6). Returns `nil` below `minimumRadarDBZ`.
    public init?(dBZ: Double) {
        guard dBZ >= Self.minimumRadarDBZ else { return nil }
        let z = pow(10, dBZ / 10)
        let mmPerHour = pow(z / 200, 1 / 1.6)
        self.init(mmPerHour: mmPerHour)
    }
}

/// One frame of the radar loop.
public struct RadarFrame: Sendable, Equatable, Identifiable {
    /// IEM layer name, e.g. `nexrad-n0q-900913-m15m`.
    public var layer: String
    /// How many minutes older than the latest composite this frame is (0, 5, ..., 55).
    public var minutesBeforeLatest: Int
    /// When the radar scan was valid, if we know the latest composite time.
    public var validAt: Date?

    public var id: String { layer }

    /// Tile URL template in MapKit's `{z}/{x}/{y}` form.
    public var urlTemplate: String {
        "\(RadarTimeline.tileBase)/\(layer)/{z}/{x}/{y}.png"
    }

    public func tileURL(z: Int, x: Int, y: Int) -> URL {
        URL(string: "\(RadarTimeline.tileBase)/\(layer)/\(z)/\(x)/\(y).png")!
    }

    /// "now", "20 min ago". Rounded to 5 minutes, relative to `now`. Composites land a few
    /// minutes after their scan time, so anything under 7.5 minutes old reads as "now".
    public func label(now: Date) -> String {
        let age: Double
        if let validAt {
            age = now.timeIntervalSince(validAt) / 60
        } else {
            age = Double(minutesBeforeLatest)
        }
        if age < 7.5 { return "now" }
        return "\(Int((age / 5).rounded()) * 5) min ago"
    }
}

public enum RadarTimeline {
    /// The `/cache/` endpoint sends a 5-minute cache header, which matches how often the offsets roll.
    public static let tileBase = "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0"
    /// Small JSON file with the latest composite's valid time.
    public static let statusURL = URL(string: "https://mesonet.agron.iastate.edu/data/gis/images/4326/USCOMP/n0q_0.json")!
    public static let attribution = "Radar: Iowa Environmental Mesonet / NWS NEXRAD"
    /// IEM serves tiles to zoom 12, but the composite is ~1 km, so going deeper just shows blur.
    public static let maximumZoom = 10
    public static let minimumZoom = 4
    /// Roughly metro-wide: about 60 km across.
    public static let defaultSpanDegrees = 0.55

    /// Past hour, oldest first, ending with the latest composite.
    public static func frames(latestValid: Date?, step: Int = 5, maxAge: Int = 55) -> [RadarFrame] {
        stride(from: maxAge, through: 0, by: -step).map { age in
            let layer = age == 0
                ? "nexrad-n0q-900913"
                : "nexrad-n0q-900913-m" + (age < 10 ? "0\(age)" : "\(age)") + "m"
            return RadarFrame(layer: layer, minutesBeforeLatest: age,
                              validAt: latestValid?.addingTimeInterval(-Double(age) * 60))
        }
    }

    /// Parse IEM's status JSON: `{"meta": {"valid": "2026-11-06T12:10:00Z", ...}}`.
    public static func latestValid(fromStatusJSON data: Data) -> Date? {
        struct Status: Decodable {
            struct Meta: Decodable { var valid: String }
            var meta: Meta
        }
        guard let status = try? JSONDecoder().decode(Status.self, from: data) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: status.meta.valid)
    }
}

/// Converts IEM's N0Q tile colors back to dBZ, then repaints them in Goodsky's three-step scale.
public enum RadarPalette {
    /// Goodsky's simplified colors, premultiplied RGBA (light → heavy).
    public static func rgba(for intensity: PrecipIntensity) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        switch intensity {
        case .light: premultiplied(r: 0x5A, g: 0xC8, b: 0xFA, alpha: 0.55)   // soft blue
        case .moderate: premultiplied(r: 0x34, g: 0x6F, b: 0xF0, alpha: 0.75) // strong blue
        case .heavy: premultiplied(r: 0xB0, g: 0x3A, b: 0xE0, alpha: 0.9)     // purple
        }
    }

    private static func premultiplied(r: UInt8, g: UInt8, b: UInt8, alpha: Double)
        -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        func p(_ c: UInt8) -> UInt8 { UInt8((Double(c) * alpha).rounded()) }
        return (p(r), p(g), p(b), UInt8((255 * alpha).rounded()))
    }

    /// dBZ for an opaque N0Q pixel color, or `nil` if the color isn't in the ramp.
    ///
    /// Exact match first. If decoding nudged the color slightly (color management, resampling),
    /// fall back to the nearest ramp color within `tolerance` (sum of squared channel differences).
    public static func dBZ(r: UInt8, g: UInt8, b: UInt8, tolerance: Int = 48) -> Double? {
        let key = UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
        if let index = lookup[key] { return Double(index) * 0.5 - 32.5 }
        var best: (index: Int, distance: Int)?
        for (i, c) in ramp.enumerated() {
            let dr = Int(r) - Int(c >> 16 & 0xFF), dg = Int(g) - Int(c >> 8 & 0xFF), db = Int(b) - Int(c & 0xFF)
            let d = dr * dr + dg * dg + db * db
            if d <= tolerance, d < (best?.distance ?? .max) { best = (i + 1, d) }
        }
        return best.map { Double($0.index) * 0.5 - 32.5 }
    }

    public static func intensity(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> PrecipIntensity? {
        guard a > 0, let dbz = dBZ(r: r, g: g, b: b) else { return nil }
        return PrecipIntensity(dBZ: dbz)
    }

    /// Recolor a tile in place. `pixels` is 8-bit RGBA, any premultiplication (N0Q tiles are fully
    /// opaque or fully transparent, so it doesn't matter). Output is premultiplied RGBA.
    /// Returns true when any precipitation was found.
    @discardableResult
    public static func recolor(_ pixels: inout [UInt8]) -> Bool {
        var any = false
        var cache = [UInt32: PrecipIntensity?]()   // tiles reuse a handful of colors
        var i = 0
        while i + 3 < pixels.count {
            let key = UInt32(pixels[i]) << 24 | UInt32(pixels[i + 1]) << 16 | UInt32(pixels[i + 2]) << 8 | UInt32(pixels[i + 3])
            let level: PrecipIntensity?
            if let hit = cache[key] {
                level = hit
            } else {
                level = intensity(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2], a: pixels[i + 3])
                cache[key] = level
            }
            if let level {
                let c = rgba(for: level)
                pixels[i] = c.r; pixels[i + 1] = c.g; pixels[i + 2] = c.b; pixels[i + 3] = c.a
                any = true
            } else {
                pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
            }
            i += 4
        }
        return any
    }

    /// Color → ramp index (1...255). dBZ = index × 0.5 − 32.5.
    static let lookup: [UInt32: Int] = {
        var d = [UInt32: Int](minimumCapacity: ramp.count)
        for (i, c) in ramp.enumerated() { d[c] = i + 1 }
        return d
    }()

    /// IEM `composite_n0q` color ramp, indexes 1...255 (from pyIEM `data/ramps/composite_n0q.txt`).
    static let ramp: [UInt32] = [
        0x85718F, 0x85728F, 0x86738D, 0x87758B, 0x87768B, 0x887789, 0x897987, 0x897A87,
        0x8A7B85, 0x8B7D84, 0x8B7E84, 0x8C7F82, 0x8D8180, 0x8D8280, 0x8E837E, 0x8F847C,
        0x8F857C, 0x90877B, 0x918879, 0x918979, 0x928B77, 0x938D75, 0x969153, 0x989457,
        0x9B975B, 0x9D9A60, 0xA09D64, 0xA3A068, 0xA5A36D, 0xA8A671, 0xAAA976, 0xADAC7A,
        0xB0AF7E, 0xB2B283, 0xB7B88C, 0xBABB90, 0xBDBE94, 0xBFC199, 0xC2C49D, 0xC4C7A2,
        0xC7CAA6, 0xCACDAA, 0xCCD0AF, 0xD2D4B4, 0xCFD2B4, 0xC9CCB4, 0xC6C9B4, 0xC3C7B4,
        0xC0C4B4, 0xBDC1B4, 0xB9BEB4, 0xB6BBB4, 0xB3B9B4, 0xB0B6B4, 0xADB3B4, 0xAAB0B4,
        0xA4ABB4, 0xA0A8B4, 0x9DA5B4, 0x9AA2B4, 0x97A0B4, 0x949DB4, 0x919AB4, 0x949BB5,
        0x9098B4, 0x8C95B3, 0x8892B2, 0x808CB0, 0x7C89AF, 0x7886AE, 0x7483AC, 0x7080AB,
        0x6C7DAA, 0x6779A9, 0x6376A8, 0x5F73A7, 0x5B70A6, 0x576DA4, 0x4F67A2, 0x4B64A1,
        0x4761A0, 0x435E9F, 0x415B9E, 0x4361A2, 0x4568A6, 0x486FAA, 0x4A76AE, 0x4D7DB2,
        0x4F84B6, 0x518BBB, 0x5699C3, 0x599FC7, 0x5BA6CB, 0x5EADCF, 0x60B4D4, 0x62BBD8,
        0x65C2DC, 0x67C9E0, 0x6AD0E4, 0x6FD6E8, 0x68D6D7, 0x59D6B3, 0x52D6A2, 0x4BD690,
        0x43D67E, 0x3CD66D, 0x35D65B, 0x11D518, 0x11D117, 0x10CD17, 0x10C816, 0x10C416,
        0x0FBC15, 0x0FB714, 0x0EB314, 0x0EAF13, 0x0EAB13, 0x0DA612, 0x0DA212, 0x0D9E11,
        0x0C9911, 0x0C9510, 0x0C9110, 0x0B880F, 0x0B840E, 0x0A800E, 0x0A7C0D, 0x0A770D,
        0x09730C, 0x096F0C, 0x096B0B, 0x08660B, 0x08620A, 0x095E09, 0x327308, 0x467D08,
        0x5B8807, 0x6F9207, 0x849D06, 0x98A806, 0xADB205, 0xC1BD05, 0xD6C704, 0xEAD204,
        0xFFE200, 0xFFD800, 0xFFD300, 0xFFCE00, 0xFFC900, 0xFFC400, 0xFFC000, 0xFFBB00,
        0xFFB600, 0xFFB100, 0xFFAC00, 0xFFA700, 0xFFA200, 0xFF9900, 0xFF9400, 0xFF8F00,
        0xFF8A00, 0xFF8500, 0xFF8000, 0xFF0000, 0xF80000, 0xF10000, 0xEA0000, 0xE30000,
        0xD50000, 0xCD0000, 0xC60000, 0xBF0000, 0xB80000, 0xB10000, 0xAA0000, 0xA30000,
        0x9B0000, 0x940000, 0x8D0000, 0x7F0000, 0x780000, 0x710000, 0xFFFFFF, 0xFFF5FF,
        0xFFEAFF, 0xFFDFFF, 0xFFD4FF, 0xFFC9FF, 0xFFBEFF, 0xFFB3FF, 0xFF9DFF, 0xFF92FF,
        0xFF75FF, 0xFC6BFD, 0xF960FA, 0xF656F7, 0xF34BF4, 0xF040F1, 0xED36EF, 0xEA2BEC,
        0xE720E9, 0xE10BE3, 0xB200FF, 0xAC00FC, 0xA400F7, 0x9B00F4, 0x9300EF, 0x8800EA,
        0x8300E8, 0x7900E2, 0x7200DD, 0x6900DB, 0x05ECF0, 0x05EBF0, 0x05EAF0, 0x05DDE0,
        0x05DCE0, 0x05DBE0, 0x05CDD0, 0x05CCD0, 0x04BDC0, 0x04BCC0, 0x04BBC0, 0x04AEB0,
        0x04ADB0, 0x049EA0, 0x049DA0, 0x049CA0, 0x038E90, 0x038D90, 0x038C90, 0x037E80,
        0x037D80, 0x036F70, 0x036E70, 0x036D70, 0x025F60, 0x025E60, 0x024F50, 0x024E50,
        0x024D50, 0x023F40, 0x023E40, 0x023D40, 0x013030, 0x012F30, 0x012020, 0x011F20,
        0x011E20, 0x3A67B5, 0x3A66B5, 0x3A65B5, 0x3A64B5, 0x3A63B5, 0x3A62B5,
    ]
}
