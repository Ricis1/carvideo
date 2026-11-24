import UIKit
import MapKit

/// v7: navigacijos programos pasirinkimas.
/// Waze ir Google Maps neleidžia įterpti savo navigacijos į kitas programėles
/// (Waze neturi iOS SDK, Google Navigation SDK skirtas tik verslo partneriams),
/// todėl tikslas perduodamas jiems per nuorodą ir jų programėlė atsidaro.
enum NavProvider: String, CaseIterable, Identifiable {
    case apple, waze, google
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apple: "Apple (programėlėje)"
        case .waze: "Waze"
        case .google: "Google Maps"
        }
    }
}

enum ExternalNav {
    /// Atidaro Waze arba Google Maps su maršrutu. Jei programėlės nėra, atidaroma jų svetainė / App Store nuoroda.
    @MainActor
    static func open(_ p: NavProvider, query: String, coordinate: CLLocationCoordinate2D? = nil) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let app: URL?
        let web: URL?
        switch p {
        case .apple:
            return
        case .waze:
            if let c = coordinate {
                app = URL(string: "waze://?ll=\(c.latitude),\(c.longitude)&navigate=yes")
                web = URL(string: "https://waze.com/ul?ll=\(c.latitude),\(c.longitude)&navigate=yes")
            } else {
                app = URL(string: "waze://?q=\(q)&navigate=yes")
                web = URL(string: "https://waze.com/ul?q=\(q)&navigate=yes")
            }
        case .google:
            let dest = coordinate.map { "\($0.latitude),\($0.longitude)" } ?? q
            app = URL(string: "comgooglemaps://?daddr=\(dest)&directionsmode=driving")
            web = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(dest)&travelmode=driving")
        }
        if let app, UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else if let web {
            UIApplication.shared.open(web)   // universali nuoroda: atidaro programėlę arba svetainę
        }
    }
}
