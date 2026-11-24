import Foundation
import CoreLocation
import AVFoundation
import AudioToolbox

/// Kelio greičio riba ir greičio kameros iš OpenStreetMap (Overpass API, nemokama, be rakto).
/// OSM duomenis kuria savanoriai, todėl kai kurių kamerų ar ženklų gali trūkti.
@MainActor
final class RoadInfoService: ObservableObject {
    struct Camera: Hashable {
        let coordinate: CLLocationCoordinate2D
        let limit: Int?
        static func == (a: Camera, b: Camera) -> Bool { a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude }
        func hash(into h: inout Hasher) { h.combine(coordinate.latitude); h.combine(coordinate.longitude) }
    }

    /// Dabartinio kelio greičio riba (km/h), jei žinoma.
    @Published private(set) var roadLimit: Int?
    /// Artimiausia kamera priekyje (≤ 300 m).
    @Published private(set) var cameraAhead: (distance: CLLocationDistance, limit: Int?)?

    var camerasOn = true
    var beepOn = true
    var voiceOn = true

    private var cameras: [Camera] = []
    private var camerasCenter: CLLocation?
    private var limitCheckedAt: (CLLocation, Date)?
    private var warned: Set<Camera> = []
    private var lastBadBeep = Date.distantPast
    private let speech = AVSpeechSynthesizer()
    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    func update(with l: CLLocation, speedKmh: Double) {
        // Kameros: kraunam 5 km spinduliu, atnaujinam pavažiavus 2 km.
        if camerasOn, camerasCenter.map({ $0.distance(from: l) > 2000 }) ?? true {
            camerasCenter = l
            Task { await loadCameras(around: l) }
        }
        // Greičio riba: kas 15 s arba kas 150 m.
        if limitCheckedAt.map({ Date().timeIntervalSince($0.1) > 15 || $0.0.distance(from: l) > 150 }) ?? true {
            limitCheckedAt = (l, Date())
            Task { await loadLimit(at: l) }
        }
        checkCameras(l, speedKmh: speedKmh)
    }

    // MARK: Kameros

    private func checkCameras(_ l: CLLocation, speedKmh: Double) {
        guard camerasOn, l.course >= 0 else { cameraAhead = nil; return }
        var best: (Camera, CLLocationDistance)?
        for c in cameras {
            let cl = CLLocation(latitude: c.coordinate.latitude, longitude: c.coordinate.longitude)
            let d = l.distance(from: cl)
            guard d <= 300 else { continue }
            var diff = abs(bearing(from: l.coordinate, to: c.coordinate) - l.course)
            if diff > 180 { diff = 360 - diff }
            guard diff < 60 || d < 30 else { continue }   // tik priekyje
            if best == nil || d < best!.1 { best = (c, d) }
        }
        guard let found = best else { cameraAhead = nil; return }
        let cam = found.0, d = found.1
        let lim = cam.limit ?? roadLimit
        cameraAhead = (d, lim)
        if !warned.contains(cam) {
            warned.insert(cam)
            if beepOn { AudioServicesPlaySystemSound(1005) }
            if voiceOn {
                let t = "Greičio kamera po \(Int(d / 10) * 10) metrų" + (lim.map { ". Riba \($0)." } ?? ".")
                let u = AVSpeechUtterance(string: t)
                u.voice = AVSpeechSynthesisVoice(language: "lt-LT") ?? AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
                speech.speak(u)
            }
        }
        if let lim, speedKmh > Double(lim), beepOn, Date().timeIntervalSince(lastBadBeep) > 1 {
            lastBadBeep = Date()
            AudioServicesPlaySystemSound(1057)
        }
    }

    private func loadCameras(around l: CLLocation) async {
        let q = "[out:json][timeout:20];node[\"highway\"=\"speed_camera\"](around:5000,\(l.coordinate.latitude),\(l.coordinate.longitude));out;"
        guard let json = await overpass(q), let els = json["elements"] as? [[String: Any]] else { return }
        cameras = els.compactMap { e in
            guard let lat = e["lat"] as? Double, let lon = e["lon"] as? Double else { return nil }
            let tags = e["tags"] as? [String: String] ?? [:]
            return Camera(coordinate: .init(latitude: lat, longitude: lon), limit: parseSpeed(tags["maxspeed"]))
        }
    }

    // MARK: Greičio riba

    private func loadLimit(at l: CLLocation) async {
        let q = "[out:json][timeout:10];way(around:25,\(l.coordinate.latitude),\(l.coordinate.longitude))[\"highway\"][\"maxspeed\"];out tags 3;"
        guard let json = await overpass(q), let els = json["elements"] as? [[String: Any]] else { return }
        let limits = els.compactMap { ($0["tags"] as? [String: String]).flatMap { parseSpeed($0["maxspeed"]) } }
        roadLimit = limits.first
    }

    private func overpass(_ query: String) async -> [String: Any]? {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")".data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// "50", "50 km/h", "LT:urban" ir pan. → km/h.
func parseSpeed(_ s: String?) -> Int? {
    guard let s = s?.lowercased() else { return nil }
    if let n = Int(s.prefix { $0.isNumber }), n > 0 { return s.contains("mph") ? Int(Double(n) * 1.609) : n }
    if s.hasSuffix(":urban") { return 50 }
    if s.hasSuffix(":rural") { return 90 }
    if s.hasSuffix(":motorway") { return 130 }
    if s.hasSuffix(":trunk") || s.hasSuffix(":expressway") { return 110 }
    if s.hasSuffix(":living_street") { return 20 }
    return nil
}

func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
    let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180, Δλ = (b.longitude - a.longitude) * .pi / 180
    let y = sin(Δλ) * cos(φ2), x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
    return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}
