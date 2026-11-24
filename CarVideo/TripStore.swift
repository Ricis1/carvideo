import Foundation
import CoreLocation

struct Trip: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var meters: Double
    var maxKmh: Double
    var destination: String?
    /// v10: kelionių žurnalas – darbo kelionė ir maršruto taškai [platuma, ilguma].
    var business: Bool? = nil
    var path: [[Double]]? = nil

    var km: Double { meters / 1000 }
    var minutes: Double { end.timeIntervalSince(start) / 60 }
    var avgKmh: Double { minutes > 0 ? km / (minutes / 60) : 0 }

}

/// Įrašo keliones automatiškai: prasideda pajudėjus (> 8 km/h),
/// baigiasi po 5 min stovėjimo arba kai baigiamas maršrutas.
@MainActor
final class TripStore: ObservableObject {
    @Published private(set) var trips: [Trip] = []
    @Published private(set) var current: Trip?
    private var last: CLLocation?
    private var stoppedSince: Date?
    private let key = "trips.v1"
    /// v9: „Pradėti kelionę“ skirtuke Greitis – kelionė prasideda iškart, net stovint.
    var manualStart = false
    /// Iškviečiama baigus kelionę su paskutine vieta (naudojama „kur palikau automobilį“).
    var onFinish: ((CLLocation, String?) -> Void)?

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let t = try? JSONDecoder().decode([Trip].self, from: d) { trips = t }
    }

    func update(with l: CLLocation, destination: String?) {
        let kmh = max(0, l.speed) * 3.6
        if current == nil {
            guard kmh > 8 || manualStart else { return }
            manualStart = false
            current = Trip(start: l.timestamp, end: l.timestamp, meters: 0, maxKmh: kmh, destination: destination, path: [[l.coordinate.latitude, l.coordinate.longitude]])
            last = l
            return
        }
        guard var t = current else { return }
        if let last, l.horizontalAccuracy >= 0, l.horizontalAccuracy < 50 {
            let d = l.distance(from: last)
            if d < 500 { t.meters += d }   // šuoliai dėl GPS klaidų ignoruojami
            if let p = t.path?.last, CLLocation(latitude: p[0], longitude: p[1]).distance(from: l) > 100 { t.path?.append([l.coordinate.latitude, l.coordinate.longitude]) }
        }
        last = l
        t.end = l.timestamp
        t.maxKmh = max(t.maxKmh, kmh)
        if let destination { t.destination = destination }
        current = t
        if kmh < 3 {
            if stoppedSince == nil { stoppedSince = l.timestamp }
            if let s = stoppedSince, l.timestamp.timeIntervalSince(s) > 300 { finish() }
        } else {
            stoppedSince = nil
        }
    }

    func finish() {
        guard let t = current else { return }
        if let l = last { onFinish?(l, t.destination) }
        current = nil; last = nil; stoppedSince = nil
        guard t.meters > 200 else { return }
        trips.insert(t, at: 0)
        if trips.count > 200 { trips.removeLast(trips.count - 200) }
        save()
    }

    /// v9: perskaito keliones iš naujo (jas gali įrašyti ir kitas ekranas).
    func reload() {
        if let d = UserDefaults.standard.data(forKey: key), let t = try? JSONDecoder().decode([Trip].self, from: d) { trips = t }
    }

    /// v9: statistika skirtukui Greitis.
    var best: Trip? { trips.max(by: { $0.maxKmh < $1.maxKmh }) }
    var totalKm: Double { trips.reduce(0) { $0 + $1.km } }
    var streakDays: Int {
        let cal = Calendar.current
        let days = Set(trips.map { cal.startOfDay(for: $0.start) })
        var d = cal.startOfDay(for: Date())
        if !days.contains(d) { d = cal.date(byAdding: .day, value: -1, to: d)! }
        var n = 0
        while days.contains(d) { n += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
        return n
    }

    /// v10: pažymėti kaip darbo / asmeninę kelionę.
    func toggleBusiness(_ id: UUID) {
        guard let i = trips.firstIndex(where: { $0.id == id }) else { return }
        trips[i].business = !(trips[i].business ?? false); save()
    }

    /// v10: CSV eksportas (atsidaro Excel / Numbers).
    func csvFile() -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        var rows = ["Data;Tikslas;Km;Min;Vid. km/h;Maks. km/h;Tipas"]
        for t in trips {
            rows.append([f.string(from: t.start), (t.destination ?? "").replacingOccurrences(of: ";", with: ","), String(format: "%.2f", t.km), "\(Int(t.minutes))", "\(Int(t.avgKmh))", "\(Int(t.maxKmh))", (t.business ?? false) ? "Darbo" : "Asmeninė"].joined(separator: ";"))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelioniu-zurnalas.csv")
        try? ("\u{FEFF}" + rows.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func delete(at offsets: IndexSet) { trips.remove(atOffsets: offsets); save() }

    private func save() {
        if let d = try? JSONEncoder().encode(trips) { UserDefaults.standard.set(d, forKey: key) }
    }
}
