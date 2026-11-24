// v13: eismo juostos, ramus naktinis ekranas, parkavimo nuotrauka, poilsio priminimas, garsumas pagal greitį.
// Kiekvieną funkciją galima išjungti: Nustatymai → v13.
import SwiftUI
import MapKit
import PhotosUI
import MediaPlayer
import AVFoundation

enum V13 {
    static func on(_ k: String) -> Bool { UserDefaults.standard.object(forKey: "f." + k) as? Bool ?? true }
}

// MARK: - Nustatymai
struct V13Section: View {
    @AppStorage("f.lanes") private var lanes = true
    @AppStorage("f.calm") private var calm = true
    @AppStorage("calmAuto") private var calmAuto = true
    @AppStorage("f.parkphoto") private var parkPhoto = true
    @AppStorage("f.breakrem") private var breakRem = true
    @AppStorage("breakHours") private var breakHours: Double = 2
    @AppStorage("f.speedvol") private var speedVol = true
    @AppStorage("volBase") private var volBase: Double = 0.5
    var body: some View {
        Section {
            Toggle(isOn: $lanes) { Label { VStack(alignment: .leading) { Text("Eismo juostos"); Text("Rodo, į kurią juostą persirikiuoti prieš posūkį").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "arrow.up.right.and.arrow.down.left") } }
            Toggle(isOn: $calm) { Label { VStack(alignment: .leading) { Text("Ramus naktinis ekranas"); Text("Juodas ekranas: laikas, greitis, posūkis ir daina").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "moon") } }
            if calm { Toggle("Įjungti automatiškai naktį po 1 min be lietimo", isOn: $calmAuto) }
            Toggle(isOn: $parkPhoto) { Label { VStack(alignment: .leading) { Text("Parkavimo nuotrauka"); Text("Nuotrauka, aukštas ir pastaba").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "camera") } }
            Toggle(isOn: $breakRem) { Label { VStack(alignment: .leading) { Text("Poilsio priminimas"); Text("Primena pailsėti po ilgo vairavimo").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "cup.and.saucer") } }
            if breakRem {
                Picker("Priminti kas", selection: $breakHours) { Text("1,5 val.").tag(1.5); Text("2 val.").tag(2.0); Text("3 val.").tag(3.0) }.pickerStyle(.segmented)
            }
            Toggle(isOn: $speedVol) { Label { VStack(alignment: .leading) { Text("Garsumas pagal greitį"); Text("Važiuojant greičiau garsas šiek tiek padidėja").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "speaker.wave.2") } }
            if speedVol {
                Picker("Bazinis garsas", selection: $volBase) { Text("Tyliau").tag(0.35); Text("Vidutiniškai").tag(0.5); Text("Garsiau").tag(0.65) }.pickerStyle(.segmented)
            }
        } header: { Text("v13") }
    }
}

// MARK: - 1. Eismo juostos (OpenStreetMap turn:lanes, veikia visame pasaulyje)
struct LaneInfo: Equatable { let lanes: [[String]]   // pvz. [["left"],["through"],["through","right"]]
}

@MainActor
final class LaneService: ObservableObject {
    @Published private(set) var info: LaneInfo?
    private var lastKey = ""
    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    /// Kviesti, kai pasikeičia navigacijos žingsnis. Ieško kelio su turn:lanes prieš posūkį.
    func update(step: MKRoute.Step?) {
        guard V13.on("lanes"), let step, step.polyline.pointCount > 0 else { info = nil; return }
        let c = step.polyline.points()[0].coordinate
        let key = String(format: "%.4f,%.4f", c.latitude, c.longitude)
        guard key != lastKey else { return }
        lastKey = key
        Task { info = await fetch(near: c) }
    }

    private func fetch(near c: CLLocationCoordinate2D) async -> LaneInfo? {
        let q = "[out:json][timeout:8];way(around:40,\(c.latitude),\(c.longitude))[\"turn:lanes\"];out tags 1;"
        var req = URLRequest(url: endpoint); req.httpMethod = "POST"
        req.httpBody = ("data=" + (q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")).data(using: .utf8)
        guard let (d, _) = try? await URLSession.shared.data(for: req),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let els = j["elements"] as? [[String: Any]],
              let tags = els.first?["tags"] as? [String: String],
              let raw = tags["turn:lanes"] ?? tags["turn:lanes:forward"] else { return nil }
        let lanes = raw.split(separator: "|", omittingEmptySubsequences: false).map { $0.split(separator: ";").map(String.init).map { $0.isEmpty || $0 == "none" ? "through" : $0 } }
        return lanes.count >= 2 ? LaneInfo(lanes: lanes) : nil
    }
}

struct LaneStrip: View {
    let info: LaneInfo
    let instructions: String
    private var wantRight: Bool { let s = instructions.lowercased(); return s.contains("right") || s.contains("dešin") || s.contains("rechts") || s.contains("droite") || s.contains("prawo") || s.contains("derecha") }
    private func good(_ l: [String]) -> Bool { l.contains { wantRight ? $0.contains("right") : $0.contains("left") } }
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(info.lanes.enumerated()), id: \.offset) { _, l in
                Image(systemName: icon(l)).font(.title3.bold()).frame(width: 34, height: 36)
                    .background(good(l) ? Color.white.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .opacity(good(l) ? 1 : 0.35)
            }
        }
        .padding(6).background(Color(red: 0.05, green: 0.35, blue: 0.16), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(wantRight ? "Rikiuokis į dešinę juostą" : "Rikiuokis į kairę juostą")
    }
    private func icon(_ l: [String]) -> String {
        if l.contains(where: { $0.contains("left") }) { return "arrow.turn.up.left" }
        if l.contains(where: { $0.contains("right") }) { return "arrow.turn.up.right" }
        return "arrow.up"
    }
}

// MARK: - 2. Ramus naktinis ekranas
struct CalmScreen: View {
    let speedKmh: Double
    let turn: String?
    let mph: Bool
    let onClose: () -> Void
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(spacing: 8) {
                Text(ctx.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 110, weight: .ultraLight)).foregroundStyle(Color(white: 0.8))
                Text("\(Int((mph ? speedKmh / 1.609 : speedKmh).rounded())) \(mph ? "mph" : "km/h")").font(.system(size: 40, weight: .light)).foregroundStyle(Color(white: 0.9))
                if let turn { Text(turn).font(.title2).foregroundStyle(.green) }
                Text("Paliesk bet kur, kad grįžtum").font(.caption).foregroundStyle(Color(white: 0.35)).padding(.top, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
            .contentShape(Rectangle()).onTapGesture(perform: onClose)
        }
        .ignoresSafeArea()
        .onAppear { UIScreen.main.brightness = max(0.05, UIScreen.main.brightness * 0.4) }
    }
}

// MARK: - 3. Parkavimo nuotrauka, aukštas, pastaba
enum ParkingExtras {
    private static var photoURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("parking.jpg") }
    static var floor: String { get { UserDefaults.standard.string(forKey: "park.floor") ?? "" } set { UserDefaults.standard.set(newValue, forKey: "park.floor") } }
    static var note: String { get { UserDefaults.standard.string(forKey: "park.note") ?? "" } set { UserDefaults.standard.set(newValue, forKey: "park.note") } }
    static func photo() -> UIImage? { UIImage(contentsOfFile: photoURL.path) }
    static func save(_ img: UIImage?) {
        guard let img else { try? FileManager.default.removeItem(at: photoURL); return }
        let s = min(1, 1200 / max(img.size.width, img.size.height))
        let r = UIGraphicsImageRenderer(size: CGSize(width: img.size.width * s, height: img.size.height * s))
        let small = r.image { _ in img.draw(in: CGRect(origin: .zero, size: r.format.bounds.size)) }
        try? small.jpegData(compressionQuality: 0.75)?.write(to: photoURL)
    }
    static func clear() { save(nil); floor = ""; note = "" }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController(); p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary; p.delegate = context.coordinator; return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(onImage) }
    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let cb: (UIImage) -> Void; init(_ cb: @escaping (UIImage) -> Void) { self.cb = cb }
        func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { if let i = info[.originalImage] as? UIImage { cb(i) }; p.dismiss(animated: true) }
        func imagePickerControllerDidCancel(_ p: UIImagePickerController) { p.dismiss(animated: true) }
    }
}

struct ParkingDetailSheet: View {
    let place: String
    let onShowMap: () -> Void
    let onForget: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var img = ParkingExtras.photo()
    @State private var floor = ParkingExtras.floor
    @State private var note = ParkingExtras.note
    @State private var showCam = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showCam = true } label: {
                        if let img { Image(uiImage: img).resizable().scaledToFill().frame(height: 180).clipped().clipShape(RoundedRectangle(cornerRadius: 12)) }
                        else { Label("Nufotografuoti vietą", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 120) }
                    }
                }
                Section {
                    TextField("Aukštas", text: $floor).onChange(of: floor) { _, v in ParkingExtras.floor = v }
                    TextField("Pastaba, pvz. B eilė prie lifto", text: $note).onChange(of: note) { _, v in ParkingExtras.note = v }
                }
                Section {
                    Button("Rodyti žemėlapyje") { dismiss(); onShowMap() }
                    Button("Pamiršti vietą", role: .destructive) { ParkingExtras.clear(); dismiss(); onForget() }
                }
            }
            .navigationTitle(place.isEmpty ? "Kur palikai automobilį" : place)
            .toolbar { Button("Gerai") { dismiss() } }
            .fullScreenCover(isPresented: $showCam) { CameraPicker { i in ParkingExtras.save(i); img = ParkingExtras.photo() }.ignoresSafeArea() }
        }
    }
}

// MARK: - 4. Poilsio priminimas
@MainActor
final class BreakReminder: ObservableObject {
    @Published var due = false
    private var driving: TimeInterval = 0
    private var last: Date?
    private var snooze: TimeInterval = 0
    var drivenText: String { let m = Int(driving / 60); return m >= 60 ? "\(m / 60) val. \(m % 60) min" : "\(m) min" }

    func update(speedKmh: Double, voice: (String) -> Void) {
        let now = Date(); defer { last = now }
        guard let last else { return }
        let dt = min(10, now.timeIntervalSince(last))
        if speedKmh > 5 { driving += dt } else { driving = max(0, driving - dt * 2) }   // ilgesnis sustojimas = pailsėjai
        let limit = (UserDefaults.standard.object(forKey: "breakHours") as? Double ?? 2) * 3600
        if V13.on("breakrem"), !due, driving >= limit + snooze { due = true; voice("Vairuoji jau ilgai. Siūlau trumpą pertrauką.") }
    }
    func later() { due = false; snooze = driving - (UserDefaults.standard.object(forKey: "breakHours") as? Double ?? 2) * 3600 + 1800 }
    func rested() { due = false; driving = 0; snooze = 0 }
}

struct BreakSheet: View {
    let driven: String
    let onFind: () -> Void
    let onLater: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 48)).foregroundStyle(.yellow)
            Text("Vairuoji jau \(driven). Laikas pailsėti").font(.title2.bold()).multilineTextAlignment(.center)
            Text("15 min pertrauka kas 2 valandas – geriausia apsauga nuo nuovargio.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack { Button("Rasti poilsio vietą", action: onFind).buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                Button("Priminti po 30 min", action: onLater).buttonStyle(.bordered) }
        }
        .padding(24).presentationDetents([.medium])
    }
}

// MARK: - 5. Garsumas pagal greitį
/// iOS neleidžia tiesiogiai keisti sistemos garso; naudojamas MPVolumeView slankiklis (veikia, bet Apple tai gali patikrinti peržiūroje).
@MainActor
enum SpeedVolume {
    private static let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
    private static var lastSet: Float = -1
    static func attach() {
        guard view.superview == nil, let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        w.addSubview(view)
    }
    static func apply(speedKmh: Double) {
        guard V13.on("speedvol") else { return }
        attach()
        let base = UserDefaults.standard.object(forKey: "volBase") as? Double ?? 0.5
        let v = Float(min(1, base + max(0, speedKmh - 30) * 0.002))
        guard abs(v - lastSet) >= 0.03, let s = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        lastSet = v; s.value = v
    }
}
