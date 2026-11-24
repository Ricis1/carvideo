// v14: muzika ir pasaulio radijas šalia žemėlapio, kuro ir įkrovimo kainos, pilnesni vertimai.
// Kiekvieną funkciją galima išjungti: Nustatymai → v14.
import SwiftUI
import MapKit
import AVFoundation
import MediaPlayer

enum V14 {
    static func on(_ k: String) -> Bool { UserDefaults.standard.object(forKey: "f." + k) as? Bool ?? true }
    /// Šalis iš nustatymų (v12), kitaip – iš telefono.
    static var country: String { let c = UserDefaults.standard.string(forKey: "country") ?? "auto"; return c == "auto" ? (Locale.current.region?.identifier ?? "LT") : c }
}

struct V14Section: View {
    @AppStorage("f.musicsplit") private var musicSplit = true
    @AppStorage("f.radio") private var radio = true
    @AppStorage("f.fuelprices") private var fuelPrices = true
    @AppStorage("tankerkoenigKey") private var tkKey = ""
    var body: some View {
        Section {
            Toggle(isOn: $musicSplit) { Label { VStack(alignment: .leading) { Text("Muzika šalia žemėlapio"); Text("Muzika atsidaro per pusę su žemėlapiu").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "music.note") } }
            Toggle(isOn: $radio) { Label { VStack(alignment: .leading) { Text("Pasaulio radijas"); Text("Tūkstančiai radijo stočių iš viso pasaulio, nemokamai").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "radio") } }
            Toggle(isOn: $fuelPrices) { Label { VStack(alignment: .leading) { Text("Kuro ir įkrovimo kainos"); Text("Pigiausios viršuje, kainas gali patikslinti ir vairuotojai").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "eurosign.circle") } }
            if fuelPrices {
                TextField("Tankerkönig raktas (Vokietija, nemokamas)", text: $tkKey).textInputAutocapitalization(.never)
            }
        } header: { Text("v14") } footer: { Text("Kainos: Prancūzija ir Austrija – oficialūs atviri duomenys be rakto; Vokietija – su nemokamu Tankerkönig raktu; kitur ir įkrovimui – vairuotojų pranešimai (reikia bendro serverio).") }
    }
}

// MARK: - 1. Muzika: šaltiniai
enum MusicSource: String, CaseIterable, Identifiable {
    case spotify, apple, radio, podcast
    var id: String { rawValue }
    var title: LocalizedStringKey { switch self { case .spotify: "Spotify"; case .apple: "Apple Music"; case .radio: "Radijas"; case .podcast: "Tinklalaidės" } }
}

// MARK: - 2. Pasaulio radijas (radio-browser.info – atvira, nemokama duomenų bazė)
struct RadioStation: Identifiable, Codable, Hashable {
    let stationuuid: String; let name: String; let url_resolved: String; let countrycode: String; let bitrate: Int; let favicon: String
    var id: String { stationuuid }
}

@MainActor
final class RadioPlayer: ObservableObject {
    @Published private(set) var stations: [RadioStation] = []
    @Published private(set) var current: RadioStation?
    @Published private(set) var playing = false
    @Published var favorites: [String] = UserDefaults.standard.stringArray(forKey: "radio.favs") ?? [] { didSet { UserDefaults.standard.set(favorites, forKey: "radio.favs") } }
    private let player = AVPlayer()

    func load(country: String? = nil) async {
        let cc = country ?? V14.country
        guard let url = URL(string: "https://all.api.radio-browser.info/json/stations/bycountrycodeexact/\(cc)?order=votes&reverse=true&limit=60&hidebroken=true") else { return }
        var req = URLRequest(url: url); req.setValue("CarVideo/14", forHTTPHeaderField: "User-Agent")
        guard let (d, _) = try? await URLSession.shared.data(for: req), let list = try? JSONDecoder().decode([RadioStation].self, from: d) else { return }
        stations = list.sorted { favorites.contains($0.id) && !favorites.contains($1.id) }
    }
    func play(_ s: RadioStation) {
        guard let u = URL(string: s.url_resolved) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player.replaceCurrentItem(with: AVPlayerItem(url: u)); player.play()
        current = s; playing = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: s.name, MPNowPlayingInfoPropertyIsLiveStream: true]
    }
    func toggle() { if playing { player.pause() } else { player.play() }; playing.toggle() }
    func step(_ d: Int) { guard let c = current, let i = stations.firstIndex(of: c), !stations.isEmpty else { if let f = stations.first { play(f) }; return }
        play(stations[(i + d + stations.count) % stations.count]) }
    func toggleFav(_ s: RadioStation) { if let i = favorites.firstIndex(of: s.id) { favorites.remove(at: i) } else { favorites.append(s.id) } }
}

/// Apple Music: grojama iš naudotojo bibliotekos per sistemos grotuvą (be papildomo leidimo iš Apple).
@MainActor
enum AppleMusicControl {
    static let p = MPMusicPlayerController.systemMusicPlayer
    static func toggle() { p.playbackState == .playing ? p.pause() : p.play() }
    static var title: String { p.nowPlayingItem?.title ?? "Apple Music" }
}

struct MusicPane: View {
    @AppStorage("musicSource") private var srcRaw = MusicSource.radio.rawValue
    @ObservedObject var radio: RadioPlayer
    private var src: MusicSource { MusicSource(rawValue: srcRaw) ?? .radio }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Šaltinis", selection: $srcRaw) {
                ForEach(MusicSource.allCases.filter { $0 != .radio || V14.on("radio") }) { Text($0.title).tag($0.rawValue) }
            }.pickerStyle(.segmented)
            switch src {
            case .radio: radioView
            case .apple:
                nowPlaying(title: AppleMusicControl.title, sub: "Apple Music") { AppleMusicControl.p.skipToPreviousItem() } play: { AppleMusicControl.toggle() } next: { AppleMusicControl.p.skipToNextItem() }
                Spacer()
            case .spotify, .podcast:
                // Spotify ir Podcasts neleidžia groti kitose programėlėse be jų SDK – atidarom jų programėlę.
                Text(src == .spotify ? "Spotify groja savo programėlėje. CarVideo atidarys ją, o muzika gros fone." : "Tinklalaidės groja Apple Podcasts programėlėje.").foregroundStyle(.secondary)
                Button(src == .spotify ? "Atidaryti Spotify" : "Atidaryti Podcasts") { UIApplication.shared.open(URL(string: src == .spotify ? "spotify://" : "podcasts://")!) }.buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LinearGradient(colors: [Color(red: 0.11, green: 0.17, blue: 0.29), .black], startPoint: .topLeading, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 14))
        .task { if radio.stations.isEmpty { await radio.load() } }
    }
    private var radioView: some View {
        VStack(alignment: .leading, spacing: 8) {
            nowPlaying(title: radio.current?.name ?? "Pasirink stotį", sub: radio.current.map { "GYVAI · \($0.countrycode) · \($0.bitrate) kbps" } ?? "") { radio.step(-1) } play: { radio.toggle() } next: { radio.step(1) }
            List(radio.stations) { s in
                HStack {
                    Button { radio.play(s) } label: { Text(s.name).lineLimit(1).foregroundStyle(radio.current == s ? .green : .primary) }
                    Spacer()
                    Button { radio.toggleFav(s) } label: { Image(systemName: radio.favorites.contains(s.id) ? "star.fill" : "star").foregroundStyle(.yellow) }.buttonStyle(.plain)
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
        }
    }
    private func nowPlaying(title: String, sub: String, prev: @escaping () -> Void, play: @escaping () -> Void, next: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.bold()).lineLimit(1)
            if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 22) {
                Button(action: prev) { Image(systemName: "backward.fill") }
                Button(action: play) { Image(systemName: "playpause.fill").font(.title2).frame(width: 52, height: 52).background(.white, in: Circle()).foregroundStyle(.black) }
                Button(action: next) { Image(systemName: "forward.fill") }
            }.font(.title3).foregroundStyle(.white)
        }
    }
}

// MARK: - 3. Kuro ir įkrovimo kainos
struct PricedStation: Identifiable {
    let id: String; let name: String; let coordinate: CLLocationCoordinate2D; let distance: CLLocationDistance
    var prices: [String: Double]   // "95", "D", "LPG", "kWh"
    let updated: Date?; let source: String
}

protocol FuelPriceProvider { func stations(near l: CLLocation) async -> [PricedStation] }

/// Prancūzija: prix-carburants (atviri duomenys, be rakto).
struct FranceProvider: FuelPriceProvider {
    func stations(near l: CLLocation) async -> [PricedStation] {
        let c = l.coordinate
        let q = "within_distance(geom, geom'POINT(\(c.longitude) \(c.latitude))', 5km)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let u = URL(string: "https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/prix-des-carburants-en-france-flux-instantane-v2/records?where=\(q)&limit=30"),
              let (d, _) = try? await URLSession.shared.data(from: u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let rs = j["results"] as? [[String: Any]] else { return [] }
        return rs.compactMap { r in
            guard let g = r["geom"] as? [String: Double], let lat = g["lat"], let lon = g["lon"] else { return nil }
            var p: [String: Double] = [:]
            if let v = r["sp95_prix"] as? Double { p["95"] = v }; if let v = r["e10_prix"] as? Double, p["95"] == nil { p["95"] = v }
            if let v = r["gazole_prix"] as? Double { p["D"] = v }; if let v = r["gplc_prix"] as? Double { p["LPG"] = v }
            let loc = CLLocation(latitude: lat, longitude: lon)
            return PricedStation(id: "\(r["id"] ?? UUID().uuidString)", name: (r["adresse"] as? String ?? "Station").capitalized, coordinate: loc.coordinate, distance: loc.distance(from: l), prices: p, updated: nil, source: "prix-carburants.gouv.fr")
        }
    }
}

/// Vokietija: Tankerkönig (oficialūs MTS-K duomenys, nemokamas raktas).
struct GermanyProvider: FuelPriceProvider {
    let key: String
    func stations(near l: CLLocation) async -> [PricedStation] {
        guard !key.isEmpty, let u = URL(string: "https://creativecommons.tankerkoenig.de/json/list.php?lat=\(l.coordinate.latitude)&lng=\(l.coordinate.longitude)&rad=5&sort=dist&type=all&apikey=\(key)"),
              let (d, _) = try? await URLSession.shared.data(from: u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let ss = j["stations"] as? [[String: Any]] else { return [] }
        return ss.compactMap { s in
            guard let lat = s["lat"] as? Double, let lng = s["lng"] as? Double else { return nil }
            var p: [String: Double] = [:]
            if let v = s["e5"] as? Double { p["95"] = v }; if let v = s["diesel"] as? Double { p["D"] = v }
            let loc = CLLocation(latitude: lat, longitude: lng)
            return PricedStation(id: s["id"] as? String ?? UUID().uuidString, name: (s["brand"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (s["name"] as? String ?? "Tankstelle"), coordinate: loc.coordinate, distance: loc.distance(from: l), prices: p, updated: Date(), source: "Tankerkönig")
        }
    }
}

/// Austrija: E-Control (oficialūs, be rakto). Grąžina pigiausias šalia.
struct AustriaProvider: FuelPriceProvider {
    func stations(near l: CLLocation) async -> [PricedStation] {
        var all: [String: PricedStation] = [:]
        for (t, code) in [("95", "SUP"), ("D", "DIE")] {
            guard let u = URL(string: "https://api.e-control.at/sprit/1.0/search/gas-stations/by-address?latitude=\(l.coordinate.latitude)&longitude=\(l.coordinate.longitude)&fuelType=\(code)&includeClosed=false"),
                  let (d, _) = try? await URLSession.shared.data(from: u), let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { continue }
            for s in arr {
                guard let id = s["id"].map({ "\($0)" }), let loc = s["location"] as? [String: Any], let lat = loc["latitude"] as? Double, let lon = loc["longitude"] as? Double,
                      let price = (s["prices"] as? [[String: Any]])?.first?["amount"] as? Double else { continue }
                let cl = CLLocation(latitude: lat, longitude: lon)
                var st = all[id] ?? PricedStation(id: id, name: s["name"] as? String ?? "Tankstelle", coordinate: cl.coordinate, distance: cl.distance(from: l), prices: [:], updated: Date(), source: "E-Control")
                st.prices[t] = price; all[id] = st
            }
        }
        return Array(all.values)
    }
}

/// Kitur: vairuotojų pranešimai per bendrą serverį (server/supabase.sql → fuel_prices).
struct CommunityProvider: FuelPriceProvider {
    func stations(near l: CLLocation) async -> [PricedStation] {
        guard let base = UserDefaults.standard.string(forKey: "supabaseURL"), !base.isEmpty, let key = UserDefaults.standard.string(forKey: "supabaseKey"),
              let u = URL(string: base + "/rest/v1/rpc/fuel_prices_nearby") else { return [] }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue(key, forHTTPHeaderField: "apikey"); r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["lat": l.coordinate.latitude, "lon": l.coordinate.longitude, "radius_m": 8000])
        guard let (d, _) = try? await URLSession.shared.data(for: r), let rows = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        var by: [String: PricedStation] = [:]
        for x in rows {
            guard let id = x["station_id"] as? String, let lat = x["lat"] as? Double, let lon = x["lon"] as? Double, let t = x["fuel"] as? String, let p = x["price"] as? Double else { continue }
            let cl = CLLocation(latitude: lat, longitude: lon)
            var s = by[id] ?? PricedStation(id: id, name: x["name"] as? String ?? "", coordinate: cl.coordinate, distance: cl.distance(from: l), prices: [:], updated: nil, source: "CarVideo")
            s.prices[t] = p; by[id] = s
        }
        return Array(by.values)
    }
    static func report(stationID: String, name: String, at c: CLLocationCoordinate2D, fuel: String, price: Double) async {
        guard let base = UserDefaults.standard.string(forKey: "supabaseURL"), !base.isEmpty, let key = UserDefaults.standard.string(forKey: "supabaseKey"),
              let u = URL(string: base + "/rest/v1/fuel_prices") else { return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue(key, forHTTPHeaderField: "apikey"); r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["station_id": stationID, "name": name, "lat": c.latitude, "lon": c.longitude, "fuel": fuel, "price": price])
        _ = try? await URLSession.shared.data(for: r)
    }
}

@MainActor
final class FuelPriceService: ObservableObject {
    @Published private(set) var items: [PricedStation] = []
    @Published private(set) var source = ""
    func load(near l: CLLocation?, country: String) async {
        guard V14.on("fuelprices"), let l else { items = []; return }
        let provider: FuelPriceProvider
        switch country {
        case "FR": provider = FranceProvider()
        case "DE": provider = GermanyProvider(key: UserDefaults.standard.string(forKey: "tankerkoenigKey") ?? "")
        case "AT": provider = AustriaProvider()
        default: provider = CommunityProvider()
        }
        var list = await provider.stations(near: l)
        if list.isEmpty, !(provider is CommunityProvider) { list = await CommunityProvider().stations(near: l) }
        items = list; source = list.first?.source ?? ""
    }
    func sorted(by fuel: String) -> [PricedStation] { items.filter { $0.prices[fuel] != nil }.sorted { $0.prices[fuel]! < $1.prices[fuel]! } }
}

struct FuelPriceSection: View {
    @ObservedObject var svc: FuelPriceService
    let onGo: (PricedStation) -> Void
    @State private var fuel = "95"
    @State private var editing: String?
    @State private var newPrice = ""
    var body: some View {
        Section {
            Picker("Kuras", selection: $fuel) { Text("95").tag("95"); Text("D").tag("D"); Text("LPG").tag("LPG") }.pickerStyle(.segmented)
            let list = svc.sorted(by: fuel)
            ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                VStack(alignment: .leading, spacing: 4) {
                    Button { onGo(s) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                HStack { Text(s.name).font(.headline).lineLimit(1); if i == 0 && list.count > 1 { Text("Pigiausia").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.green, in: Capsule()).foregroundStyle(.black) } }
                                Text(Measurement(value: s.distance / 1000, unit: UnitLength.kilometers).formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))))).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(s.prices[fuel]!, format: .currency(code: Locale.current.currency?.identifier ?? "EUR").precision(.fractionLength(3))).font(.title3.bold().monospacedDigit())
                        }
                    }
                    if editing == s.id {
                        HStack { TextField("Kaina", text: $newPrice).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width: 100)
                            Button("Išsaugoti") { if let v = Double(newPrice.replacingOccurrences(of: ",", with: ".")) { Task { await CommunityProvider.report(stationID: s.id, name: s.name, at: s.coordinate, fuel: fuel, price: v) } }; editing = nil }.buttonStyle(.borderedProminent) }
                    } else {
                        Button("Patikslinti kainą") { editing = s.id; newPrice = "" }.font(.caption)
                    }
                }
            }
        } header: { Text("Kainos") } footer: { if !svc.source.isEmpty { Text("Šaltinis: \(svc.source)") } }
    }
}
