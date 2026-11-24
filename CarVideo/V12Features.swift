import SwiftUI
import Speech
import AVFoundation
import AppIntents
import CoreLocation

// MARK: - v12: video režimas, šalys, balsas, draugai, vidutinio greičio ruožai, bendras serveris

enum V12 {
    static let features: [(String, String, String)] = [
        ("f.voice", "Balso komandos", "„Važiuok namo“, „pranešk apie policiją“, „kitas takelis“"),
        ("f.friends", "Draugai žemėlapyje", "Matyti draugus ir dalintis kelione"),
        ("f.avgzone", "Vidutinio greičio ruožai", "Rodo vidutinį greitį ruože ir įspėja")
    ]
}

// MARK: Šalių taisyklės (pasaulinei auditorijai)

struct Region: Identifiable {
    let id: String, name: String, mph: Bool
    let winterTyres: (Int, Int, Int, Int)?   // nuo mėn./d. iki mėn./d.; nil – nėra datos
    let byWeather: Bool                       // „pagal orą“ (DE, AT, CH)
    let policeAlertsAllowed: Bool
    let note: String?

    static let all: [Region] = [
        .init(id: "LT", name: "Lietuva", mph: false, winterTyres: (11, 10, 4, 1), byWeather: false, policeAlertsAllowed: true, note: nil),
        .init(id: "LV", name: "Latvija", mph: false, winterTyres: (12, 1, 3, 1), byWeather: false, policeAlertsAllowed: true, note: nil),
        .init(id: "EE", name: "Estija", mph: false, winterTyres: (12, 1, 3, 1), byWeather: false, policeAlertsAllowed: true, note: nil),
        .init(id: "FI", name: "Suomija", mph: false, winterTyres: (12, 1, 3, 1), byWeather: false, policeAlertsAllowed: true, note: nil),
        .init(id: "SE", name: "Švedija", mph: false, winterTyres: (12, 1, 4, 1), byWeather: false, policeAlertsAllowed: true, note: nil),
        .init(id: "IT", name: "Italija", mph: false, winterTyres: (11, 15, 4, 15), byWeather: false, policeAlertsAllowed: true, note: nil),
        .init(id: "DE", name: "Vokietija", mph: false, winterTyres: nil, byWeather: true, policeAlertsAllowed: false, note: "Vairuotojui draudžiama naudoti policijos ir kamerų įspėjimus."),
        .init(id: "AT", name: "Austrija", mph: false, winterTyres: nil, byWeather: true, policeAlertsAllowed: true, note: nil),
        .init(id: "CH", name: "Šveicarija", mph: false, winterTyres: nil, byWeather: true, policeAlertsAllowed: false, note: "Draudžiama įspėti apie policiją ir kameras."),
        .init(id: "FR", name: "Prancūzija", mph: false, winterTyres: nil, byWeather: false, policeAlertsAllowed: false, note: "Kamerų vieta nerodoma – tik „pavojinga zona“."),
        .init(id: "PL", name: "Lenkija", mph: false, winterTyres: nil, byWeather: false, policeAlertsAllowed: true, note: nil),
        .init(id: "ES", name: "Ispanija", mph: false, winterTyres: nil, byWeather: false, policeAlertsAllowed: true, note: nil),
        .init(id: "NO", name: "Norvegija", mph: false, winterTyres: nil, byWeather: false, policeAlertsAllowed: true, note: nil),
        .init(id: "GB", name: "Jungtinė Karalystė", mph: true, winterTyres: nil, byWeather: false, policeAlertsAllowed: true, note: nil),
        .init(id: "US", name: "JAV", mph: true, winterTyres: nil, byWeather: false, policeAlertsAllowed: true, note: nil),
        .init(id: "OT", name: "Kita šalis", mph: false, winterTyres: nil, byWeather: false, policeAlertsAllowed: true, note: nil)
    ]
    static var current: Region {
        let pick = UserDefaults.standard.string(forKey: "country") ?? "auto"
        let code = pick == "auto" ? (Locale.current.region?.identifier ?? "LT") : pick
        return all.first { $0.id == code } ?? all.last!
    }
    /// Kai šalis pakeičiama: vienetai ir draudžiami įspėjimai.
    static func apply(_ r: Region) {
        UserDefaults.standard.set(r.mph ? "mph" : "kmh", forKey: "units")
        if !r.policeAlertsAllowed {
            var off = Set((UserDefaults.standard.string(forKey: "alertKindsOff") ?? "").split(separator: ",").map(String.init))
            off.insert("police"); UserDefaults.standard.set(off.joined(separator: ","), forKey: "alertKindsOff")
            UserDefaults.standard.set(false, forKey: "camerasOn")
        }
    }
}

struct V12Section: View {
    @AppStorage("videoMode") private var videoMode = "split"
    @AppStorage("country") private var country = "auto"
    @AppStorage("f.voice") private var voice = true
    @AppStorage("f.friends") private var friends = true
    @AppStorage("f.avgzone") private var avg = true
    @AppStorage("supabaseURL") private var sbURL = ""
    @AppStorage("supabaseKey") private var sbKey = ""
    var body: some View {
        Section {
            Picker("Video atidaryti", selection: $videoMode) {
                Text("Šalia žemėlapio (per pusę)").tag("split"); Text("Per visą ekraną").tag("full"); Text("YouTube programėlėje").tag("app")
            }
        } footer: { Text(videoMode == "app" ? "YouTube programėlėje matysi savo paskyrą, bet video nebus šalia žemėlapio ir CarVideo negalės jo sustabdyti važiuojant." : "Video ir žemėlapis per pusę; skirtuką galima tempti.") }
        Section {
            Picker("Šalis", selection: $country) {
                Text("Pagal telefoną (\(Region.current.name))").tag("auto")
                ForEach(Region.all) { Text($0.name).tag($0.id) }
            }
            .onChange(of: country) { _, _ in Region.apply(Region.current); Reminders.reschedule() }
            Button("Kalba") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
        } header: { Text("Kalba ir šalis") } footer: { Text("Kalba keičiama iPhone nustatymuose → CarVideo → Kalba. " + (Region.current.note ?? "")) }
        Section("Navigacija") {
            Toggle(isOn: $voice) { VStack(alignment: .leading) { Text("Balso komandos"); Text("„Važiuok namo“, „pranešk apie policiją“ ir per Siri").font(.caption).foregroundStyle(.secondary) } }
            Toggle(isOn: $friends) { VStack(alignment: .leading) { Text("Draugai žemėlapyje"); Text("Dalintis kelione kodu").font(.caption).foregroundStyle(.secondary) } }
            Toggle(isOn: $avg) { VStack(alignment: .leading) { Text("Vidutinio greičio ruožai"); Text("Iš OpenStreetMap, visame pasaulyje").font(.caption).foregroundStyle(.secondary) } }
        }
        Section {
            TextField("Supabase URL", text: $sbURL).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("anon raktas", text: $sbKey)
        } header: { Text("Serveris (pranešimai ir draugai)") } footer: { Text(sbURL.isEmpty ? "Neįvesta – pranešimai matomi tik šiame telefone." : "Naudojamas bendras serveris.") }
    }
}

// MARK: Bendras serveris (Supabase REST)

final class SupabaseBackend: AlertBackend {
    let url: URL, key: String
    init?(url: String, key: String) { guard let u = URL(string: url), !key.isEmpty else { return nil }; self.url = u; self.key = key }
    static var configured: SupabaseBackend? { SharedServer17.active ? SupabaseBackend(url: SharedServer17.url, key: SharedServer17.key) : nil }   // v17: įmontuotas serveris + jungiklis

    private func req(_ path: String, _ method: String = "GET", body: Any? = nil) -> URLRequest {
        var r = URLRequest(url: url.appendingPathComponent(path)); r.httpMethod = method
        r.setValue(key, forHTTPHeaderField: "apikey"); r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { r.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        return r
    }
    private struct Row: Decodable { let id: UUID; let kind: String; let lat: Double; let lon: Double; let created_at: String; let confirmations: Int }

    func nearby(_ c: CLLocationCoordinate2D) async -> [RoadAlert] {
        guard let (d, _) = try? await URLSession.shared.data(for: req("rest/v1/rpc/alerts_nearby", "POST", body: ["p_lat": c.latitude, "p_lon": c.longitude])),
              let rows = try? JSONDecoder().decode([Row].self, from: d) else { return [] }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return rows.compactMap { r in AlertKind(rawValue: r.kind).map { RoadAlert(id: r.id, kind: $0, lat: r.lat, lon: r.lon, created: f.date(from: r.created_at) ?? .now, confirmations: r.confirmations) } }
    }
    func report(_ a: RoadAlert) async {
        _ = try? await URLSession.shared.data(for: req("rest/v1/alerts", "POST", body: ["id": a.id.uuidString, "kind": a.kind.rawValue, "lat": a.lat, "lon": a.lon, "country": Region.current.id]))
    }
    func vote(_ id: UUID, stillThere: Bool) async {
        _ = try? await URLSession.shared.data(for: req("rest/v1/rpc/alerts_vote", "POST", body: ["p_id": id.uuidString, "p_still_there": stillThere]))
    }

    // Draugai
    struct LiveTrip: Codable, Identifiable { var code: String; var name: String; var lat: Double?; var lon: Double?; var speed_kmh: Int?; var destination: String?; var id: String { code } }
    func publish(_ t: LiveTrip) async {
        var r = req("rest/v1/live_trips", "POST", body: try? JSONSerialization.jsonObject(with: JSONEncoder().encode(t)))
        r.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        _ = try? await URLSession.shared.data(for: r)
    }
    func friends(_ codes: [String]) async -> [LiveTrip] {
        guard !codes.isEmpty else { return [] }
        var r = req("rest/v1/live_trips"); var comps = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "code", value: "in.(\(codes.joined(separator: ",")))")]; r.url = comps.url
        guard let (d, _) = try? await URLSession.shared.data(for: r) else { return [] }
        return (try? JSONDecoder().decode([LiveTrip].self, from: d)) ?? []
    }
}

// MARK: Draugai žemėlapyje

@MainActor
final class FriendsService: ObservableObject {
    @Published private(set) var friends: [SupabaseBackend.LiveTrip] = []
    @AppStorage("friendCodes") private var codesRaw = ""     // draugų kodai, atskirti kableliais
    @AppStorage("myTripCode") private var myCode = ""
    @AppStorage("myName") private var myName = ""
    private var last = Date.distantPast

    var shareURL: URL { URL(string: "https://carvideo.app/k/\(ensureCode())")! }
    func ensureCode() -> String { if myCode.isEmpty { myCode = String(UUID().uuidString.prefix(6)) }; return myCode }
    func addFriend(code: String) { var s = Set(codesRaw.split(separator: ",").map(String.init)); s.insert(code.uppercased()); codesRaw = s.joined(separator: ",") }

    func update(location l: CLLocation, destination: String?) {
        guard Feature.on("f.friends"), let sb = SupabaseBackend.configured, Date().timeIntervalSince(last) > 15 else { return }
        last = Date()
        let me = SupabaseBackend.LiveTrip(code: ensureCode(), name: myName.isEmpty ? "Draugas" : myName, lat: l.coordinate.latitude, lon: l.coordinate.longitude, speed_kmh: Int(max(0, l.speed) * 3.6), destination: destination)
        let codes = codesRaw.split(separator: ",").map(String.init)
        Task { await sb.publish(me); friends = await sb.friends(codes) }
    }
}

// MARK: Vidutinio greičio ruožai (OpenStreetMap: relation enforcement=average_speed)

@MainActor
final class AvgSpeedZones: ObservableObject {
    struct Zone: Identifiable { let id: Int; let from: CLLocation; let to: CLLocation; let limit: Double }
    @Published private(set) var zones: [Zone] = []
    @Published private(set) var active: (zone: Zone, avgKmh: Double, metersLeft: Double)?
    private var lastFetch: CLLocation?
    private var start: (Date, CLLocationDistance)?
    private var travelled: CLLocationDistance = 0
    private var prev: CLLocation?

    func update(with l: CLLocation) {
        guard Feature.on("f.avgzone") else { active = nil; return }
        if lastFetch == nil || lastFetch!.distance(from: l) > 15_000 { lastFetch = l; Task { await fetch(around: l.coordinate) } }
        if let p = prev { travelled += l.distance(from: p) }; prev = l
        if let a = active {
            let left = l.distance(from: a.zone.to)
            if left < 60 { active = nil; start = nil; return }
            let secs = Date().timeIntervalSince(start!.0), dist = travelled - start!.1
            active = (a.zone, secs > 0 ? dist / secs * 3.6 : 0, left)
        } else if let z = zones.first(where: { $0.from.distance(from: l) < 60 }) {
            start = (Date(), travelled); active = (z, 0, l.distance(from: z.to))
        }
    }

    private func fetch(around c: CLLocationCoordinate2D) async {
        let q = "[out:json][timeout:20];relation[\"type\"=\"enforcement\"][\"enforcement\"=\"average_speed\"](around:30000,\(c.latitude),\(c.longitude));out geom;"
        var r = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!); r.httpMethod = "POST"
        r.httpBody = ("data=" + (q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")).data(using: .utf8)
        guard let (d, _) = try? await URLSession.shared.data(for: r),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let els = j["elements"] as? [[String: Any]] else { return }
        zones = els.compactMap { e in
            guard let id = e["id"] as? Int, let members = e["members"] as? [[String: Any]] else { return nil }
            func pt(_ role: String) -> CLLocation? {
                guard let m = members.first(where: { ($0["role"] as? String) == role }), let la = m["lat"] as? Double, let lo = m["lon"] as? Double else { return nil }
                return CLLocation(latitude: la, longitude: lo)
            }
            guard let f = pt("from") ?? pt("device"), let t = pt("to") else { return nil }
            let tags = e["tags"] as? [String: String] ?? [:]
            return Zone(id: id, from: f, to: t, limit: Double(tags["maxspeed"] ?? "") ?? 0)
        }
    }
}

struct AvgZoneBox: View {
    let zone: AvgSpeedZones.Zone, avg: Double, left: Double
    var over: Bool { zone.limit > 0 && avg > zone.limit }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("VIDUTINIO GREIČIO RUOŽAS").font(.caption2).foregroundStyle(.secondary)
            Text("Ø \(Units.speed(avg))" + (zone.limit > 0 ? " / \(Units.speed(zone.limit))" : "") + " \(Units.speedLabel)").font(.title2.bold())
            Text("\(Int(left)) m iki pabaigos" + (over ? " · sulėtink" : "")).font(.caption)
        }
        .padding(10).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(over ? .red : .green, lineWidth: 2))
    }
}

// MARK: Balso komandos (mikrofonas programėlėje + Siri)

enum VoiceCommand: String, CaseIterable {
    case home, work, police, pothole, crash, next, pause, play, video, map, half
    var phrases: [String] {
        switch self {
        case .home: ["namo", "home", "nach hause", "do domu", "a casa", "maison"]
        case .work: ["darb", "work", "arbeit", "praca", "trabajo", "travail"]
        case .police: ["polic", "police", "polizei", "policja", "policía"]
        case .pothole: ["duob", "pothole", "schlagloch", "dziur", "bache"]
        case .crash: ["avarij", "crash", "accident", "unfall", "wypadek", "accidente"]
        case .next: ["kitas", "next", "nächste", "następn", "siguiente", "suivant"]
        case .pause: ["pauz", "pause", "stop"]
        case .play: ["grok", "groti", "play", "abspielen", "graj", "reproducir", "lecture"]
        case .video: ["video", "vídeo", "wideo", "vidéo"]
        case .map: ["žemėlap", "map", "karte", "mapa", "carte"]
        case .half: ["pus", "half", "hälfte", "połow", "mitad", "moitié"]
        }
    }
    static func parse(_ text: String) -> VoiceCommand? {
        let t = text.lowercased()
        return allCases.first { c in c.phrases.contains { t.contains($0) } }
    }
}

extension Notification.Name { static let voiceCommand = Notification.Name("voiceCommand") }

@MainActor
final class VoiceListener: ObservableObject {
    @Published var listening = false
    @Published var heard = ""
    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?

    func toggle() { listening ? stop() : start() }

    func start() {
        SFSpeechRecognizer.requestAuthorization { st in
            guard st == .authorized else { return }
            Task { @MainActor in self.begin() }
        }
    }
    private func begin() {
        guard let rec = SFSpeechRecognizer(locale: Locale.current), rec.isAvailable else { return }
        let req = SFSpeechAudioBufferRecognitionRequest(); req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }   // privatumas: atpažinimas telefone
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { b, _ in req.append(b) }
        try? engine.start(); listening = true
        task = rec.recognitionTask(with: req) { [weak self] r, err in
            Task { @MainActor in
                guard let self else { return }
                if let r { self.heard = r.bestTranscription.formattedString
                    if let c = VoiceCommand.parse(self.heard) { NotificationCenter.default.post(name: .voiceCommand, object: c.rawValue); self.stop() } }
                if err != nil || (r?.isFinal ?? false) { self.stop() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.stop() }
    }
    func stop() {
        guard listening else { return }
        engine.stop(); engine.inputNode.removeTap(onBus: 0); task?.cancel(); task = nil; listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Siri: „Hey Siri, pranešk CarVideo apie policiją“ – veikia neatrakinus telefono.
struct ReportAlertIntent: AppIntent {
    static var title: LocalizedStringResource = "Pranešti apie kliūtį"
    static var openAppWhenRun = true
    @Parameter(title: "Kas") var kind: AlertKindEntity
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .voiceCommand, object: kind.rawValue)
        return .result(dialog: "Ačiū, pranešta")
    }
}
enum AlertKindEntity: String, AppEnum {
    case police, pothole, crash
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kliūtis"
    static var caseDisplayRepresentations: [AlertKindEntity: DisplayRepresentation] = [.police: "Policija", .pothole: "Duobė", .crash: "Avarija"]
}
