import Foundation
import MapKit
import AVFoundation

// MARK: - Degalinės ir įkrovimo stotelės (Apple Maps duomenys)

@MainActor
final class StationFinder: ObservableObject {
    struct Station: Identifiable {
        let id = UUID()
        let item: MKMapItem
        let distance: CLLocationDistance
        let isEV: Bool
    }
    @Published private(set) var fuel: [Station] = []
    @Published private(set) var ev: [Station] = []
    @Published private(set) var loading = false

    /// Ieško 5 km spinduliu. Kainų Apple nepateikia.
    func search(near l: CLLocation?) async {
        guard let l else { return }
        loading = true
        defer { loading = false }
        fuel = await find(.gasStation, near: l)
        ev = await find(.evCharger, near: l)
    }

    private func find(_ cat: MKPointOfInterestCategory, near l: CLLocation) async -> [Station] {
        let req = MKLocalPointsOfInterestRequest(center: l.coordinate, radius: 5000)
        req.pointOfInterestFilter = MKPointOfInterestFilter(including: [cat])
        guard let items = try? await MKLocalSearch(request: req).start().mapItems else { return [] }
        return items.map { i in
            let loc = i.placemark.location ?? CLLocation(latitude: i.placemark.coordinate.latitude, longitude: i.placemark.coordinate.longitude)
            return Station(item: i, distance: loc.distance(from: l), isEV: cat == .evCharger)
        }
        .sorted { $0.distance < $1.distance }
    }
}

// MARK: - Pastatytas automobilis

struct ParkedCar: Codable {
    var latitude: Double
    var longitude: Double
    var date: Date
    var place: String?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

enum ParkingStore {
    private static let key = "parkedCar.v1"
    static func load() -> ParkedCar? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(ParkedCar.self, from: $0) }
    }
    static func save(_ p: ParkedCar?) {
        if let p, let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

// MARK: - Orai maršrute (Open-Meteo, nemokama, be rakto)

@MainActor
final class RouteWeather: ObservableObject {
    struct Warning: Equatable { let title: String; let detail: String }
    @Published private(set) var warning: Warning?
    @Published private(set) var summary: String?
    private let speech = AVSpeechSynthesizer()
    var voiceOn = true

    /// Tikrina 3 taškus maršrute: pradžią, vidurį ir pabaigą.
    func check(route: MKRoute) async {
        let n = route.polyline.pointCount
        guard n > 0 else { return }
        let pts = route.polyline.points()
        let idx = [0, n / 2, n - 1]
        var worst: Warning?
        var temps: [Double] = []
        for i in idx {
            let c = pts[i].coordinate
            guard let w = await current(at: c) else { continue }
            temps.append(w.t)
            if let r = risk(w), worst == nil || r.title.contains("plikledis") { worst = r }
        }
        if let mn = temps.min(), let mx = temps.max() {
            summary = mn == mx ? "\(Int(mn.rounded())) °C" : "\(Int(mn.rounded()))…\(Int(mx.rounded())) °C"
        }
        warning = worst
        if let worst, voiceOn {
            let u = AVSpeechUtterance(string: worst.title + ". " + worst.detail)
            u.voice = AVSpeechSynthesisVoice(language: "lt-LT") ?? AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
            speech.speak(u)
        }
    }

    func dismiss() { warning = nil }

    private struct Now { let t: Double; let code: Int; let vis: Double }

    private func current(at c: CLLocationCoordinate2D) async -> Now? {
        let s = String(format: "https://api.open-meteo.com/v1/forecast?latitude=%.3f&longitude=%.3f&current=temperature_2m,weather_code,visibility", c.latitude, c.longitude)
        guard let url = URL(string: s), let res = try? await URLSession.shared.data(from: url),
              let json = (try? JSONSerialization.jsonObject(with: res.0)) as? [String: Any],
              let cur = json["current"] as? [String: Any],
              let t = cur["temperature_2m"] as? Double else { return nil }
        return Now(t: t, code: cur["weather_code"] as? Int ?? 0, vis: cur["visibility"] as? Double ?? 10000)
    }

    private func risk(_ w: Now) -> Warning? {
        if w.t <= 1, (51...77).contains(w.code) || (80...86).contains(w.code) {
            return Warning(title: "Galimas plikledis", detail: "Kelyje \(Int(w.t.rounded())) °C ir krituliai. Važiuok atsargiai.")
        }
        if w.code == 45 || w.code == 48 || w.vis < 1000 {
            return Warning(title: "Rūkas kelyje", detail: "Matomumas apie \(Int(w.vis)) m.")
        }
        if (95...99).contains(w.code) {
            return Warning(title: "Perkūnija maršrute", detail: "Gali būti stiprus lietus.")
        }
        return nil
    }
}
