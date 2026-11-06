import Foundation
import Testing
@testable import GoodskyCore

@Suite struct RadarTests {
    @Test func rampHasEveryIndexOnce() {
        #expect(RadarPalette.ramp.count == 255)
        #expect(Set(RadarPalette.ramp).count == 255)
    }

    @Test func knownColorsDecodeToDBZ() {
        #expect(RadarPalette.dBZ(r: 0x85, g: 0x71, b: 0x8F) == -32)   // index 1
        #expect(RadarPalette.dBZ(r: 0x0F, g: 0xBC, b: 0x15) == 24)    // green
        #expect(RadarPalette.dBZ(r: 0xFF, g: 0xE2, b: 0x00) == 40)    // yellow
        #expect(RadarPalette.dBZ(r: 0xD5, g: 0x00, b: 0x00) == 52)    // red
    }

    @Test func nearMissColorsStillDecode() {
        // One step off in each channel (e.g. after color management) still maps to 40 dBZ yellow.
        #expect(RadarPalette.dBZ(r: 0xFE, g: 0xE3, b: 0x01) == 40)
        // Nothing close by: rejected.
        #expect(RadarPalette.dBZ(r: 0, g: 0, b: 0) == nil)
    }

    @Test func dbzBandsMatchSummaryBands() {
        #expect(PrecipIntensity(dBZ: 10) == nil)     // drizzle/clutter hidden
        #expect(PrecipIntensity(dBZ: 15) == .light)
        #expect(PrecipIntensity(dBZ: 24) == .light)
        #expect(PrecipIntensity(dBZ: 32) == .moderate)
        #expect(PrecipIntensity(dBZ: 40) == .heavy)
        #expect(PrecipIntensity(dBZ: 60) == .heavy)
    }

    @Test func recolorRepaintsAndClears() {
        var px: [UInt8] = [
            0, 0, 0, 0,                 // transparent stays clear
            0xFF, 0xE2, 0x00, 0xFF,     // 40 dBZ → heavy
            0x0F, 0xBC, 0x15, 0xFF,     // 24 dBZ → light
            0x90, 0x98, 0xB4, 0xFF,     // 0 dBZ clutter → cleared
        ]
        let found = RadarPalette.recolor(&px)
        #expect(found)
        let heavy = RadarPalette.rgba(for: .heavy), light = RadarPalette.rgba(for: .light)
        #expect(Array(px[0..<4]) == [0, 0, 0, 0])
        #expect(Array(px[4..<8]) == [heavy.r, heavy.g, heavy.b, heavy.a])
        #expect(Array(px[8..<12]) == [light.r, light.g, light.b, light.a])
        #expect(Array(px[12..<16]) == [0, 0, 0, 0])
    }

    @Test func recolorOfDryTileReportsNothing() {
        var px: [UInt8] = [0, 0, 0, 0, 0x90, 0x98, 0xB4, 0xFF]
        #expect(!RadarPalette.recolor(&px))
    }

    @Test func framesCoverThePastHourOldestFirst() {
        let latest = Fixtures.date(hour: 12, minute: 10)
        let frames = RadarTimeline.frames(latestValid: latest)
        #expect(frames.count == 12)
        #expect(frames.first?.layer == "nexrad-n0q-900913-m55m")
        #expect(frames[10].layer == "nexrad-n0q-900913-m05m")
        #expect(frames.last?.layer == "nexrad-n0q-900913")
        #expect(frames.first?.validAt == Fixtures.date(hour: 11, minute: 15))
        #expect(frames.last?.tileURL(z: 9, x: 143, y: 195).absoluteString
                == "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/9/143/195.png")
        #expect(frames.last?.urlTemplate.hasSuffix("/nexrad-n0q-900913/{z}/{x}/{y}.png") == true)
    }

    @Test func frameLabels() {
        let latest = Fixtures.date(hour: 12, minute: 10)
        let now = Fixtures.date(hour: 12, minute: 13)
        let frames = RadarTimeline.frames(latestValid: latest)
        #expect(frames.last?.label(now: now) == "now")
        #expect(frames[9].label(now: now) == "15 min ago")   // valid 12:00, 13 min old → rounds to 15
        #expect(frames[0].label(now: now) == "60 min ago")   // valid 11:15, 58 min old
        // Without a known valid time, fall back to the layer offset.
        let unknown = RadarTimeline.frames(latestValid: nil)
        #expect(unknown[0].label(now: now) == "55 min ago")
        #expect(unknown.last?.label(now: now) == "now")
    }

    @Test func parsesStatusJSON() {
        let json = #"{"meta": {"vcp": null, "product": "N0Q", "site": "USCOMP", "valid": "2026-11-06T12:10:00Z"}}"#
        let date = RadarTimeline.latestValid(fromStatusJSON: Data(json.utf8))
        #expect(date == ISO8601DateFormatter().date(from: "2026-11-06T12:10:00Z"))
        #expect(RadarTimeline.latestValid(fromStatusJSON: Data("nope".utf8)) == nil)
    }
}
