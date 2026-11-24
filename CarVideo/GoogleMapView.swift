import SwiftUI
import MapKit

/// v8: Google žemėlapis programėlės viduje (Google Maps SDK for iOS).
/// Reikia savo Google Cloud API rakto (Nustatymai → Žemėlapis programėlėje).
/// Žemėlapio rodymas Maps SDK nemokamas; maršrutą vis tiek skaičiuoja Apple (MKDirections),
/// o linija nupiešiama ant Google žemėlapio. Google navigacijai (Navigation SDK) reikėtų atskiro, mokamo leidimo.
#if canImport(GoogleMaps)
import GoogleMaps

enum GoogleMapsSetup {
    private static var configuredKey: String?
    static func configure(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return false }
        if configuredKey == nil { GMSServices.provideAPIKey(k); configuredKey = k }
        return true
    }
}

struct GoogleMapView: UIViewRepresentable {
    let route: MKRoute?
    let location: CLLocation?
    let night: Bool

    func makeUIView(context: Context) -> GMSMapView {
        let opts = GMSMapViewOptions()
        opts.camera = GMSCameraPosition(latitude: location?.coordinate.latitude ?? 54.687, longitude: location?.coordinate.longitude ?? 25.28, zoom: 16, bearing: 0, viewingAngle: 45)
        let v = GMSMapView(options: opts)
        v.isMyLocationEnabled = true
        v.isTrafficEnabled = true
        v.settings.compassButton = true
        return v
    }

    func updateUIView(_ v: GMSMapView, context: Context) {
        v.overrideUserInterfaceStyle = night ? .dark : .light
        v.clear()
        if let r = route {
            let path = GMSMutablePath()
            let pts = r.polyline.points()
            for i in 0..<r.polyline.pointCount { path.add(pts[i].coordinate) }
            let line = GMSPolyline(path: path)
            line.strokeWidth = 7
            line.strokeColor = .systemBlue
            line.map = v
        }
        if let l = location {
            v.animate(to: GMSCameraPosition(target: l.coordinate, zoom: 16.5, bearing: l.course >= 0 ? l.course : 0, viewingAngle: 50))
        }
    }
}
#else
enum GoogleMapsSetup { static func configure(_ key: String) -> Bool { false } }
struct GoogleMapView: View {
    let route: MKRoute?; let location: CLLocation?; let night: Bool
    var body: some View { EmptyView() }
}
#endif
