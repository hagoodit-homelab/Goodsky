import CoreGraphics
import GoodskyCore
import ImageIO
import MapKit
import UniformTypeIdentifiers

/// One radar frame as a MapKit tile overlay. Downloads IEM's N0Q tile and repaints it in
/// Goodsky's light/moderate/heavy colors before MapKit sees it.
final class RadarTileOverlay: MKTileOverlay {
    let frame: RadarFrame

    init(frame: RadarFrame) {
        self.frame = frame
        super.init(urlTemplate: frame.urlTemplate)
        canReplaceMapContent = false
        minimumZ = RadarTimeline.minimumZoom
        maximumZ = RadarTimeline.maximumZoom
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let request = URLRequest(url: url(forTilePath: path), cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15)
        RadarTileOverlay.session.dataTask(with: request) { data, response, error in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else {
                result(nil, error ?? URLError(.badServerResponse))
                return
            }
            result(RadarTileRecolorer.recolor(png: data) ?? data, nil)
        }.resume()
    }

    /// IEM sends `max-age=300`, which lines up with how often the frames roll forward.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 64 << 20)
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()
}

/// PNG in → repainted PNG out. The palette logic itself is in GoodskyCore (`RadarPalette`) and unit-tested.
enum RadarTileRecolorer {
    static func recolor(png: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width, height = image.height, count = width * height * 4
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: info),
              let base = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // N0Q pixels are fully opaque or fully transparent, so premultiplication leaves colors intact.
        let buffer = base.bindMemory(to: UInt8.self, capacity: count)
        var pixels = Array(UnsafeBufferPointer(start: buffer, count: count))
        RadarPalette.recolor(&pixels)
        pixels.withUnsafeBufferPointer { buffer.update(from: $0.baseAddress!, count: count) }

        guard let output = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
