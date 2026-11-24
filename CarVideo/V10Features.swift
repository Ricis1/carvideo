import SwiftUI
import MapKit
import SceneKit
import ActivityKit
import UserNotifications

// MARK: - v10: 7 funkcijos, kiekvieną galima išjungti (Nustatymai → Papildomos funkcijos)

enum Feature: String, CaseIterable, Identifiable {
    case own3d, passenger, live, log, remind, wizard, portrait
    var id: String { rawValue }
    var key: String { "f." + rawValue }
    var title: String {
        switch self {
        case .own3d: "Savas 3D automobilis"
        case .passenger: "Keleivio režimas"
        case .live: "Užrakinto ekrano valdiklis"
        case .log: "Kelionių žurnalas"
        case .remind: "Priminimai automobiliui"
        case .wizard: "Pirmo paleidimo vedlys"
        case .portrait: "Stačias režimas"
        }
    }
    var detail: String {
        switch self {
        case .own3d: "Mūsų sukurtas modelis, tinka viešam išleidimui"
        case .passenger: "Video nesustoja, kai patvirtini, kad žiūri keleivis"
        case .live: "Laikas iki tikslo ir eismas ant užrakinto ekrano"
        case .log: "Maršrutas žemėlapyje, darbo / asmeninė, eksportas"
        case .remind: "Techninė apžiūra, draudimas, padangų keitimas"
        case .wizard: "Trumpas nustatymas pirmą kartą atidarius"
        case .portrait: "Pagrindinis ekranas ir telefoną laikant stačiai"
        }
    }
    var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

struct FeatureToggle: View {
    let f: Feature
    @AppStorage private var on: Bool
    init(_ f: Feature) { self.f = f; _on = AppStorage(wrappedValue: true, f.key) }
    var body: some View {
        Toggle(isOn: $on) { VStack(alignment: .leading) { Text(LocalizedStringKey(f.title)); Text(LocalizedStringKey(f.detail)).font(.caption).foregroundStyle(.secondary) } }
            .onChange(of: on) { _, v in
                if f == .remind { v ? Reminders.reschedule() : Reminders.cancelAll() }
                if f == .live, !v { LiveRoute.end() }
            }
    }
}

struct FeaturesSection: View {
    @AppStorage("f.remind") private var remindOn = true
    @AppStorage("f.wizard") private var wizardOn = true
    @AppStorage("onboarded") private var onboarded = false
    var body: some View {
        Section("Papildomos funkcijos") { ForEach(Feature.allCases) { FeatureToggle($0) } }
        if remindOn { RemindersSection() }
        if wizardOn { Section { Button("Paleisti pirmo nustatymo vedlį iš naujo") { onboarded = false } } }
    }
}

// MARK: Užrakinto ekrano valdiklis (Live Activity)

enum LiveRoute {
    static func start(to dest: String, minutes: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        let st = NavActivityAttributes.ContentState(minutesLeft: minutes, arrival: .now.addingTimeInterval(Double(minutes) * 60), traffic: "vidutinis")
        _ = try? Activity.request(attributes: NavActivityAttributes(destination: dest.isEmpty ? "Tikslas" : dest), content: .init(state: st, staleDate: nil))
    }
    static func update(minutes: Int) {
        for a in Activity<NavActivityAttributes>.activities {
            let st = NavActivityAttributes.ContentState(minutesLeft: minutes, arrival: .now.addingTimeInterval(Double(minutes) * 60), traffic: a.content.state.traffic)
            Task { await a.update(.init(state: st, staleDate: nil)) }
        }
    }
    static func end() {
        for a in Activity<NavActivityAttributes>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}

// MARK: Priminimai (TA, draudimas, padangos)

enum Reminders {
    static let ud = UserDefaults.standard
    static func date(_ k: String) -> Date? { let t = ud.double(forKey: "rem." + k); return t > 0 ? Date(timeIntervalSince1970: t) : nil }
    static func set(_ k: String, _ d: Date?) { ud.set(d?.timeIntervalSince1970 ?? 0, forKey: "rem." + k); reschedule() }
    static var tiresOn: Bool { ud.object(forKey: "rem.tires") as? Bool ?? true }

    /// v12: pagal šalį (Region). Lietuvoje žieminės privalomos lapkričio 10 – balandžio 1.
    static func nextTireChange(from now: Date = .now) -> (String, Date) {
        let r = Region.current, cal = Calendar.current, y = cal.component(.year, from: now)
        guard let (wm, wd, sm, sd) = r.winterTyres else {
            return (r.byWeather ? "Žieminės padangos – pagal orą (\(r.name))" : "Padangų datos nėra (\(r.name))", .distantFuture)
        }
        let winter = cal.date(from: DateComponents(year: y, month: wm, day: wd))!
        let summer = cal.date(from: DateComponents(year: y, month: sm, day: sd))!
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMMd")
        if now < summer { return ("Vasarinės padangos nuo \(f.string(from: summer))", summer) }
        if now < winter { return ("Žieminės padangos nuo \(f.string(from: winter))", winter) }
        let next = cal.date(byAdding: .year, value: 1, to: summer)!
        return ("Vasarinės padangos nuo \(f.string(from: next))", next)
    }

    static func cancelAll() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["ta", "ins", "tires"].flatMap { ["\($0).14", "\($0).1"] }) }

    static func reschedule() {
        cancelAll()
        guard Feature.remind.isOn else { return }
        var items: [(String, String, Date)] = []
        if let d = date("ta") { items.append(("ta", "Techninė apžiūra", d)) }
        if let d = date("ins") { items.append(("ins", "Baigiasi draudimas", d)) }
        if tiresOn, Region.current.winterTyres != nil { let t = nextTireChange(); items.append(("tires", t.0, t.1)) }
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            for (id, title, d) in items {
                for days in [14, 1] {
                    guard let at = Calendar.current.date(byAdding: .day, value: -days, to: d), at > .now else { continue }
                    let n = UNMutableNotificationContent(); n.title = title; n.body = days == 1 ? "Rytoj" : "Po 2 savaičių"; n.sound = .default
                    var dc = Calendar.current.dateComponents([.year, .month, .day], from: at); dc.hour = 10
                    c.add(UNNotificationRequest(identifier: "\(id).\(days)", content: n, trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)))
                }
            }
        }
    }
}

struct RemindersSection: View {
    @State private var ta = Reminders.date("ta") ?? .now
    @State private var ins = Reminders.date("ins") ?? .now
    @State private var hasTA = Reminders.date("ta") != nil
    @State private var hasIns = Reminders.date("ins") != nil
    @AppStorage("rem.tires") private var tires = true
    var body: some View {
        Section {
            Toggle("Techninė apžiūra", isOn: $hasTA)
            if hasTA { DatePicker("Data", selection: $ta, displayedComponents: .date) }
            Toggle("Draudimas", isOn: $hasIns)
            if hasIns { DatePicker("Baigiasi", selection: $ins, displayedComponents: .date) }
            Toggle(isOn: $tires) { VStack(alignment: .leading) { Text("Padangų keitimas"); Text(Reminders.nextTireChange().0).font(.caption).foregroundStyle(.secondary) } }
        } header: { Text("Priminimai") } footer: { Text("Priminsim prieš 14 dienų ir išvakarėse.") }
        .onChange(of: hasTA) { _, v in Reminders.set("ta", v ? ta : nil) }
        .onChange(of: ta) { _, d in if hasTA { Reminders.set("ta", d) } }
        .onChange(of: hasIns) { _, v in Reminders.set("ins", v ? ins : nil) }
        .onChange(of: ins) { _, d in if hasIns { Reminders.set("ins", d) } }
        .onChange(of: tires) { _, _ in Reminders.reschedule() }
    }
}

// MARK: Kelionių žurnalas

struct TripLogView: View {
    @ObservedObject var store: TripStore
    var body: some View {
        List {
            Section {
                ShareLink(item: store.csvFile()) { Label("Eksportuoti CSV", systemImage: "square.and.arrow.up") }
                Text("Darbo kelionės: " + Units.distance(store.trips.filter { $0.business ?? false }.reduce(0) { $0 + $1.km })).foregroundStyle(.secondary)
            }
            ForEach(store.trips) { t in
                HStack(spacing: 12) {
                    TripMiniMap(trip: t).frame(width: 90, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading) {
                        Text(t.destination ?? "Kelionė").bold()
                        Text("\(t.start.formatted(date: .abbreviated, time: .shortened)) · \(Units.distance(t.km)) · \(Int(t.minutes)) min").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button((t.business ?? false) ? "Darbo" : "Asmeninė") { store.toggleBusiness(t.id) }
                        .buttonStyle(.bordered).tint((t.business ?? false) ? .orange : .gray)
                }
            }
            .onDelete(perform: store.delete)
        }
        .navigationTitle("Kelionių žurnalas")
    }
}

struct TripMiniMap: View {
    let trip: Trip
    var body: some View {
        let pts = (trip.path ?? []).map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
        Map(interactionModes: []) {
            if pts.count > 1 { MapPolyline(coordinates: pts).stroke(.blue, lineWidth: 3) }
            if let f = pts.first { Annotation("", coordinate: f) { Circle().fill(.white).frame(width: 7) } }
            if let l = pts.last { Annotation("", coordinate: l) { Circle().fill(.green).frame(width: 8) } }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

// MARK: Pirmo paleidimo vedlys

struct OnboardingView: View {
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("homeAddress") private var home = ""
    @AppStorage("navProvider") private var nav = "apple"
    @AppStorage("units") private var units = "kmh"
    @AppStorage("speedLimitKmh") private var limit: Double = 300
    @State private var step = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { ForEach(0..<4) { i in Capsule().fill(i == step ? Color.accentColor : .gray.opacity(0.3)).frame(width: i == step ? 22 : 8, height: 8) } }
            switch step {
            case 0: page("Sveiki atvykę į CarVideo", "Video, muzika ir navigacija automobilyje vienoje programėlėje. Nustatysim per minutę.") { EmptyView() }
            case 1: page("Kur tavo namai?", "Tada vienu paspaudimu galėsi važiuoti namo.") { TextField("Namų adresas", text: $home).textFieldStyle(.roundedBorder) }
            case 2: page("Kuo naviguoji?", "Apple rodoma programėlės viduje. Waze ir Google Maps atsidaro savo programėlėje.") {
                Picker("", selection: $nav) { Text("Apple").tag("apple"); Text("Waze").tag("waze"); Text("Google Maps").tag("google") }.pickerStyle(.segmented) }
            default: page("Greitis ir vienetai", "Video sustoja, kai greitis viršija ribą.") {
                Picker("", selection: $units) { Text("km/h").tag("kmh"); Text("mph").tag("mph") }.pickerStyle(.segmented)
                Stepper("Riba: \(Int(limit)) km/h", value: $limit, in: 0...300, step: 10) }
            }
            HStack {
                Button(step == 0 ? "Praleisti" : "Atgal") { if step == 0 { onboarded = true } else { step -= 1 } }.buttonStyle(.bordered)
                Spacer()
                Button(step == 3 ? "Pradėti" : "Toliau") { if step == 3 { onboarded = true } else { step += 1 } }.buttonStyle(.borderedProminent)
            }
        }
        .padding(28).frame(maxWidth: 560)
    }
    @ViewBuilder private func page<C: View>(_ t: String, _ d: String, @ViewBuilder _ c: () -> C) -> some View {
        Text(t).font(.largeTitle.bold()); Text(d).foregroundStyle(.secondary); c()
    }
}

// MARK: Stačias režimas – pagrindinis ekranas
// „Namo“ stačiai: Waze / Google atsidaro savo programėlėje; Apple – Apple Maps (pilna navigacija gulsčiai programėlėje).

struct PortraitHomeView: View {
    @AppStorage("homeAddress") private var home = ""
    @AppStorage("navProvider") private var navRaw = "apple"
    @Environment(\.openURL) private var openURL
    @State private var pos: MapCameraPosition = .userLocation(fallback: .automatic)
    @MainActor private func goHome() {
        let p = NavProvider(rawValue: navRaw) ?? .apple
        if p == .apple, let q = home.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let u = URL(string: "maps://?daddr=\(q)&dirflg=d") { openURL(u) }
        else { ExternalNav.open(p, query: home) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TimelineView(.everyMinute) { c in Text(c.date, style: .time).font(.system(size: 56, weight: .thin)) }
                if Feature.own3d.isOn { OwnCar16View().frame(height: 170) }   // v16: kėbulai ir ratlankiai
                Map(position: $pos) { UserAnnotation() }
                    .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(alignment: .bottomLeading) {
                        HStack {
                            Button("Namo") { goHome() }.buttonStyle(.borderedProminent)
                        }.padding(12)
                    }
                if Feature.remind.isOn, Reminders.tiresOn, Region.current.winterTyres != nil {
                    let t = Reminders.nextTireChange()
                    Label("\(t.0) · po \(Calendar.current.dateComponents([.day], from: .now, to: t.1).day ?? 0) d.", systemImage: "bell").font(.footnote)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }
                Text("Video ir navigacija per visą ekraną – pasuk telefoną gulsčiai.").font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }
    }
}

/// Pagrindinis skirtukas: gulsčiai – automobilio ekranas, stačiai – PortraitHomeView (jei įjungta).
struct HomeTab: View {
    @Environment(\.verticalSizeClass) private var vClass
    @AppStorage("f.portrait") private var portraitOn = true
    var body: some View {
        if portraitOn && vClass == .regular { PortraitHomeView() } else { ContentView() }
    }
}

// MARK: Savas 3D automobilis (sukurtas kodu, jokių svetimų licencijų)

struct OwnCarView: UIViewRepresentable {
    @AppStorage("carColorHex") private var colorHex = "#9AA0A6"
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(); v.backgroundColor = .clear; v.autoenablesDefaultLighting = true; v.allowsCameraControl = true; v.antialiasingMode = .multisampling4X
        v.scene = Self.scene(color: UIColor(hex: colorHex)); return v
    }
    func updateUIView(_ v: SCNView, context: Context) {}

    static func scene(color: UIColor) -> SCNScene {
        let s = SCNScene(), car = SCNNode()
        let paint = SCNMaterial(); paint.lightingModel = .physicallyBased; paint.diffuse.contents = color; paint.metalness.contents = 0.6; paint.roughness.contents = 0.3
        let glass = SCNMaterial(); glass.lightingModel = .physicallyBased; glass.diffuse.contents = UIColor(white: 0.03, alpha: 1); glass.roughness.contents = 0.05
        // apatinė kėbulo dalis
        let b = UIBezierPath(); b.move(to: CGPoint(x: 2.32, y: 0.34)); b.addLine(to: CGPoint(x: 2.36, y: 0.5)); b.addQuadCurve(to: CGPoint(x: 1.9, y: 0.72), controlPoint: CGPoint(x: 2.3, y: 0.68))
        b.addLine(to: CGPoint(x: 0.8, y: 0.84)); b.addLine(to: CGPoint(x: -1.75, y: 0.9)); b.addQuadCurve(to: CGPoint(x: -2.32, y: 0.8), controlPoint: CGPoint(x: -2.2, y: 0.88))
        b.addLine(to: CGPoint(x: -2.36, y: 0.42)); b.addLine(to: CGPoint(x: -2.25, y: 0.3)); b.addLine(to: CGPoint(x: -1.82, y: 0.3))
        b.addArc(withCenter: CGPoint(x: -1.42, y: 0.36), radius: 0.42, startAngle: .pi, endAngle: 0, clockwise: false)
        b.addLine(to: CGPoint(x: 1.02, y: 0.3)); b.addArc(withCenter: CGPoint(x: 1.42, y: 0.36), radius: 0.42, startAngle: .pi, endAngle: 0, clockwise: false); b.close()
        b.flatness = 0.005
        let body = SCNShape(path: b, extrusionDepth: 1.8); body.chamferRadius = 0.12; body.materials = [paint]
        car.addChildNode(SCNNode(geometry: body))
        // stiklinis salonas
        let h = UIBezierPath(); h.move(to: CGPoint(x: 0.95, y: 0.8)); h.addQuadCurve(to: CGPoint(x: -0.35, y: 1.33), controlPoint: CGPoint(x: 0.3, y: 1.3))
        h.addQuadCurve(to: CGPoint(x: -1.85, y: 0.88), controlPoint: CGPoint(x: -1.2, y: 1.3)); h.close(); h.flatness = 0.005
        let cab = SCNShape(path: h, extrusionDepth: 1.4); cab.chamferRadius = 0.14; cab.materials = [glass]
        car.addChildNode(SCNNode(geometry: cab))
        // ratai
        for (x, z) in [(1.42, 0.84), (1.42, -0.84), (-1.42, 0.84), (-1.42, -0.84)] {
            let tire = SCNCylinder(radius: 0.35, height: 0.26); tire.firstMaterial?.diffuse.contents = UIColor(white: 0.05, alpha: 1)
            let n = SCNNode(geometry: tire); n.eulerAngles.x = .pi / 2; n.position = SCNVector3(x, 0.35, z); car.addChildNode(n)
            let rim = SCNCylinder(radius: 0.24, height: 0.27); rim.firstMaterial?.lightingModel = .physicallyBased; rim.firstMaterial?.metalness.contents = 1.0; rim.firstMaterial?.diffuse.contents = UIColor.lightGray
            let r = SCNNode(geometry: rim); r.eulerAngles.x = .pi / 2; r.position = n.position; car.addChildNode(r)
        }
        car.eulerAngles.y = -0.6
        car.runAction(.repeatForever(.sequence([.rotateBy(x: 0, y: 0.4, z: 0, duration: 6), .rotateBy(x: 0, y: -0.4, z: 0, duration: 6)])))
        s.rootNode.addChildNode(car)
        let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera?.fieldOfView = 28; cam.position = SCNVector3(0, 1.4, 9.5); cam.look(at: SCNVector3(0, 0.6, 0)); s.rootNode.addChildNode(cam)
        return s
    }
}

extension UIColor {
    convenience init(hex: String) {
        var v: UInt64 = 0; Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}
