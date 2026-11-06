import GoodskyCore
import MapKit
import SwiftUI

/// MKMapView with one recolored tile overlay per radar frame. All frames load up front; playback
/// just swaps which one is visible, so the loop is smooth once tiles are cached.
struct RadarMapView: UIViewRepresentable {
    let center: CLLocationCoordinate2D
    let frames: [RadarFrame]
    let visibleIndex: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.pointOfInterestFilter = .excludingAll
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = true
        map.showsCompass = false
        // Keep zoom in the range where the radar is readable.
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 15_000,
                                                        maxCenterCoordinateDistance: 2_000_000)
        let span = MKCoordinateSpan(latitudeDelta: RadarTimeline.defaultSpanDegrees,
                                    longitudeDelta: RadarTimeline.defaultSpanDegrees)
        map.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)

        let pin = MKPointAnnotation()
        pin.coordinate = center
        map.addAnnotation(pin)

        context.coordinator.install(frames: frames, on: map)
        context.coordinator.show(index: visibleIndex)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.show(index: visibleIndex)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var renderers: [String: MKTileOverlayRenderer] = [:]
        private var layers: [String] = []
        private var shown: Int?

        func install(frames: [RadarFrame], on map: MKMapView) {
            layers = frames.map(\.layer)
            map.addOverlays(frames.map(RadarTileOverlay.init(frame:)), level: .aboveRoads)
        }

        func show(index: Int) {
            guard index != shown else { return }
            shown = index
            for (i, layer) in layers.enumerated() {
                guard let renderer = renderers[layer] else { continue }
                // Hidden frames stay barely-there instead of 0 so MapKit keeps loading their tiles.
                renderer.alpha = i == index ? 1 : 0.001
                renderer.setNeedsDisplay()
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tile = overlay as? RadarTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKTileOverlayRenderer(tileOverlay: tile)
            let index = layers.firstIndex(of: tile.frame.layer)
            renderer.alpha = index == shown ? 1 : 0.001
            renderers[tile.frame.layer] = renderer
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "forecast") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "forecast")
            view.annotation = annotation
            view.glyphImage = UIImage(systemName: "house.fill")
            view.markerTintColor = .systemOrange
            view.displayPriority = .required
            return view
        }
    }
}
