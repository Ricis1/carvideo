// v19: tikslo paieška kaip Waze – rašai, iškart rodo pasiūlymus, paskutinius tikslus ir „Namo“.
import SwiftUI
import MapKit

@MainActor
final class PlaceCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let c = MKLocalSearchCompleter()
    override init() { super.init(); c.delegate = self; c.resultTypes = [.address, .pointOfInterest] }
    func update(_ q: String, near l: CLLocation?) {
        if let l { c.region = MKCoordinateRegion(center: l.coordinate, latitudinalMeters: 200_000, longitudinalMeters: 200_000) }
        if q.trimmingCharacters(in: .whitespaces).isEmpty { results = []; c.cancel() } else { c.queryFragment = q }
    }
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = Array(completer.results.prefix(12)); Task { @MainActor in self.results = r }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

struct RecentPlace: Codable, Hashable, Identifiable {
    var title: String; var subtitle: String; var lat: Double; var lon: Double
    var id: String { title + subtitle }
    var item: MKMapItem { let i = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: lat, longitude: lon))); i.name = title; return i }
    static var all: [RecentPlace] {
        get { (try? JSONDecoder().decode([RecentPlace].self, from: UserDefaults.standard.data(forKey: "recentPlaces") ?? Data())) ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(Array(newValue.prefix(8))), forKey: "recentPlaces") }
    }
    static func add(_ p: RecentPlace) { all = [p] + all.filter { $0.id != p.id } }
}

struct DestinationSearchSheet: View {
    let location: CLLocation?
    let home: String
    let onPick: (MKMapItem, String) -> Void
    @StateObject private var comp = PlaceCompleter()
    @State private var q = ""
    @State private var busy = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if q.isEmpty {
                    if !home.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button { Task { await pick(query: home, title: home) } } label: { Label("Namo", systemImage: "house.fill") }
                    }
                    let rec = RecentPlace.all
                    if !rec.isEmpty {
                        Section("Neseniai") {
                            ForEach(rec) { r in
                                Button { finish(r.item, r.title) } label: { row(r.title, r.subtitle, "clock") }
                            }
                        }
                    }
                } else {
                    ForEach(comp.results, id: \.self) { r in
                        Button { Task { await pick(completion: r) } } label: { row(r.title, r.subtitle, r.subtitle.isEmpty ? "magnifyingglass" : "mappin.circle.fill") }
                    }
                    if comp.results.isEmpty {
                        Button { Task { await pick(query: q, title: q) } } label: { row("Ieškoti „\(q)“", "", "magnifyingglass") }
                    }
                }
            }
            .overlay { if busy { ProgressView().controlSize(.large) } }
            .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Kur važiuojam?")
            .searchFocused($focused)
            .onSubmit(of: .search) { Task { await pick(query: q, title: q) } }
            .onChange(of: q) { _, v in comp.update(v, near: location) }
            .onAppear { focused = true }
            .navigationTitle("Kur važiuojam?").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Uždaryti") { dismiss() } } }
        }
    }

    private func row(_ t: String, _ s: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(t).foregroundStyle(.primary)
                if !s.isEmpty { Text(s).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func pick(completion r: MKLocalSearchCompletion) async {
        busy = true; defer { busy = false }
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: r)).start().mapItems.first else { return }
        finish(item, r.title, subtitle: r.subtitle)
    }
    private func pick(query: String, title: String) async {
        let t = query.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }
        busy = true; defer { busy = false }
        let req = MKLocalSearch.Request(); req.naturalLanguageQuery = t
        if let l = location { req.region = MKCoordinateRegion(center: l.coordinate, latitudinalMeters: 200_000, longitudinalMeters: 200_000) }
        guard let item = try? await MKLocalSearch(request: req).start().mapItems.first else { return }
        finish(item, title)
    }
    private func finish(_ item: MKMapItem, _ title: String, subtitle: String = "") {
        let c = item.placemark.coordinate
        RecentPlace.add(.init(title: title, subtitle: subtitle.isEmpty ? (item.placemark.title ?? "") : subtitle, lat: c.latitude, lon: c.longitude))
        onPick(item, title); dismiss()
    }
}
