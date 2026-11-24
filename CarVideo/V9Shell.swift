import SwiftUI
import AVFoundation
import CoreLocation

// MARK: - v9: programėlės skirtukai (Pradžia · Valdikliai · Garsai · Greitis · Nustatymai)
// Struktūra įkvėpta Car Connect, dizainas ir funkcijos – savi. Viskas nemokama, be markių logotipų.

enum Units {
    static var mph: Bool { UserDefaults.standard.string(forKey: "units") == "mph" }
    static var fahrenheit: Bool { UserDefaults.standard.string(forKey: "tempUnit") == "f" }
    static func speed(_ kmh: Double) -> Int { Int((mph ? kmh * 0.621371 : kmh).rounded()) }
    static var speedLabel: String { mph ? "mph" : "km/h" }
    static func distance(_ km: Double) -> String { mph ? String(format: "%.1f mi", km * 0.621371) : String(format: "%.1f km", km) }
    static func temp(_ c: Double) -> String { fahrenheit ? "\(Int((c * 9 / 5 + 32).rounded()))°F" : "\(Int(c.rounded()))°" }
}

struct AppShell: View {
    @State private var tab = 0
    @AppStorage("keepAwake") private var keepAwake = true
    @StateObject private var carLink = CarConnectionMonitor()
    @AppStorage("f.wizard") private var wizardOn = true
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        TabView(selection: $tab) {
            HomeTab().tag(0).tabItem { Label("Pradžia", systemImage: "square.grid.2x2.fill") }
            WidgetsGalleryView().tag(1).tabItem { Label("Valdikliai", systemImage: "rectangle.stack.fill") }
            SoundsView(link: carLink).tag(2).tabItem { Label("Garsai", systemImage: "speaker.wave.2.fill") }
            SpeedTabView().tag(3).tabItem { Label("Greitis", systemImage: "gauge.with.needle") }
            AppSettingsView().tag(4).tabItem { Label("Nustatymai", systemImage: "gearshape.fill") }
        }
        .tint(Color(red: 0.5, green: 0.74, blue: 1))
        // v10: pirmo paleidimo vedlys
        .fullScreenCover(isPresented: Binding(get: { wizardOn && !onboarded }, set: { _ in })) { OnboardingView() }
        // Ekranas neužgęsta, kol programėlė atidaryta (jei įjungta).
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onChange(of: keepAwake) { _, v in UIApplication.shared.isIdleTimerDisabled = v }
    }
}

// MARK: - Prisijungimo prie automobilio garsai

/// Seka, ar garsas eina į CarPlay / Bluetooth automobilį, ir sugroja pasirinktą garsą.
/// iOS praneša apie tai tik kai programėlė veikia, todėl patikimiausia – automatizavimas
/// „Spartieji klavišai → CarPlay → Prisijungia → Atidaryti CarVideo“.
@MainActor
final class CarConnectionMonitor: ObservableObject {
    @Published private(set) var connected = false
    private let ud = UserDefaults.standard
    @Published var chimeOn: String { didSet { ud.set(chimeOn, forKey: "chimeOn") } }
    @Published var chimeOff: String { didSet { ud.set(chimeOff, forKey: "chimeOff") } }
    @Published var greet: Bool { didSet { ud.set(greet, forKey: "greetVoice") } }
    private let synth = AVSpeechSynthesizer()

    init() {
        chimeOn = UserDefaults.standard.string(forKey: "chimeOn") ?? "rise"
        chimeOff = UserDefaults.standard.string(forKey: "chimeOff") ?? "soft"
        greet = UserDefaults.standard.bool(forKey: "greetVoice")
        connected = Self.isCar()
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.routeChanged() }
        }
    }

    static func isCar() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { [.carAudio, .bluetoothA2DP, .bluetoothHFP].contains($0.portType) }
    }

    private func routeChanged() {
        let now = Self.isCar()
        guard now != connected else { return }
        connected = now
        fire(now)
        // v11: automatinis veiksmas, kai programėlė jau veikia
        if now, Feature.on("f.autolaunch") {
            UserDefaults.standard.set(UserDefaults.standard.string(forKey: "autoAction") ?? "music", forKey: "pendingCarAction")
            NotificationCenter.default.post(name: .carActionRequested, object: nil)
        }
    }

    func fire(_ on: Bool) {
        Chime.play(on ? chimeOn : chimeOff)
        if greet {
            let u = AVSpeechUtterance(string: on ? "Gero kelio" : "Iki kito karto")
            u.voice = AVSpeechSynthesisVoice(language: "lt-LT")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.synth.speak(u) }
        }
    }
}

/// Mūsų sukurti garsai – sintezuojami programėlėje, jokių svetimų failų.
enum Chime: String, CaseIterable, Identifiable {
    case rise, soft, glass, sport, retro, none
    var id: String { rawValue }
    var title: String { ["rise": "Pakilimas", "soft": "Švelnus", "glass": "Kristalas", "sport": "Sportinis", "retro": "Retro", "none": "Be garso"][rawValue]! }
    var notes: [Double] {
        switch self {
        case .rise: [523, 659, 784, 1047]
        case .soft: [784, 523]
        case .glass: [1319, 1760, 2637]
        case .sport: [196, 294, 392]
        case .retro: [880, 660, 880, 1175]
        case .none: []
        }
    }

    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var ready = false

    static func play(_ raw: String) {
        guard let c = Chime(rawValue: raw), !c.notes.isEmpty else { return }
        let sr = 44100.0
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let step = 0.13, tail = 0.55
        let total = AVAudioFrameCount(sr * (step * Double(c.notes.count) + tail))
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: total) else { return }
        buf.frameLength = total
        let d = buf.floatChannelData![0]
        for i in 0..<Int(total) { d[i] = 0 }
        for (n, f) in c.notes.enumerated() {
            let start = Int(sr * step * Double(n))
            for i in 0..<Int(sr * tail) where start + i < Int(total) {
                let t = Double(i) / sr
                let env = min(1, t / 0.015) * exp(-t * 9)
                var s = sin(2 * .pi * f * t)
                if c == .sport || c == .retro { s = s > 0 ? 0.35 : -0.35 }
                d[start + i] += Float(s * env * 0.25)
            }
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            if !ready { engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: fmt); ready = true }
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(buf, at: nil, options: .interrupts)
            player.play()
        } catch {}
    }
}

struct SoundsView: View {
    @ObservedObject var link: CarConnectionMonitor
    @State private var showHow = false
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Trumpas garsas, kai telefonas prisijungia prie automobilio ar atsijungia nuo jo.").foregroundStyle(.secondary) }
                Section("Prisijungus") { picker($link.chimeOn) }
                Section("Atsijungus") { picker($link.chimeOff) }
                Section {
                    Toggle("Pasisveikinti balsu („Gero kelio“)", isOn: $link.greet)
                    Button("Išbandyti: prisijungti") { link.fire(true) }
                    Button("Išbandyti: atsijungti") { link.fire(false) }
                    Button("Kaip tai veikia?") { showHow = true }
                } footer: { Text(link.connected ? "Dabar prijungta prie automobilio" : "Dabar neprijungta") }
            }
            .navigationTitle("Garsai")
            .sheet(isPresented: $showHow) { InfoSheet(kind: .sounds) }
        }
    }
    private func picker(_ b: Binding<String>) -> some View {
        ForEach(Chime.allCases) { c in
            Button { b.wrappedValue = c.rawValue; Chime.play(c.rawValue) } label: {
                HStack { Text(c.title); Spacer(); if b.wrappedValue == c.rawValue { Image(systemName: "checkmark") } }
            }.foregroundStyle(.primary)
        }
    }
}

// MARK: - Greitis

struct SpeedTabView: View {
    @StateObject private var loc = LocationManager()
    @StateObject private var trips = TripStore()
    @AppStorage("carMake") private var carMake = "BMW"
    @AppStorage("gaugeStyle") private var gaugeStyleRaw = "auto"
    @AppStorage("units") private var units = "kmh"
    @AppStorage("speedLimitKmh") private var limit: Double = 300
    @State private var running = false
    @AppStorage("f.log") private var logOn = true

    private var style: GaugeStyle { GaugeStyle(rawValue: gaugeStyleRaw) ?? .forMake(carMake) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    BrandGauge(style: style, speed: Double(Units.speed(loc.speedKmh)), limit: Double(Units.speed(limit)))
                        .frame(width: 240, height: 240)
                    Button(running ? "Baigti kelionę" : "Pradėti kelionę") {
                        if running { trips.finish() } else { trips.manualStart = true }
                        running.toggle()
                    }
                    .buttonStyle(.borderedProminent).tint(running ? .red : .accentColor).controlSize(.large)
                    if let c = trips.current {
                        Text("\(Units.distance(c.km)) · \(Int(c.minutes)) min · maks. \(Units.speed(c.maxKmh)) \(Units.speedLabel)").foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        stat("Paskutinė kelionė", trips.trips.first.map { Units.distance($0.km) } ?? "–", trips.trips.first.map { "\(Int($0.minutes)) min" } ?? "Dar nebuvo")
                        stat("Serija", "\(trips.streakDays) d.", "Dienos iš eilės prie vairo")
                        stat("Didžiausias greitis", trips.best.map { "\(Units.speed($0.maxKmh)) \(Units.speedLabel)" } ?? "–", "Rekordas")
                        stat("Iš viso", Units.distance(trips.totalKm), "\(trips.trips.count) kelionių")
                    }
                    if logOn { NavigationLink("Kelionių žurnalas") { TripLogView(store: trips) }.buttonStyle(.bordered) }
                }.padding()
            }
            .navigationTitle("Greitis")
            .onAppear { trips.reload() }
            .onChange(of: loc.location) { _, l in if let l { trips.update(with: l, destination: nil) } }
        }
    }
    private func stat(_ k: String, _ v: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k.uppercased()).font(.caption2).tracking(1.2).foregroundStyle(.secondary)
            Text(v).font(.system(size: 26, weight: .light))
            Text(s).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Valdikliai (peržiūra programėlėje; patys valdikliai – CarVideoWidget)

struct WidgetsGalleryView: View {
    @AppStorage("setupHidden") private var setupHidden = false
    @State private var showSetup = false
    private let cols = [GridItem(.adaptive(minimum: 160), spacing: 10)]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !setupHidden {
                        HStack(spacing: 12) {
                            Image(systemName: "car.fill").font(.title2).frame(width: 46, height: 46).background(.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading) { Text("Prijunk prie automobilio").bold(); Text("Kad programėlė atsidarytų pati, kai sėdi į mašiną.").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Kaip") { showSetup = true }.buttonStyle(.borderedProminent)
                            Button { setupHidden = true } label: { Image(systemName: "xmark") }
                        }.padding(14).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                    }
                    Text("Valdiklius pridėsi iPhone ekrane: palaikyk tuščią vietą → „+“ → CarVideo.").font(.footnote).foregroundStyle(.secondary)
                    LazyVGrid(columns: cols, spacing: 10) {
                        card("Važiuoti namo", "~12 min", [.blue, .indigo])
                        card("Metų progresas", String(format: "%.1f%%", YearProgress.percent), [.purple, .indigo])
                        card("Dienos mintis", "„\(Quotes.today)“", [.gray, .black])
                    }
                }.padding()
            }
            .navigationTitle("Valdikliai")
            .sheet(isPresented: $showSetup) { InfoSheet(kind: .setup) }
        }
    }
    private func card(_ t: String, _ v: String, _ c: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t.uppercased()).font(.caption2).tracking(1.2).opacity(0.75)
            Spacer()
            Text(v).font(.system(size: 22, weight: .light)).lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading).padding(12)
        .background(LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
    }
}

enum YearProgress {
    static var percent: Double {
        let cal = Calendar.current, now = Date()
        let y0 = cal.date(from: cal.dateComponents([.year], from: now))!
        let y1 = cal.date(byAdding: .year, value: 1, to: y0)!
        return now.timeIntervalSince(y0) / y1.timeIntervalSince(y0) * 100
    }
}
enum Quotes {
    static let all = ["Geriausias kelias – tas, kuriuo grįžti namo.", "Lėčiau važiuoji – daugiau pamatai.", "Kelionė prasideda ne nuo rakto, o nuo noro.", "Saugiai šiandien – dar daug kelionių rytoj.", "Kiekvienas kilometras – nauja istorija."]
    static var today: String { all[Calendar.current.component(.day, from: Date()) % all.count] }
}

// MARK: - Nustatymai

struct AppSettingsView: View {
    @AppStorage("units") private var units = "kmh"
    @AppStorage("tempUnit") private var temp = "c"
    @AppStorage("keepAwake") private var keepAwake = true
    @State private var info: InfoSheet.Kind?
    private let icons: [(String?, String)] = [(nil, "Naktis"), ("IconBlue", "Mėlyna"), ("IconLight", "Šviesi"), ("IconSunset", "Saulėlydis")]

    var body: some View {
        NavigationStack {
            Form {
                Section("Vienetai") {
                    Picker("Greitis", selection: $units) { Text("km/h").tag("kmh"); Text("mph").tag("mph") }.pickerStyle(.segmented)
                    Picker("Temperatūra", selection: $temp) { Text("°C").tag("c"); Text("°F").tag("f") }.pickerStyle(.segmented)
                }
                FeaturesSection()   // v10
                V11FeaturesSection()   // v11
                V12Section()   // v12
                V13Section()   // v13
                V14Section()   // v14
                V15Section()   // v15
                V16Section()   // v16
                V17Section()   // v17
                Section("Funkcijos") {
                    Toggle(isOn: $keepAwake) { Label("Ekranas neužgęsta važiuojant", systemImage: "iphone") }
                }
                Section("Programėlės piktograma") {
                    ForEach(icons, id: \.1) { name, title in
                        // Paveikslėliai IconBlue/IconLight/IconSunset pridedami į Assets prieš build'ą.
                        Button(title) { UIApplication.shared.setAlternateIconName(name) }
                    }
                }
                Section("Apie") {
                    Link(destination: URL(string: "mailto:")!) { Label("Pasiūlyti idėją", systemImage: "lightbulb") }
                    Link(destination: URL(string: "mailto:")!) { Label("Susisiekti", systemImage: "envelope") }
                    ShareLink(item: "CarVideo – video, muzika ir navigacija automobilyje") { Label("Pasidalinti programėle", systemImage: "square.and.arrow.up") }
                }
                Section("Teisinė informacija") {
                    Button { info = .privacy } label: { Label("Privatumo politika", systemImage: "hand.raised") }
                    Button { info = .terms } label: { Label("Naudojimo sąlygos", systemImage: "doc.text") }
                    Button { info = .licenses } label: { Label("Licencijos ir šaltiniai", systemImage: "c.circle") }
                }
                Section { Text("CarVideo 12.0 · viskas nemokama").foregroundStyle(.secondary) }
            }
            .navigationTitle("Nustatymai")
            .sheet(item: $info) { InfoSheet(kind: $0) }
        }
    }
}

struct InfoSheet: View {
    enum Kind: String, Identifiable { case privacy, terms, licenses, setup, sounds; var id: String { rawValue } }
    let kind: Kind
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { Text(text).padding().frame(maxWidth: .infinity, alignment: .leading) }
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Gerai") { dismiss() } }
        }
    }
    private var title: String { ["privacy": "Privatumo politika", "terms": "Naudojimo sąlygos", "licenses": "Licencijos", "setup": "Prijungimas", "sounds": "Garsai"][kind.rawValue]! }
    private var text: String {
        switch kind {
        case .privacy: "CarVideo neturi paskyrų, reklamų ir sekimo. Viskas, ką įvedi, lieka tik tavo iPhone.\n\nVieta naudojama tik navigacijai, greičiui ir orams. Užklausos žemėlapių ir orų tarnyboms (Apple Maps, Open-Meteo, OpenStreetMap) siunčiamos be tavo vardo.\n\nPranešus apie kliūtį kelyje, siunčiama tik jos vieta, tipas ir laikas. Po 1 valandos pranešimas ištrinamas.\n\nIštrynus programėlę, dingsta ir visi duomenys."
        case .terms: "Programėlė nemokama ir pateikiama „tokia, kokia yra“. Vairuotojas visada atsako už saugų vairavimą. Greičio ribos ir kameros imamos iš OpenStreetMap ir gali būti netikslios. YouTube ir Spotify turinį teikia jų savininkai."
        case .licenses: "Žemėlapiai: Apple Maps, pasirinktinai Google Maps. Greičio ribos ir kameros: © OpenStreetMap bendraautoriai (ODbL). Orai: Open-Meteo (CC BY 4.0). Automobilių sąrašas: Wikidata (CC0). Nuotraukos: Wikimedia Commons. 3D automobilis: sukurtas CarVideo (savas, be svetimų licencijų)."
        case .setup: "1. CarPlay: Nustatymai → Bendra → CarPlay → pasirink automobilį.\n\n2. Kad CarVideo atsidarytų pati: „Spartieji klavišai“ → Automatizavimas → „+“ → CarPlay → Prisijungia → Atidaryti programą → CarVideo → Vykdyti iškart.\n\n3. Be CarPlay: tas pats, tik rinkis „Bluetooth“ ir savo automobilį."
        case .sounds: "Kai CarVideo veikia, ji mato, kad garsas persijungė į automobilį per CarPlay ar Bluetooth, ir sugroja pasirinktą garsą. Kad skambėtų kiekvieną kartą, nustatyk automatizavimą (žr. Valdikliai → Kaip prijungti)."
        }
    }
}
