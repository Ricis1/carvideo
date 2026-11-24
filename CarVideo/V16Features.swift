// v16: savas 3D automobilis (5 kėbulai, 3 ratlankiai, žibintai), kelionė su sustojimais, elektromobilio kelionės planas.
// Kiekvieną funkciją galima išjungti: Nustatymai → v16.
import SwiftUI
import SceneKit
import MapKit

enum V16 { static func on(_ k: String) -> Bool { UserDefaults.standard.object(forKey: "f." + k) as? Bool ?? true } }

// MARK: - 1. Savas 3D automobilis
enum CarBody: String, CaseIterable, Identifiable {
    case coupe, sedan, hatch, wagon, suv
    var id: String { rawValue }
    var title: LocalizedStringKey { switch self { case .coupe: "Kupė"; case .sedan: "Sedanas"; case .hatch: "Hečbekas"; case .wagon: "Universalas"; case .suv: "Visureigis" } }
    /// Šoninio silueto parametrai (metrai, X – ilgis, Y – aukštis). Tie patys kaip demo.
    struct P { let L, R, wb, wr, gc, hf, b, br, roof, cf, rf, rr, cr, w: CGFloat; let vert, rails: Bool }
    var p: P {
        switch self {
        case .coupe: P(L: 2.36, R: -2.36, wb: 1.42, wr: 0.35, gc: 0.3, hf: 0.6, b: 0.84, br: 0.9, roof: 1.33, cf: 0.95, rf: -0.15, rr: -0.55, cr: -1.85, w: 1.62, vert: false, rails: false)
        case .sedan: P(L: 2.4, R: -2.45, wb: 1.45, wr: 0.34, gc: 0.3, hf: 0.64, b: 0.88, br: 0.94, roof: 1.43, cf: 1.0, rf: 0.05, rr: -0.85, cr: -1.6, w: 1.6, vert: false, rails: false)
        case .hatch: P(L: 2.0, R: -1.95, wb: 1.27, wr: 0.33, gc: 0.3, hf: 0.64, b: 0.88, br: 0.92, roof: 1.47, cf: 0.82, rf: 0.02, rr: -1.45, cr: -1.88, w: 1.56, vert: true, rails: false)
        case .wagon: P(L: 2.42, R: -2.42, wb: 1.45, wr: 0.34, gc: 0.3, hf: 0.64, b: 0.88, br: 0.92, roof: 1.45, cf: 1.0, rf: 0.12, rr: -2.0, cr: -2.33, w: 1.6, vert: true, rails: true)
        case .suv: P(L: 2.36, R: -2.36, wb: 1.42, wr: 0.42, gc: 0.46, hf: 0.95, b: 1.14, br: 1.16, roof: 1.84, cf: 0.9, rf: 0.08, rr: -1.95, cr: -2.26, w: 1.76, vert: true, rails: true)
        }
    }
}
enum RimStyle: String, CaseIterable, Identifiable {
    case sport, multi, aero
    var id: String { rawValue }
    var title: LocalizedStringKey { switch self { case .sport: "Sportiniai"; case .multi: "Daugiastipiniai"; case .aero: "Aerodinaminiai" } }
}

enum OwnCar16 {
    static func mat(_ c: UIColor, metal: CGFloat = 0, rough: CGFloat = 0.5, emission: UIColor? = nil) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased; m.diffuse.contents = c; m.metalness.contents = metal; m.roughness.contents = rough
        if let emission { m.emission.contents = emission }; return m
    }
    static func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ m: SCNMaterial, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNNode {
        let b = SCNBox(width: w, height: h, length: l, chamferRadius: min(w, h, l) * 0.3); b.materials = [m]
        let n = SCNNode(geometry: b); n.position = SCNVector3(x, y, z); return n
    }
    static func scene(color: UIColor, body: CarBody, rims: RimStyle) -> SCNScene {
        let s = SCNScene(), car = SCNNode(), P = body.p
        let paint = mat(color, metal: 0.6, rough: 0.28), glass = mat(UIColor(white: 0.03, alpha: 1), metal: 0.3, rough: 0.05)
        let black = mat(UIColor(white: 0.04, alpha: 1), rough: 0.8), trim = mat(UIColor(white: 0.09, alpha: 1), metal: 0.3, rough: 0.4)
        let chrome = mat(.lightGray, metal: 1, rough: 0.2), dark = mat(UIColor(white: 0.17, alpha: 1), metal: 0.8, rough: 0.35)
        // kėbulas
        let cy = P.wr + 0.01, rad = P.wr + 0.08, a0 = asin(max(-1, min(1, (P.gc - cy) / rad))), dx = rad * cos(a0)
        let b = UIBezierPath()
        b.move(to: CGPoint(x: P.L - 0.04, y: P.gc + 0.04)); b.addLine(to: CGPoint(x: P.L, y: P.hf - 0.14))
        b.addQuadCurve(to: CGPoint(x: P.L - 0.45, y: P.hf + 0.05), controlPoint: CGPoint(x: P.L - 0.03, y: P.hf))
        b.addLine(to: CGPoint(x: P.cf, y: P.b)); b.addLine(to: CGPoint(x: P.cr, y: P.br))
        if P.vert { b.addLine(to: CGPoint(x: P.R + 0.06, y: P.br - 0.02)); b.addQuadCurve(to: CGPoint(x: P.R, y: P.br - 0.2), controlPoint: CGPoint(x: P.R, y: P.br - 0.04)) }
        else { b.addQuadCurve(to: CGPoint(x: P.R + 0.02, y: P.br - 0.14), controlPoint: CGPoint(x: P.R + 0.12, y: P.br + 0.02)) }
        b.addLine(to: CGPoint(x: P.R, y: P.gc + 0.14)); b.addLine(to: CGPoint(x: P.R + 0.1, y: P.gc))
        for wx in [-P.wb, P.wb] {
            b.addLine(to: CGPoint(x: wx - dx, y: P.gc))
            b.addArc(withCenter: CGPoint(x: wx, y: cy), radius: rad, startAngle: .pi - a0, endAngle: a0, clockwise: false)   // UIKit: y žemyn, todėl „false“ eina viršumi
        }
        b.close(); b.flatness = 0.004
        let bodyG = SCNShape(path: b, extrusionDepth: P.w); bodyG.chamferRadius = 0.12; bodyG.materials = [paint]; car.addChildNode(SCNNode(geometry: bodyG))
        // salonas
        let cw = P.w - 0.4, h = UIBezierPath()
        h.move(to: CGPoint(x: P.cf, y: P.b - 0.04)); h.addQuadCurve(to: CGPoint(x: P.rf, y: P.roof), controlPoint: CGPoint(x: P.rf + (P.cf - P.rf) * 0.3, y: P.roof))
        h.addLine(to: CGPoint(x: P.rr, y: P.roof))
        h.addQuadCurve(to: CGPoint(x: P.cr, y: P.br - 0.03), controlPoint: P.vert ? CGPoint(x: P.cr + 0.04, y: P.roof) : CGPoint(x: P.cr + (P.rr - P.cr) * 0.45, y: P.roof - 0.03))
        h.close(); h.flatness = 0.004
        let cab = SCNShape(path: h, extrusionDepth: cw + 0.2); cab.chamferRadius = 0.14; cab.materials = [glass]; car.addChildNode(SCNNode(geometry: cab))
        car.addChildNode(box(abs(P.rf - P.rr) + 0.1, 0.04, cw + 0.2, paint, (P.rf + P.rr) / 2, P.roof + 0.02, 0))
        if P.rails { for sd: CGFloat in [1, -1] { car.addChildNode(box(abs(P.rf - P.rr) - 0.1, 0.04, 0.04, chrome, (P.rf + P.rr) / 2, P.roof + 0.07, sd * cw / 2)) } }
        // veidrodėliai, slenksčiai, grotelės, žibintai, išmetimas
        let hl = mat(.white, emission: UIColor(red: 0.87, green: 0.94, blue: 1, alpha: 1)), tl = mat(UIColor(red: 0.33, green: 0, blue: 0, alpha: 1), emission: .red)
        for sd: CGFloat in [1, -1] {
            car.addChildNode(box(0.16, 0.09, 0.14, paint, P.cf - 0.18, P.b + 0.07, sd * (P.w / 2 + 0.12)))
            car.addChildNode(box(2 * P.wb - 2 * rad - 0.1, 0.06, 0.03, trim, 0, P.gc + 0.06, sd * (P.w / 2 + 0.02)))
            car.addChildNode(box(0.07, 0.045, 0.36, hl, P.L + 0.01, P.hf - 0.1, sd * P.w * 0.33))
            car.addChildNode(box(0.05, 0.03, 0.22, hl, P.L, P.gc + 0.1, sd * P.w * 0.36))
            car.addChildNode(box(0.06, 0.07, 0.42, tl, P.R - 0.02, P.br - 0.12, sd * P.w * 0.32))
            let ex = SCNCylinder(radius: 0.05, height: 0.14); ex.materials = [chrome]; let en = SCNNode(geometry: ex); en.eulerAngles.z = .pi / 2; en.position = SCNVector3(P.R - 0.02, P.gc + 0.06, sd * P.w * 0.19); car.addChildNode(en)
        }
        car.addChildNode(box(0.06, (P.hf - P.gc) * 0.32, P.w * 0.46, trim, P.L + 0.03, P.gc + (P.hf - P.gc) * 0.45, 0))
        if !P.vert { car.addChildNode(box(0.04, 0.025, P.w * 0.3, tl, P.R - 0.02, P.br - 0.12, 0)) }
        // ratai
        for (x, sd) in [(P.wb, CGFloat(1)), (P.wb, -1), (-P.wb, 1), (-P.wb, -1)] {
            let wh = SCNNode(); let r = P.wr
            let tire = SCNTube(innerRadius: r * 0.7, outerRadius: r, height: 0.26); tire.materials = [black]; let tn = SCNNode(geometry: tire); tn.eulerAngles.x = .pi / 2; wh.addChildNode(tn)
            let disc = SCNCylinder(radius: r * 0.6, height: 0.02); disc.materials = [dark]; let dn = SCNNode(geometry: disc); dn.eulerAngles.x = .pi / 2; dn.position.z = Float(sd * 0.06); wh.addChildNode(dn)
            wh.addChildNode(box(0.1, 0.16, 0.06, mat(UIColor(red: 0.82, green: 0.13, blue: 0.1, alpha: 1), rough: 0.4), -0.14, 0.12, sd * 0.08))
            let ring = SCNTorus(ringRadius: r * 0.7, pipeRadius: 0.02); ring.materials = [chrome]; let rn = SCNNode(geometry: ring); rn.eulerAngles.x = .pi / 2; rn.position.z = Float(sd * 0.12); wh.addChildNode(rn)
            switch rims {
            case .aero:
                let f = SCNCylinder(radius: r * 0.7, height: 0.03); f.materials = [mat(UIColor(white: 0.55, alpha: 1), metal: 0.9, rough: 0.3)]; let fn = SCNNode(geometry: f); fn.eulerAngles.x = .pi / 2; fn.position.z = Float(sd * 0.12); wh.addChildNode(fn)
            case .sport, .multi:
                let n = rims == .multi ? 10 : 5
                for i in 0..<n { for off in (rims == .sport ? [0.0, 0.16] : [0.0]) {
                    let a = Double(i) * 2 * .pi / Double(n) + off
                    let sp = box(rims == .multi ? 0.025 : 0.045, r * 0.68, 0.03, chrome, CGFloat(cos(a)) * r * 0.35, CGFloat(sin(a)) * r * 0.35, sd * 0.12)
                    sp.eulerAngles.z = Float(a - .pi / 2); wh.addChildNode(sp) } }
            }
            wh.position = SCNVector3(x, r, sd * (P.w / 2 + 0.02)); car.addChildNode(wh)
        }
        if P.gc > 0.4 { car.scale = SCNVector3(0.92, 0.92, 0.92) }
        car.eulerAngles.y = 0.55
        car.runAction(.repeatForever(.sequence([.rotateBy(x: 0, y: 0.45, z: 0, duration: 6), .rotateBy(x: 0, y: -0.45, z: 0, duration: 6)])))
        s.rootNode.addChildNode(car)
        let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera?.fieldOfView = 26; cam.position = SCNVector3(4.2, 1.7, 5.6); cam.look(at: SCNVector3(0, 0.75, 0)); s.rootNode.addChildNode(cam)
        return s
    }
}

struct OwnCar16View: UIViewRepresentable {
    @AppStorage("carColorHex") private var colorHex = "#9AA0A6"
    @AppStorage("carBody") private var bodyType = CarBody.coupe.rawValue
    @AppStorage("carRims") private var rims = RimStyle.sport.rawValue
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(); v.backgroundColor = .clear; v.autoenablesDefaultLighting = true; v.allowsCameraControl = true; v.antialiasingMode = .multisampling4X; return v
    }
    func updateUIView(_ v: SCNView, context: Context) {
        v.scene = OwnCar16.scene(color: UIColor(hex: colorHex), body: CarBody(rawValue: bodyType) ?? .coupe, rims: RimStyle(rawValue: rims) ?? .sport)
    }
}

struct V16Section: View {
    @AppStorage("carBody") private var bodyType = CarBody.coupe.rawValue
    @AppStorage("carRims") private var rims = RimStyle.sport.rawValue
    @AppStorage("f.stops") private var stops = true
    @AppStorage("f.evplan") private var evplan = true
    @AppStorage("ev.range") private var range: Double = 400
    var body: some View {
        Section {
            if Feature.own3d.isOn {
                OwnCar16View().frame(height: 170)
                Picker("Kėbulas", selection: $bodyType) { ForEach(CarBody.allCases) { Text($0.title).tag($0.rawValue) } }
                Picker("Ratlankiai", selection: $rims) { ForEach(RimStyle.allCases) { Text($0.title).tag($0.rawValue) } }.pickerStyle(.segmented)
            }
            Toggle(isOn: $stops) { Label { VStack(alignment: .leading) { Text("Kelionė su sustojimais"); Text("Keli tikslai vienoje kelionėje").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath") } }
            Toggle(isOn: $evplan) { Label { VStack(alignment: .leading) { Text("Elektromobilio planas"); Text("Kur ir kiek krauti ilgoje kelionėje").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "bolt.car") } }
            if evplan { Stepper("Nuvažiuoja pilnai: \(Int(range)) km", value: $range, in: 100...900, step: 10) }
        } header: { Text("v16") }
    }
}

// MARK: - 2. Kelionė su sustojimais
@MainActor
final class MultiStopTrip: ObservableObject {
    @Published var names: [String] = ["", ""]
    @Published private(set) var items: [MKMapItem] = []
    @Published private(set) var index = 0
    @Published private(set) var active = false
    var current: MKMapItem? { active && index < items.count ? items[index] : nil }
    var hasNext: Bool { active && index + 1 < items.count }

    /// Suranda visus adresus. `optimize` – artimiausio kaimyno tvarka (galutinis tikslas lieka paskutinis).
    func prepare(near l: CLLocation?, optimize: Bool) async -> Bool {
        var found: [MKMapItem] = []
        for n in names.map({ $0.trimmingCharacters(in: .whitespaces) }) where !n.isEmpty {
            let r = MKLocalSearch.Request(); r.naturalLanguageQuery = n
            if let l { r.region = MKCoordinateRegion(center: l.coordinate, latitudinalMeters: 200_000, longitudinalMeters: 200_000) }
            if let it = try? await MKLocalSearch(request: r).start().mapItems.first { found.append(it) }
        }
        guard found.count >= 2 else { return false }
        if optimize, found.count > 2, var cur = l {
            var mid = Array(found.dropLast()), out: [MKMapItem] = []
            while !mid.isEmpty {
                let i = mid.indices.min { cur.distance(from: mid[$0].placemark.location!) < cur.distance(from: mid[$1].placemark.location!) }!
                let it = mid.remove(at: i); out.append(it); cur = it.placemark.location!
            }
            found = out + [found.last!]
        }
        items = found; index = 0; active = true; return true
    }
    func setItems(_ list: [MKMapItem]) { items = list; index = 0; active = !list.isEmpty }
    func advance() { if hasNext { index += 1 } else { cancel() } }
    func cancel() { active = false; items = []; index = 0 }
}

struct StopsSheet: View {
    @ObservedObject var trip: MultiStopTrip
    let onGo: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(trip.names.indices, id: \.self) { i in
                    HStack {
                        Image(systemName: i == trip.names.count - 1 ? "flag.fill" : "\(i + 1).circle.fill").foregroundStyle(i == trip.names.count - 1 ? .red : .blue)
                        TextField(i == trip.names.count - 1 ? "Galutinis tikslas" : "Sustojimas \(i + 1)", text: $trip.names[i])
                    }
                }
                .onMove { trip.names.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { trip.names.remove(atOffsets: $0); if trip.names.isEmpty { trip.names = [""] } }
                Button("+ Pridėti sustojimą") { if trip.names.count < 9 { trip.names.insert("", at: max(0, trip.names.count - 1)) } }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Kelionė su sustojimais")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Uždaryti") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Menu("Vesti") { Button("Vesti šia tvarka") { dismiss(); onGo(false) }; Button("Optimizuoti tvarką") { dismiss(); onGo(true) } } }
            }
        }
    }
}

// MARK: - 3. Elektromobilio kelionės planas
struct EVStop: Identifiable { let id = UUID(); let item: MKMapItem; let km: Int; let arrivePct: Int; let minutes: Int }
struct EVPlan { let km: Int; let stops: [EVStop]; let arrivePct: Int; let destination: MKMapItem }

enum EVPlanner {
    /// Skaičiuoja: sąnaudos ~0,18 kWh/km, rezervas 10 %, kraunama iki `chargeTo`, vid. galia 110 kW.
    static func plan(to dest: MKMapItem, from l: CLLocation, battery: Double, range: Double, chargeTo: Double) async -> EVPlan? {
        let req = MKDirections.Request(); req.source = MKMapItem(placemark: MKPlacemark(coordinate: l.coordinate)); req.destination = dest; req.transportType = .automobile
        guard let route = try? await MKDirections(request: req).calculate().routes.first else { return nil }
        let total = route.distance / 1000, cap = range * 0.18
        var pos = 0.0, pct = battery, stops: [EVStop] = []
        while stops.count < 8 {
            let reach = (pct - 10) / 100 * range
            if pos + reach >= total { break }
            let at = pos + reach * 0.92
            let arrive = pct - (at - pos) / range * 100
            guard let c = coordinate(on: route.polyline, atKm: at), let charger = await nearestCharger(c) else { break }
            stops.append(EVStop(item: charger, km: Int(at), arrivePct: Int(arrive), minutes: Int((chargeTo - arrive) / 100 * cap / 110 * 60 * 1.15)))
            pos = at; pct = chargeTo
        }
        return EVPlan(km: Int(total), stops: stops, arrivePct: Int(pct - (total - pos) / range * 100), destination: dest)
    }
    static func coordinate(on line: MKPolyline, atKm km: Double) -> CLLocationCoordinate2D? {
        let pts = line.points(); var acc = 0.0
        for i in 1..<line.pointCount {
            let d = pts[i - 1].distance(to: pts[i]) / 1000
            if acc + d >= km { return pts[i].coordinate }
            acc += d
        }
        return nil
    }
    static func nearestCharger(_ c: CLLocationCoordinate2D) async -> MKMapItem? {
        let r = MKLocalPointsOfInterestRequest(center: c, radius: 8000); r.pointOfInterestFilter = MKPointOfInterestFilter(including: [.evCharger])
        let items = (try? await MKLocalSearch(request: r).start().mapItems) ?? []
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return items.min { $0.placemark.location!.distance(from: here) < $1.placemark.location!.distance(from: here) }
    }
}

struct EVPlanSheet: View {
    let location: CLLocation?
    let onGo: ([MKMapItem]) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ev.range") private var range: Double = 400
    @AppStorage("ev.chargeTo") private var chargeTo: Double = 80
    @State private var battery: Double = 80
    @State private var dest = ""
    @State private var plan: EVPlan?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Kur važiuoji? pvz. Ryga", text: $dest)
                    Stepper("Baterija dabar: \(Int(battery)) %", value: $battery, in: 5...100, step: 5)
                    Stepper("Nuvažiuoja pilnai: \(Int(range)) km", value: $range, in: 100...900, step: 10)
                    Stepper("Krauti iki: \(Int(chargeTo)) %", value: $chargeTo, in: 50...100, step: 5)
                    Button(busy ? "Skaičiuojama…" : "Suplanuoti") { Task { await calc() } }.disabled(busy || dest.isEmpty)
                }
                if let plan {
                    Section("\(plan.km) km · \(plan.stops.count) įkrovimas(-ai) · ~\(plan.stops.reduce(0) { $0 + $1.minutes }) min") {
                        Label("Išvykimas · \(Int(battery)) %", systemImage: "circle.fill").foregroundStyle(.green)
                        ForEach(plan.stops) { s in
                            Label("\(s.item.name ?? "Įkrovimo stotelė") · \(s.km) km · atvyksi su \(s.arrivePct) % · krauti ~\(s.minutes) min", systemImage: "bolt.fill")
                        }
                        Label("\(plan.destination.name ?? dest) · atvyksi su \(plan.arrivePct) %", systemImage: "flag.fill").foregroundStyle(.red)
                        Button("Vesti su sustojimais") { dismiss(); onGo(plan.stops.map(\.item) + [plan.destination]) }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Kelionė elektromobiliu")
            .toolbar { Button("Uždaryti") { dismiss() } }
        }
    }
    private func calc() async {
        guard let l = location else { return }
        busy = true; defer { busy = false }
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = dest
        guard let d = try? await MKLocalSearch(request: r).start().mapItems.first else { return }
        plan = await EVPlanner.plan(to: d, from: l, battery: battery, range: range, chargeTo: chargeTo)
    }
}
