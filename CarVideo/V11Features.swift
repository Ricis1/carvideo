import SwiftUI
import AppIntents
import CoreLocation

// MARK: - v11: automatinis paleidimas, vairuotojų pranešimai (CarPlay – CarPlay/CarPlaySceneDelegate.swift)

extension Feature {
    // v11 jungikliai (raktai f.carplay, f.autolaunch, f.alerts; numatytai įjungta)
    static let v11: [(String, String, String)] = [
        ("f.carplay", "CarPlay versija", "Žemėlapis ir greitis automobilio ekrane"),
        ("f.autolaunch", "Automatinis paleidimas", "Prisijungus prie automobilio – muzika arba navigacija"),
        ("f.alerts", "Vairuotojų pranešimai", "Policija, duobės, avarijos – kaip Waze, mūsų programėlėje")
    ]
    static func on(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

struct V11FeaturesSection: View {
    @AppStorage("f.carplay") private var carplay = true
    @AppStorage("f.autolaunch") private var auto = true
    @AppStorage("f.alerts") private var alerts = true
    @AppStorage("autoAction") private var action = CarAction.music.rawValue
    var body: some View {
        Section("Automobilis") {
            Toggle(isOn: $carplay) { row(Feature.v11[0]) }
            Toggle(isOn: $auto) { row(Feature.v11[1]) }
            if auto {
                Picker("Prisijungus", selection: $action) { ForEach(CarAction.allCases) { Text($0.title).tag($0.rawValue) } }
            }
            Toggle(isOn: $alerts) { row(Feature.v11[2]) }
        }
    }
    private func row(_ r: (String, String, String)) -> some View { VStack(alignment: .leading) { Text(r.1); Text(r.2).font(.caption).foregroundStyle(.secondary) } }
}

// MARK: Automatinis paleidimas
// iOS neleidžia programėlei atsidaryti pačiai. Todėl yra veiksmas „CarVideo automobilyje“ programoje
// „Spartieji klavišai“: Automatizavimas → CarPlay / Bluetooth → Prisijungia → CarVideo automobilyje → Vykdyti iškart.

enum CarAction: String, CaseIterable, Identifiable, AppEnum {
    case music, home, menu, none
    var id: String { rawValue }
    var title: String { ["music": "Paleisti muziką", "home": "Vesti namo", "menu": "Pradžios ekranas", "none": "Nieko"][rawValue]! }
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Veiksmas"
    static var caseDisplayRepresentations: [CarAction: DisplayRepresentation] = [.music: "Paleisti muziką", .home: "Vesti namo", .menu: "Pradžios ekranas", .none: "Nieko"]
}

struct CarModeIntent: AppIntent {
    static var title: LocalizedStringResource = "CarVideo automobilyje"
    static var description = IntentDescription("Atidaro CarVideo ir paleidžia muziką arba navigaciją namo.")
    static var openAppWhenRun = true
    @Parameter(title: "Veiksmas") var action: CarAction?

    @MainActor func perform() async throws -> some IntentResult {
        guard Feature.on("f.autolaunch") else { return .result() }
        let a = action ?? CarAction(rawValue: UserDefaults.standard.string(forKey: "autoAction") ?? "music") ?? .music
        UserDefaults.standard.set(a.rawValue, forKey: "pendingCarAction")
        NotificationCenter.default.post(name: .carActionRequested, object: nil)
        return .result()
    }
}

struct CarVideoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CarModeIntent(), phrases: ["\(.applicationName) automobilyje", "Paleisk \(.applicationName)"], shortTitle: "Automobilyje", systemImageName: "car.fill")
        // v12: Siri – pranešimai be rankų
        AppShortcut(intent: ReportAlertIntent(), phrases: ["Pranešk \(.applicationName) apie \(\.$kind)", "Report \(\.$kind) in \(.applicationName)"], shortTitle: "Pranešti", systemImageName: "exclamationmark.triangle.fill")
    }
}

extension Notification.Name { static let carActionRequested = Notification.Name("carActionRequested") }

/// Paima laukiantį veiksmą (iš Sparčiųjų klavišų arba prisijungus prie automobilio, kai programėlė veikia).
enum PendingCarAction {
    static func take() -> CarAction? {
        guard let r = UserDefaults.standard.string(forKey: "pendingCarAction") else { return nil }
        UserDefaults.standard.removeObject(forKey: "pendingCarAction")
        return CarAction(rawValue: r)
    }
}

// MARK: Vairuotojų pranešimai (policija, duobės, avarijos)

enum AlertKind: String, Codable, CaseIterable, Identifiable {
    case police, pothole, crash, hazard, jam
    var id: String { rawValue }
    var title: String { ["police": "Policija", "pothole": "Duobė", "crash": "Avarija", "hazard": "Kliūtis kelyje", "jam": "Spūstis"][rawValue]! }
    var symbol: String { ["police": "shield.fill", "pothole": "circle.bottomhalf.filled", "crash": "car.side.rear.and.collision.and.car.side.front", "hazard": "exclamationmark.triangle.fill", "jam": "car.2.fill"][rawValue]! }
    var color: Color { [.blue, .orange, .red, .yellow, .purple][AlertKind.allCases.firstIndex(of: self)!] }
}

struct RoadAlert: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: AlertKind
    var lat: Double, lon: Double
    var created = Date()
    var confirmations = 0
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var expired: Bool { Date().timeIntervalSince(created) > 3600 }
}

/// Serveris, per kurį vairuotojai mato vieni kitų pranešimus.
/// Reikia savo serverio (pvz. Supabase arba Firebase): lentelė „alerts“ + užklausa „pranešimai 10 km spinduliu“.
/// Kol serverio nėra, naudojamas LocalBackend – pranešimai matomi tik tavo telefone.
protocol AlertBackend {
    func nearby(_ c: CLLocationCoordinate2D) async -> [RoadAlert]
    func report(_ a: RoadAlert) async
    func vote(_ id: UUID, stillThere: Bool) async
}

final class LocalBackend: AlertBackend {
    private let key = "alerts.local"
    private var all: [RoadAlert] {
        get { (try? JSONDecoder().decode([RoadAlert].self, from: UserDefaults.standard.data(forKey: key) ?? Data())) ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
    func nearby(_ c: CLLocationCoordinate2D) async -> [RoadAlert] {
        let me = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return all.filter { !$0.expired && CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: me) < 10_000 }
    }
    func report(_ a: RoadAlert) async { all = all.filter { !$0.expired } + [a] }
    func vote(_ id: UUID, stillThere: Bool) async {
        var a = all
        if stillThere { if let i = a.firstIndex(where: { $0.id == id }) { a[i].confirmations += 1 } } else { a.removeAll { $0.id == id } }
        all = a
    }
}

@MainActor
final class RoadAlertService: ObservableObject {
    @Published private(set) var alerts: [RoadAlert] = []
    @Published var approaching: (RoadAlert, Int)?
    @AppStorage("alertKindsOff") private var kindsOff = ""   // pvz. "police,jam"
    private var warned = Set<UUID>()
    private var lastFetch = Date.distantPast
    var backend: AlertBackend { SupabaseBackend.configured ?? LocalBackend() }   // v12: bendras serveris, jei įvestas

    func enabled(_ k: AlertKind) -> Bool { !kindsOff.split(separator: ",").contains(Substring(k.rawValue)) }

    func update(with l: CLLocation) {
        guard Feature.on("f.alerts") else { alerts = []; approaching = nil; return }
        if Date().timeIntervalSince(lastFetch) > 30 {   // v17: dažniau, kad kitų pranešimai ateitų greičiau
            lastFetch = Date()
            Task { alerts = await backend.nearby(l.coordinate) }
        }
        // įspėjimas, kai iki pranešimo liko < 500 m ir jis yra priekyje
        for a in alerts where enabled(a.kind) && !warned.contains(a.id) {
            let d = CLLocation(latitude: a.lat, longitude: a.lon).distance(from: l)
            if d < 500, l.course < 0 || abs(bearing(l.coordinate, a.coordinate) - l.course).truncatingRemainder(dividingBy: 360) < 60 {
                warned.insert(a.id); approaching = (a, Int(d / 10) * 10)
                break
            }
        }
    }

    func report(_ k: AlertKind, at c: CLLocationCoordinate2D) {
        let a = RoadAlert(kind: k, lat: c.latitude, lon: c.longitude)
        alerts.append(a); warned.insert(a.id)
        Task { await backend.report(a); lastFetch = .distantPast }
    }

    func vote(stillThere: Bool) {
        guard let (a, _) = approaching else { return }
        approaching = nil
        if !stillThere { alerts.removeAll { $0.id == a.id } }
        Task { await backend.vote(a.id, stillThere: stillThere) }
    }

    private func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let f1 = a.latitude * .pi / 180, f2 = b.latitude * .pi / 180, dl = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dl) * cos(f2), x = cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dl)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

struct ReportAlertSheet: View {
    let onPick: (AlertKind) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(AlertKind.allCases) { k in
                    Button { onPick(k); dismiss() } label: {
                        VStack(spacing: 6) { Image(systemName: k.symbol).font(.title2).foregroundStyle(k.color); Text(k.title).bold() }
                            .frame(maxWidth: .infinity, minHeight: 74).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
            }
            .padding()
            .navigationTitle("Pranešti kitiems").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Atšaukti") { dismiss() } }
        }
        .presentationDetents([.medium])
    }
}

struct AlertBanner: View {
    let alert: RoadAlert, meters: Int
    let vote: (Bool) -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alert.kind.symbol).foregroundStyle(alert.kind.color).font(.title2)
            VStack(alignment: .leading) {
                Text("\(alert.kind.title) po \(meters) m").bold()
                Text("Patvirtino \(alert.confirmations) · prieš \(Int(Date().timeIntervalSince(alert.created) / 60)) min").font(.caption).foregroundStyle(.secondary)
            }
            Button("Vis dar yra") { vote(true) }.buttonStyle(.borderedProminent).tint(.green)
            Button("Nebėra") { vote(false) }.buttonStyle(.bordered)
        }
        .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
