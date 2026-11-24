import CarPlay
import MapKit
import SwiftUI

/// v11: CarPlay versija (navigacijos programėlė).
/// Apple leidžia CarPlay rodyti tik savo šablonus: žemėlapį (piešia programėlė), mygtukus, sąrašus.
/// Video CarPlay ekrane nerodomas. Muzika automobilio ekrane rodoma per Spotify / Apple Music jų pačių CarPlay programas.
/// Kad tai veiktų, reikia: mokamos Apple Developer paskyros (99 $/m.) ir Apple patvirtinto leidimo
/// „com.apple.developer.carplay-maps“ (prašoma developer.apple.com/carplay). Be jo CarPlay ekranas nepasirodys.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPMapTemplateDelegate {
    private var interfaceController: CPInterfaceController?
    private var window: CPWindow?
    private let mapTemplate = CPMapTemplate()
    private let loc = LocationManager()

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect ic: CPInterfaceController, to window: CPWindow) {
        interfaceController = ic; self.window = window
        guard Feature.on("f.carplay") else {
            let t = CPInformationTemplate(title: "CarVideo", layout: .leading, items: [CPInformationItem(title: "CarPlay išjungtas", detail: "Įjunk: CarVideo → Nustatymai → CarPlay versija")], actions: [])
            ic.setRootTemplate(t, animated: false, completion: nil); return
        }
        // Žemėlapis su greičiu – mūsų SwiftUI vaizdas automobilio ekrane
        window.rootViewController = UIHostingController(rootView: CarPlayMapView(loc: loc))
        mapTemplate.mapDelegate = self
        let home = CPBarButton(title: "Namo") { [weak self] _ in self?.goHome() }
        let report = CPBarButton(title: "Pranešti") { [weak self] _ in self?.showReport() }
        mapTemplate.leadingNavigationBarButtons = [home]
        mapTemplate.trailingNavigationBarButtons = Feature.on("f.alerts") ? [report] : []
        ic.setRootTemplate(mapTemplate, animated: false, completion: nil)
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnect ic: CPInterfaceController, from window: CPWindow) {
        interfaceController = nil; self.window = nil
    }

    private func goHome() {
        let addr = UserDefaults.standard.string(forKey: "homeAddress") ?? ""
        guard !addr.isEmpty else { return }
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = addr
        MKLocalSearch(request: r).start { [weak self] res, _ in
            guard let self, let dest = res?.mapItems.first else { return }
            let trip = CPTrip(origin: MKMapItem.forCurrentLocation(), destination: dest, routeChoices: [CPRouteChoice(summaryVariants: ["Greičiausias"], additionalInformationVariants: [], selectionSummaryVariants: [])])
            self.mapTemplate.showTripPreviews([trip], textConfiguration: nil)
        }
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, startedTrip trip: CPTrip, using routeChoice: CPRouteChoice) {
        mapTemplate.hideTripPreviews()
        _ = mapTemplate.startNavigationSession(for: trip)   // posūkiai rodomi CarPlay kortelėje
    }

    private func showReport() {
        let items = AlertKind.allCases.map { k in
            CPGridButton(titleVariants: [k.title], image: UIImage(systemName: k.symbol)!) { [weak self] _ in
                if let c = self?.loc.location?.coordinate { Task { @MainActor in RoadAlertShared.service.report(k, at: c) } }
                self?.interfaceController?.popTemplate(animated: true, completion: nil)
            }
        }
        interfaceController?.pushTemplate(CPGridTemplate(title: "Pranešti kitiems", gridButtons: items), animated: true, completion: nil)
    }
}

/// Bendras pranešimų servisas programėlei ir CarPlay ekranui.
@MainActor enum RoadAlertShared { static let service = RoadAlertService() }

struct CarPlayMapView: View {
    @ObservedObject var loc: LocationManager
    @ObservedObject private var alerts = RoadAlertShared.service
    @AppStorage("carMake") private var carMake = "BMW"
    @AppStorage("gaugeStyle") private var gaugeStyleRaw = "auto"
    @AppStorage("speedLimitKmh") private var limit: Double = 300
    @State private var cam: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    var body: some View {
        Map(position: $cam) {
            UserAnnotation()
            ForEach(alerts.alerts) { a in Annotation(a.kind.title, coordinate: a.coordinate) { Image(systemName: a.kind.symbol).foregroundStyle(.white).padding(6).background(a.kind.color, in: Circle()) } }
        }
        .overlay(alignment: .bottomLeading) {
            BrandGauge(style: GaugeStyle(rawValue: gaugeStyleRaw) ?? .forMake(carMake), speed: Double(Units.speed(loc.speedKmh)), limit: Double(Units.speed(limit)))
                .frame(width: 96, height: 96).padding(10)
        }
        .onChange(of: loc.location) { _, l in if let l { alerts.update(with: l) } }
    }
}
