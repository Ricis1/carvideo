import SwiftUI

/// v6: spidometrai pagal automobilio markės stilių.
/// Dizainai originalūs (be logotipų), tik įkvėpti markių prietaisų skydelių.
enum GaugeStyle: String, CaseIterable, Identifiable {
    case blue, red, silver, teal, minimal, classic, orange, layered
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blue: "Mėlynas sportinis"
        case .red: "Raudona adata"
        case .silver: "Sidabrinis prabangus"
        case .teal: "Žalsva juosta"
        case .minimal: "Minimalus"
        case .classic: "Klasikinis analoginis"
        case .orange: "Oranžiniai segmentai"
        case .layered: "3D sluoksniai"
        }
    }

    /// Markė → stilius (tik markės, turinčios CarPlay arba Android Auto).
    static func forMake(_ make: String) -> GaugeStyle {
        switch make.lowercased().trimmingCharacters(in: .whitespaces) {
        case "bmw", "mini": .blue
        case "audi", "alfa romeo", "porsche", "ferrari", "lamborghini", "maserati", "abarth": .red
        case "mercedes-benz", "mercedes", "lexus", "genesis", "bentley", "aston martin", "infiniti", "lincoln", "cadillac", "rolls-royce": .silver
        case "volvo", "polestar", "land rover", "jaguar", "smart": .minimal
        case "toyota", "mazda", "honda", "subaru", "nissan", "mitsubishi", "suzuki", "acura", "isuzu": .classic
        case "ford", "chevrolet", "jeep", "dodge", "ram", "gmc", "buick", "chrysler": .orange
        case "peugeot", "citroën", "citroen", "ds", "opel", "vauxhall", "renault", "dacia", "fiat", "alpine": .layered
        default: .teal
        }
    }
}

struct BrandGauge: View {
    let style: GaugeStyle
    let speed: Double
    let limit: Double
    var maxSpeed: Double = 260

    private var frac: Double { min(1, max(0, speed / maxSpeed)) }
    private var over: Bool { speed > limit }
    private let sweep = 0.75   // 270°
    private var numColor: Color { over ? .red : .white }

    var body: some View {
        ZStack {
            face
            content
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Greitis \(Int(speed)) km/h")
    }

    // Lankas nuo -135° iki +135° (pradžia apačioje kairėje).
    private func arc(_ to: Double) -> some Shape {
        Circle().trim(from: 0, to: sweep * to).rotation(.degrees(135))
    }

    @ViewBuilder private var face: some View {
        switch style {
        case .classic: Circle().fill(Color(red: 0.95, green: 0.94, blue: 0.92)).overlay(Circle().stroke(.black, lineWidth: 3))
        case .silver: Circle().fill(LinearGradient(colors: [.white, .gray, .white], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().inset(by: 6).fill(Color(red: 0.04, green: 0.08, blue: 0.13)))
        case .orange: RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.07))
        case .layered: Circle().fill(Color(red: 0.05, green: 0.04, blue: 0.1))
        default: Circle().fill(Color(white: 0.05))
        }
    }

    @ViewBuilder private var content: some View {
        GeometryReader { g in
            let s = g.size.width
            ZStack {
                switch style {
                case .blue, .teal, .layered:
                    let w = style == .teal ? s * 0.1 : s * 0.06
                    let grad: AnyShapeStyle = style == .blue
                        ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.11, green: 0.41, blue: 0.83), Color(red: 0.49, green: 0.75, blue: 1)], startPoint: .leading, endPoint: .trailing))
                        : style == .teal ? AnyShapeStyle(Color(red: 0.09, green: 0.78, blue: 0.71))
                        : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.48, green: 0.36, blue: 1), Color(red: 0, green: 0.88, blue: 0.78)], startPoint: .leading, endPoint: .trailing))
                    arc(1).stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: w, lineCap: .round)).padding(s * 0.12)
                    arc(frac).stroke(grad, style: StrokeStyle(lineWidth: w, lineCap: .round)).padding(s * 0.12)
                        .shadow(color: style == .layered ? .cyan : .clear, radius: 4)
                    number(s * 0.26)
                case .red, .silver, .classic:
                    ticks(s, color: style == .classic ? .black : (style == .silver ? .cyan : .white))
                    Capsule().fill(style == .silver ? Color.white : Color.red)
                        .frame(width: s * 0.03, height: s * 0.38)
                        .offset(y: -s * 0.19)
                        .rotationEffect(.degrees(-135 + 270 * frac))
                    Circle().fill(Color(white: 0.1)).frame(width: s * 0.1)
                    Text("\(Int(speed))").font(.system(size: s * 0.13, weight: .heavy, design: .rounded))
                        .foregroundStyle(style == .classic ? (over ? .red : .black) : numColor)
                        .offset(y: s * 0.28)
                case .minimal:
                    arc(1).stroke(Color.white.opacity(0.2), lineWidth: 1.5).padding(s * 0.08)
                    Circle().fill(Color.blue).frame(width: s * 0.08)
                        .offset(y: -s * 0.42).rotationEffect(.degrees(-135 + 270 * frac))
                    number(s * 0.3, weight: .light)
                case .orange:
                    ForEach(0..<24, id: \.self) { i in
                        let on = Double(i) / 23 <= frac && speed > 0
                        Capsule().fill(on ? (i > 18 ? Color.red : Color.orange) : Color(white: 0.2))
                            .frame(width: s * 0.04, height: s * 0.09)
                            .offset(y: -s * 0.38)
                            .rotationEffect(.degrees(-135 + 270 * Double(i) / 23))
                    }
                    number(s * 0.26)
                }
            }
            .frame(width: s, height: s)
        }
    }

    private func number(_ size: CGFloat, weight: Font.Weight = .heavy) -> some View {
        VStack(spacing: -2) {
            Text("\(Int(speed))").font(.system(size: size, weight: weight, design: .rounded)).foregroundStyle(numColor)
            Text("km/h").font(.system(size: size * 0.3)).foregroundStyle(.gray)
        }
    }

    private func ticks(_ s: CGFloat, color: Color) -> some View {
        ForEach(0..<14, id: \.self) { i in
            Rectangle().fill(color).frame(width: 1.5, height: s * 0.06)
                .offset(y: -s * 0.43)
                .rotationEffect(.degrees(-135 + 270 * Double(i) / 13))
        }
    }
}
