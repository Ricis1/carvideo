// v15: žemėlapiai ir maršrutai be interneto (vaizdo registratorius išimtas v17).
// Kiekvieną funkciją galima išjungti: Nustatymai → v15.
import SwiftUI
import AVFoundation
import AVKit
import Network
import MapKit
import MapLibre

enum V15 { static func on(_ k: String) -> Bool { UserDefaults.standard.object(forKey: "f." + k) as? Bool ?? true } }

struct V15Section: View {
    @AppStorage("f.offline") private var offline = true
    @ObservedObject var maps = OfflineMaps.shared
    var body: some View {
        Section {
            Toggle(isOn: $offline) { Label { VStack(alignment: .leading) { Text("Žemėlapiai be interneto"); Text("Atsisiųstos šalys veikia ir be ryšio").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "wifi.slash") } }
            if offline { NavigationLink("Atsisiųsti šalis (\(maps.downloaded.count))") { OfflineMapsView() } }
        } header: { Text("v15") }
    }
}

// v17: vaizdo registratorius išimtas (užpildydavo telefono atmintį).

// MARK: - 2. Žemėlapiai be interneto (MapLibre + OpenFreeMap, nemokama, be rakto)
struct OfflineRegion: Identifiable { let id: String; let name: LocalizedStringKey; let bounds: (Double, Double, Double, Double) }   // pietūs, vakarai, šiaurė, rytai

@MainActor
final class OfflineMaps: NSObject, ObservableObject {
    static let shared = OfflineMaps()
    static let style = URL(string: "https://tiles.openfreemap.org/styles/liberty")!
    static let regions: [OfflineRegion] = [
        .init(id: "LT", name: "Lietuva", bounds: (53.89, 20.93, 56.45, 26.84)), .init(id: "LV", name: "Latvija", bounds: (55.67, 20.97, 58.09, 28.24)),
        .init(id: "EE", name: "Estija", bounds: (57.51, 21.76, 59.68, 28.21)), .init(id: "PL", name: "Lenkija", bounds: (49.0, 14.12, 54.84, 24.15)),
        .init(id: "DE", name: "Vokietija", bounds: (47.27, 5.87, 55.06, 15.04)), .init(id: "FI", name: "Suomija", bounds: (59.8, 20.55, 70.09, 31.59)),
        .init(id: "SE", name: "Švedija", bounds: (55.34, 11.03, 69.06, 24.17)), .init(id: "FR", name: "Prancūzija", bounds: (41.33, -5.14, 51.09, 9.56)),
        .init(id: "ES", name: "Ispanija", bounds: (35.95, -9.39, 43.79, 3.32)), .init(id: "IT", name: "Italija", bounds: (36.62, 6.63, 47.09, 18.52)),
        .init(id: "GB", name: "Jungtinė Karalystė", bounds: (49.9, -8.65, 60.86, 1.77)),
    ]
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var downloaded: Set<String> = []
    @Published private(set) var online = true
    private let monitor = NWPathMonitor()

    override init() {
        super.init()
        monitor.pathUpdateHandler = { [weak self] p in Task { @MainActor in self?.online = p.status == .satisfied } }
        monitor.start(queue: .global())
        NotificationCenter.default.addObserver(self, selector: #selector(packProgress(_:)), name: .MLNOfflinePackProgressChanged, object: nil)
        MLNOfflineStorage.shared.addObserver(self, forKeyPath: "packs", options: [.initial, .new], context: nil)
    }
    override nonisolated func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        Task { @MainActor in self.refresh() }
    }
    private func id(of p: MLNOfflinePack) -> String? { (try? JSONSerialization.jsonObject(with: p.context) as? [String: String])?["id"] }
    func refresh() {
        let packs = MLNOfflineStorage.shared.packs ?? []
        downloaded = Set(packs.filter { $0.progress.countOfResourcesExpected > 0 && $0.progress.countOfResourcesCompleted >= $0.progress.countOfResourcesExpected }.compactMap(id(of:)))
    }
    func download(_ r: OfflineRegion) {
        let b = r.bounds
        let region = MLNTilePyramidOfflineRegion(styleURL: Self.style, bounds: MLNCoordinateBounds(sw: .init(latitude: b.0, longitude: b.1), ne: .init(latitude: b.2, longitude: b.3)), fromZoomLevel: 0, toZoomLevel: 13)
        let ctx = (try? JSONSerialization.data(withJSONObject: ["id": r.id])) ?? Data()
        progress[r.id] = 0
        MLNOfflineStorage.shared.addPack(for: region, withContext: ctx) { pack, _ in pack?.resume() }
    }
    func delete(_ id: String) {
        for p in MLNOfflineStorage.shared.packs ?? [] where self.id(of: p) == id { MLNOfflineStorage.shared.removePack(p) { _ in Task { @MainActor in self.refresh() } } }
    }
    @objc private func packProgress(_ n: Notification) {
        guard let p = n.object as? MLNOfflinePack, let id = id(of: p) else { return }
        let e = Double(max(1, p.progress.countOfResourcesExpected))
        progress[id] = Double(p.progress.countOfResourcesCompleted) / e
        if p.state == .complete { progress[id] = nil; refresh() }
    }
    /// Ar dabar rodyti žemėlapį iš telefono.
    var useOffline: Bool { V15.on("offline") && !online && !downloaded.isEmpty }
}

struct OfflineMapsView: View {
    @ObservedObject var maps = OfflineMaps.shared
    var body: some View {
        List {
            Section { Text("Atsisiųsk šalį – žemėlapis veiks ir be ryšio (užsienyje, miške, tuneliuose). Paskutinis maršrutas išsaugomas ir rodomas dingus internetui.").font(.callout).foregroundStyle(.secondary) }
            ForEach(OfflineMaps.regions) { r in
                HStack {
                    Text(r.name)
                    Spacer()
                    if let p = maps.progress[r.id] { ProgressView(value: p).frame(width: 100) }
                    else if maps.downloaded.contains(r.id) { Text("Atsisiųsta").foregroundStyle(.green); Button("Ištrinti", role: .destructive) { maps.delete(r.id) } }
                    else { Button("Atsisiųsti") { maps.download(r) } }
                }
            }
        }
        .navigationTitle("Žemėlapiai be interneto")
        .onAppear { maps.refresh() }
    }
}

/// Paskutinis maršrutas – kad būtų matomas ir dingus ryšiui.
enum OfflineRouteCache {
    struct Cached: Codable { let coords: [[Double]]; let steps: [String] }
    private static var url: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("last-route.json") }
    static func save(_ r: MKRoute) {
        let pts = r.polyline.points(); let n = r.polyline.pointCount
        let c = Cached(coords: (0..<n).map { [pts[$0].coordinate.latitude, pts[$0].coordinate.longitude] }, steps: r.steps.map(\.instructions).filter { !$0.isEmpty })
        try? JSONEncoder().encode(c).write(to: url)
    }
    static func load() -> Cached? { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Cached.self, from: $0) } }
}

struct OfflineMapView: UIViewRepresentable {
    let center: CLLocationCoordinate2D?
    func makeUIView(context: Context) -> MLNMapView {
        let m = MLNMapView(frame: .zero, styleURL: OfflineMaps.style)
        m.showsUserLocation = true; m.userTrackingMode = .followWithCourse; m.delegate = context.coordinator
        return m
    }
    func updateUIView(_ m: MLNMapView, context: Context) {}
    func makeCoordinator() -> Coord { Coord() }
    final class Coord: NSObject, MLNMapViewDelegate {
        func mapView(_ m: MLNMapView, didFinishLoading style: MLNStyle) {
            guard let c = OfflineRouteCache.load(), c.coords.count > 1 else { return }
            var pts = c.coords.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
            let line = MLNPolylineFeature(coordinates: &pts, count: UInt(pts.count))
            let src = MLNShapeSource(identifier: "route", shape: line, options: nil); style.addSource(src)
            let l = MLNLineStyleLayer(identifier: "route", source: src)
            l.lineColor = NSExpression(forConstantValue: UIColor.systemBlue); l.lineWidth = NSExpression(forConstantValue: 6); l.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(l)
        }
    }
}
