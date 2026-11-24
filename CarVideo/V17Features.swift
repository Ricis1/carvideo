// v17: rinkliavos ir vinjetės, vaizdingas maršrutas, Dynamic Island, bendri vairuotojų pranešimai.
// Kiekvieną funkciją galima išjungti: Nustatymai → v17. Vaizdo registratorius išimtas.
import SwiftUI
import MapKit
import ActivityKit

enum V17 { static func on(_ k: String) -> Bool { UserDefaults.standard.object(forKey: "f." + k) as? Bool ?? true } }

// MARK: - 1–2. Maršruto parinktys: greičiausias / vaizdingas, vengti mokamų kelių ir vinječių

enum RouteOptions17 {
    static var scenic: Bool { V17.on("scenic") && UserDefaults.standard.string(forKey: "routeType") == "scenic" }
    static var avoidTolls: Bool { V17.on("tolls") && UserDefaults.standard.bool(forKey: "avoidTolls") }
    static var avoidVignettes: Bool { V17.on("tolls") && UserDefaults.standard.bool(forKey: "avoidVignettes") }

    /// Pritaiko pasirinkimus Apple Maps užklausai.
    static func apply(to req: MKDirections.Request) {
        req.tollPreference = avoidTolls ? .avoid : .any
        // Vinjetės galioja greitkeliams, todėl jų vengiant vengiami greitkeliai. Vaizdingas – irgi mažesni keliai.
        req.highwayPreference = (avoidVignettes || scenic) ? .avoid : .any
        if scenic { req.requestsAlternateRoutes = true }
    }
    /// Iš kelių variantų: greičiausias, o vaizdingam – ilgiausias (daugiau gamtos), bet ne daugiau kaip +35 % laiko.
    static func pick(_ routes: [MKRoute]) -> MKRoute? {
        guard let fastest = routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else { return nil }
        guard scenic else { return routes.first }
        return routes.filter { $0.expectedTravelTime <= fastest.expectedTravelTime * 1.35 }.max(by: { $0.distance < $1.distance }) ?? fastest
    }
}

struct Vignette17: Identifiable {
    enum Kind { case free, vignette, toll }
    let id: String; let country: LocalizedStringKey; let kind: Kind; let info: String; let buy: String
    /// Apytikslės kainos (2026), tikrinti oficialiose svetainėse.
    static let all: [Vignette17] = [
        .init(id: "LT", country: "Lietuva", kind: .free, info: "Lengviesiems nereikia (vinjetė tik krovininiams)", buy: ""),
        .init(id: "LV", country: "Latvija", kind: .free, info: "Lengviesiems nereikia", buy: ""),
        .init(id: "EE", country: "Estija", kind: .free, info: "Lengviesiems nereikia", buy: ""),
        .init(id: "PL", country: "Lenkija", kind: .toll, info: "Mokamos atkarpos A1, A2, A4 (~2–10 €)", buy: "https://etoll.gov.pl"),
        .init(id: "DE", country: "Vokietija", kind: .free, info: "Lengviesiems nemokama", buy: ""),
        .init(id: "CZ", country: "Čekija", kind: .vignette, info: "E-vinjetė: 10 d. ~12 €, metai ~100 €", buy: "https://edalnice.cz"),
        .init(id: "SK", country: "Slovakija", kind: .vignette, info: "E-vinjetė: 10 d. ~12 €, metai ~60 €", buy: "https://eznamka.sk"),
        .init(id: "AT", country: "Austrija", kind: .vignette, info: "Skaitmeninė: 1 d. ~9 €, 10 d. ~13 €", buy: "https://shop.asfinag.at"),
        .init(id: "HU", country: "Vengrija", kind: .vignette, info: "E-matrica: 10 d. ~15 €", buy: "https://ematrica.nemzetiutdij.hu"),
        .init(id: "SI", country: "Slovėnija", kind: .vignette, info: "E-vinjetė: 7 d. ~16 €", buy: "https://evinjeta.dars.si"),
        .init(id: "CH", country: "Šveicarija", kind: .vignette, info: "Vinjetė metams 40 CHF", buy: "https://via.admin.ch"),
        .init(id: "RO", country: "Rumunija", kind: .vignette, info: "Rovinieta: 7 d. ~3 €", buy: "https://www.roviniete.ro"),
        .init(id: "BG", country: "Bulgarija", kind: .vignette, info: "E-vinjetė: savaitė ~8 €", buy: "https://web.bgtoll.bg"),
        .init(id: "FR", country: "Prancūzija", kind: .toll, info: "Mokama už atkarpas (péage)", buy: ""),
        .init(id: "IT", country: "Italija", kind: .toll, info: "Mokama už atkarpas (pedaggio)", buy: ""),
        .init(id: "ES", country: "Ispanija", kind: .toll, info: "Dalis greitkelių mokami (peaje)", buy: ""),
    ]
    static func by(_ code: String) -> Vignette17? { all.first { $0.id == code } }
}

/// Patikrina, per kurias šalis eina maršrutas ir ar ten reikia vinjetės, kurios dar neturi.
@MainActor
final class VignetteChecker: ObservableObject {
    @Published private(set) var needed: [Vignette17] = []
    @Published private(set) var hasTolls = false
    @Published var dismissed = false
    @AppStorage("vig.owned") var ownedRaw = ""   // pvz. "CZ,AT"
    var owned: Set<String> { Set(ownedRaw.split(separator: ",").map(String.init)) }
    func toggleOwned(_ c: String) { var o = owned; if o.contains(c) { o.remove(c) } else { o.insert(c) }; ownedRaw = o.sorted().joined(separator: ",") }

    func check(_ r: MKRoute?) {
        needed = []; hasTolls = false; dismissed = false
        guard let r, V17.on("tolls") else { return }
        hasTolls = r.hasTolls
        guard r.distance > 60_000, !RouteOptions17.avoidVignettes else { return }   // trumpas maršrutas – šalies nekeičia
        let n = r.polyline.pointCount, pts = r.polyline.points()
        let samples = stride(from: 0, to: n, by: max(1, n / 10)).map { pts[$0].coordinate }
        Task {
            var codes: [String] = []
            for c in samples {   // CLGeocoder leidžia nedaug užklausų, todėl ~10 taškų nuosekliai
                if let p = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first,
                   let iso = p.isoCountryCode, !codes.contains(iso) { codes.append(iso) }
            }
            needed = codes.compactMap(Vignette17.by).filter { $0.kind == .vignette && !owned.contains($0.id) }
        }
    }
}

struct VignetteBanner: View {
    @ObservedObject var vig: VignetteChecker
    var onAvoid: () -> Void
    var onInfo: () -> Void
    var body: some View {
        if !vig.needed.isEmpty, !vig.dismissed {
            HStack(spacing: 10) {
                Image(systemName: "road.lanes").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reikia vinjetės: \(vig.needed.map(\.id).joined(separator: ", "))").font(.subheadline.bold())
                    Text(vig.needed.map { $0.id + ": " + $0.info }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                Button("Turiu") { vig.needed.forEach { vig.toggleOwned($0.id) }; vig.dismissed = true }.buttonStyle(.borderedProminent).tint(.green)
                Button("Vengti") { UserDefaults.standard.set(true, forKey: "avoidVignettes"); vig.dismissed = true; onAvoid() }.buttonStyle(.bordered)
                Button("Kur pirkti") { onInfo() }.buttonStyle(.bordered)
            }
            .padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 12).padding(.top, 60)
        }
    }
}

struct RouteOptionsSheet: View {
    @AppStorage("routeType") private var routeType = "fast"
    @AppStorage("avoidTolls") private var avoidTolls = false
    @AppStorage("avoidVignettes") private var avoidVig = false
    @AppStorage("f.tolls") private var tollsOn = true
    @AppStorage("f.scenic") private var scenicOn = true
    @ObservedObject var vig: VignetteChecker
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if scenicOn {
                    Section("Maršrutas") {
                        Picker("Maršrutas", selection: $routeType) {
                            Text("Greičiausias").tag("fast"); Text("Vaizdingas").tag("scenic")
                        }.pickerStyle(.segmented)
                        Text(routeType == "scenic" ? "Pro ežerus, miškus ir mažesnius kelius" : "Mažiausiai laiko").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if tollsOn {
                    Section {
                        Toggle("Vengti mokamų kelių", isOn: $avoidTolls)
                        Toggle("Vengti kelių su vinjete", isOn: $avoidVig)
                    }
                    Section {
                        ForEach(Vignette17.all) { v in
                            HStack {
                                Text(v.id).font(.caption.bold()).foregroundStyle(.blue).frame(width: 28)
                                VStack(alignment: .leading) { Text(v.country); Text(v.info).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                switch v.kind {
                                case .free: Text("nereikia").font(.caption2.bold()).foregroundStyle(.green)
                                case .toll: if let u = URL(string: v.buy), !v.buy.isEmpty { Link("rinkliava", destination: u).font(.caption2.bold()) } else { Text("rinkliava").font(.caption2.bold()).foregroundStyle(.red) }
                                case .vignette:
                                    Button(vig.owned.contains(v.id) ? "Turiu ✓" : "Turiu") { vig.toggleOwned(v.id) }.buttonStyle(.bordered).tint(vig.owned.contains(v.id) ? .green : .gray).font(.caption)
                                    if let u = URL(string: v.buy) { Link(destination: u) { Image(systemName: "cart") } }
                                }
                            }
                        }
                    } header: { Text("Vinjetės ir rinkliavos Europoje") } footer: { Text("Paspaudus „Turiu“ – daugiau neįspėsime apie šią šalį. Kainos apytikslės, tikrink oficialioje svetainėje.") }
                }
            }
            .navigationTitle("Maršruto parinktys").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Uždaryti") { dismiss() } } }
            .onChange(of: routeType) { _, _ in onChange() }
            .onChange(of: avoidTolls) { _, _ in onChange() }
            .onChange(of: avoidVig) { _, _ in onChange() }
        }
    }
}

// MARK: - 3. Dynamic Island (Live Activity su posūkiu)

enum LiveRoute17 {
    private static var last = Date.distantPast
    private static var lastText = ""
    /// SF Symbol pagal Apple Maps nurodymo tekstą (veikia lietuviškai ir angliškai).
    static func symbol(_ t: String) -> String {
        let s = t.lowercased()
        if s.contains("apsisuk") || s.contains("u-turn") { return "arrow.uturn.down" }
        if s.contains("žied") || s.contains("roundabout") { return "arrow.triangle.turn.up.right.circle" }
        if s.contains("kair") || s.contains("left") { return s.contains("laikyk") || s.contains("keep") ? "arrow.up.left" : "arrow.turn.up.left" }
        if s.contains("deš") || s.contains("right") { return s.contains("laikyk") || s.contains("keep") ? "arrow.up.right" : "arrow.turn.up.right" }
        if s.contains("tiksl") || s.contains("arrive") || s.contains("destination") { return "flag.checkered" }
        return "arrow.up"
    }
    /// Atnaujina ne dažniau kaip kas 5 s arba pasikeitus posūkiui (Apple riboja atnaujinimų kiekį).
    static func update(step: MKRoute.Step?, distance: CLLocationDistance, minutes: Int, speed: Double, limit: Int?) {
        guard V17.on("island") else { return }
        let text = step?.instructions ?? ""
        guard text != lastText || Date().timeIntervalSince(last) > 5 else { return }
        last = Date(); lastText = text
        for a in Activity<NavActivityAttributes>.activities {
            var st = a.content.state
            st.minutesLeft = minutes; st.arrival = .now.addingTimeInterval(Double(minutes) * 60)
            st.turnText = text.isEmpty ? nil : text; st.turnSymbol = symbol(text); st.turnDistance = Int(max(0, distance))
            st.speedKmh = Int(max(0, speed)); st.limitKmh = limit
            Task { await a.update(.init(state: st, staleDate: .now.addingTimeInterval(120))) }
        }
    }
}

// MARK: - 4. Bendri pranešimai (nemokamas Supabase serveris)

enum SharedServer17 {
    /// Serveris įrašomas kompiliuojant (GitHub Secrets → Info.plist), todėl naudotojui nieko vesti nereikia.
    /// Jei nustatymuose įvestas kitas serveris – naudojamas jis.
    static var url: String {
        let own = UserDefaults.standard.string(forKey: "supabaseURL") ?? ""
        return own.isEmpty ? (Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "") : own
    }
    static var key: String {
        let own = UserDefaults.standard.string(forKey: "supabaseKey") ?? ""
        return own.isEmpty ? (Bundle.main.object(forInfoDictionaryKey: "SupabaseKey") as? String ?? "") : own
    }
    static var available: Bool { url.hasPrefix("https://") && !key.isEmpty }
    static var active: Bool { V17.on("shared") && available }
}

// MARK: - Nustatymai

struct V17Section: View {
    @AppStorage("f.tolls") private var tolls = true
    @AppStorage("f.scenic") private var scenic = true
    @AppStorage("f.island") private var island = true
    @AppStorage("f.shared") private var shared = true
    @StateObject private var vig = VignetteChecker()
    var body: some View {
        Section {
            Toggle(isOn: $tolls) { Label { VStack(alignment: .leading) { Text("Rinkliavos ir vinjetės"); Text("Įspėja apie mokamus kelius ir vinjetes, leidžia jų vengti").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "eurosign.circle") } }
            Toggle(isOn: $scenic) { Label { VStack(alignment: .leading) { Text("Vaizdingas maršrutas"); Text("Pasirinkimas važiuoti gražesniu keliu pro ežerus ir miškus").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "tree") } }
            if tolls || scenic { NavigationLink("Maršruto parinktys") { RouteOptionsSheet(vig: vig) {} } }
            Toggle(isOn: $island) { Label { VStack(alignment: .leading) { Text("Dynamic Island"); Text("Posūkis, atstumas ir atvykimo laikas viršuje, kai programėlė fone").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "capsule.fill") } }
            Toggle(isOn: $shared) { Label { VStack(alignment: .leading) { Text("Bendri pranešimai"); Text("Policija, duobės ir avarijos matomos visiems CarVideo vairuotojams").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "antenna.radiowaves.left.and.right") } }
            if shared {
                Label(SharedServer17.available ? "Prisijungta prie bendro serverio" : "Serveris nenustatytas – pranešimai tik šiame telefone",
                      systemImage: SharedServer17.available ? "checkmark.circle.fill" : "exclamationmark.triangle").font(.caption).foregroundStyle(SharedServer17.available ? .green : .orange)
            }
        } header: { Text("v17") } footer: { Text("Be vardų ir paskyrų – siunčiama tik vieta, tipas ir laikas. Serveris nemokamas.") }
    }
}
