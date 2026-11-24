import Foundation
import MapKit
import AVFoundation

/// Maršrutas app'o viduje (Apple Maps duomenys): paieška, maršrutas,
/// einamasis posūkis, perskaičiavimas nuklydus ir balso nurodymai.
@MainActor
final class RouteManager: ObservableObject {
    @Published private(set) var route: MKRoute?
    @Published private(set) var destinationItem: MKMapItem?
    @Published private(set) var currentStep: MKRoute.Step?
    @Published private(set) var distanceToStep: CLLocationDistance = 0
    @Published private(set) var remainingDistance: CLLocationDistance = 0
    @Published private(set) var remainingTime: TimeInterval = 0
    @Published private(set) var isCalculating = false
    @Published var errorText: String?
    @Published var voiceOn = true
    /// Greitesnis kelias dėl kamščių: pasiūlymas vairuotojui.
    @Published private(set) var fasterRoute: MKRoute?
    @Published private(set) var fasterSaving: TimeInterval = 0
    private var lastTrafficCheck = Date()
    private var declinedUntil = Date.distantPast

    private var steps: [MKRoute.Step] = []
    private var stepIndex = 0
    private var announcedNear = false
    private var lastReroute = Date.distantPast
    private let speech = AVSpeechSynthesizer()

    var isNavigating: Bool { route != nil }

    // MARK: Planavimas

    func start(to query: String, from location: CLLocation?) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isCalculating = true
        errorText = nil
        defer { isCalculating = false }
        do {
            let search = MKLocalSearch.Request()
            search.naturalLanguageQuery = q
            if let location {
                search.region = MKCoordinateRegion(center: location.coordinate,
                                                   latitudinalMeters: 200_000, longitudinalMeters: 200_000)
            }
            guard let item = try await MKLocalSearch(request: search).start().mapItems.first else {
                errorText = "Vieta nerasta"
                return
            }
            destinationItem = item
            try await calculate(from: location)
            speak(currentStep?.instructions)
        } catch {
            errorText = "Nepavyko rasti maršruto"
        }
    }

    /// Maršrutas į konkrečią vietą (pvz. degalinę iš sąrašo).
    func start(to item: MKMapItem, from location: CLLocation?) async {
        isCalculating = true
        errorText = nil
        defer { isCalculating = false }
        destinationItem = item
        do {
            try await calculate(from: location)
            speak(currentStep?.instructions)
        } catch {
            errorText = "Nepavyko rasti maršruto"
        }
    }

    private func calculate(from location: CLLocation?) async throws {
        guard let destinationItem else { return }
        let req = MKDirections.Request()
        if let location {
            req.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        } else {
            req.source = .forCurrentLocation()
        }
        req.destination = destinationItem
        req.transportType = .automobile
        req.departureDate = Date()   // laikas su dabartiniais kamščiais
        RouteOptions17.apply(to: req)   // v17: vaizdingas / be mokamų kelių / be vinječių
        let response = try await MKDirections(request: req).calculate()
        guard let r = RouteOptions17.pick(response.routes) else { throw URLError(.cannotFindHost) }
        apply(r)
    }

    private func apply(_ r: MKRoute) {
        route = r
        fasterRoute = nil
        lastTrafficCheck = Date()
        steps = r.steps.filter { !$0.instructions.isEmpty }
        stepIndex = 0
        announcedNear = false
        currentStep = steps.first
        remainingDistance = r.distance
        remainingTime = r.expectedTravelTime
    }

    func stop() {
        fasterRoute = nil
        route = nil
        destinationItem = nil
        currentStep = nil
        steps = []
        speech.stopSpeaking(at: .immediate)
    }

    // MARK: Sekimas

    func update(with location: CLLocation) {
        guard let route, stepIndex < steps.count else { return }
        let here = MKMapPoint(location.coordinate)

        // Nuklydus daugiau nei 80 m nuo maršruto – perskaičiuojam (ne dažniau nei kas 15 s).
        if distance(from: here, to: route.polyline) > 80, Date().timeIntervalSince(lastReroute) > 15 {
            lastReroute = Date()
            Task { try? await calculate(from: location); speak(currentStep?.instructions) }
            return
        }

        let step = steps[stepIndex]
        let end = endPoint(of: step)
        let d = here.distance(to: end)
        distanceToStep = d

        // Likęs atstumas: iki šio žingsnio pabaigos + likę žingsniai.
        let rest = steps.dropFirst(stepIndex + 1).reduce(0) { $0 + $1.distance }
        remainingDistance = d + rest
        if route.distance > 0 {
            remainingTime = route.expectedTravelTime * remainingDistance / route.distance
        }

        // Kas 2 min patikrinam kamščius ir alternatyvius kelius.
        if Date().timeIntervalSince(lastTrafficCheck) > 120, fasterRoute == nil, Date() > declinedUntil {
            lastTrafficCheck = Date()
            Task { await checkFaster(from: location) }
        }

        if d < 200, !announcedNear, step.distance > 400 {
            announcedNear = true
            speak("Po \(Int(d / 10) * 10) metrų, \(step.instructions)")
        }
        if d < 25 {
            stepIndex += 1
            announcedNear = false
            if stepIndex < steps.count {
                currentStep = steps[stepIndex]
                speak(steps[stepIndex].instructions)
            } else {
                speak("Atvykote")
                currentStep = nil
                self.route = nil
            }
        }
    }

    // MARK: Kamščiai

    private func checkFaster(from location: CLLocation) async {
        guard let destinationItem, remainingTime > 300 else { return }
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        req.destination = destinationItem
        req.transportType = .automobile
        req.requestsAlternateRoutes = true
        req.departureDate = Date()
        RouteOptions17.apply(to: req)   // v17: greitesnis kelias irgi laikosi pasirinkimų
        guard !RouteOptions17.scenic else { return }   // vaizdingame maršrute greitesnio nesiūlom
        guard let res = try? await MKDirections(request: req).calculate(),
              let best = res.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else { return }
        let saving = remainingTime - best.expectedTravelTime
        guard saving >= 180, route != nil else { return }   // siūlom tik jei sutaupoma ≥ 3 min
        fasterRoute = best
        fasterSaving = saving
        speak("Kamštis priekyje. Rastas greitesnis kelias, sutaupysite apie \(Int(saving / 60)) minutes.")
    }

    func acceptFaster() {
        guard let r = fasterRoute else { return }
        apply(r)
        speak("Važiuojame greitesniu keliu. " + (currentStep?.instructions ?? ""))
    }

    func declineFaster() {
        fasterRoute = nil
        declinedUntil = Date().addingTimeInterval(600)
    }

    // MARK: Pagalbinės

    private func endPoint(of step: MKRoute.Step) -> MKMapPoint {
        let n = step.polyline.pointCount
        return n > 0 ? step.polyline.points()[n - 1] : MKMapPoint(step.polyline.coordinate)
    }

    /// Mažiausias atstumas (metrais) nuo taško iki linijos.
    private func distance(from p: MKMapPoint, to line: MKPolyline) -> CLLocationDistance {
        let pts = line.points()
        let n = line.pointCount
        guard n > 1 else { return n == 1 ? p.distance(to: pts[0]) : .infinity }
        var best = CLLocationDistance.infinity
        for i in 0..<(n - 1) {
            let a = pts[i], b = pts[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            var t = len2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2 : 0
            t = max(0, min(1, t))
            let proj = MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
            best = min(best, p.distance(to: proj))
        }
        return best
    }

    /// v13: kiti moduliai (poilsio priminimas) gali ištarti tekstą tuo pačiu balsu.
    func speakText(_ text: String) { speak(text) }

    private func speak(_ text: String?) {
        guard voiceOn, let text, !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first) ?? AVSpeechSynthesisVoice(language: "en-US")
        speech.speak(u)
    }
}

/// Posūkio ikona pagal nurodymo tekstą (lietuvių arba anglų kalba).
func maneuverIcon(for instructions: String) -> String {
    let s = instructions.lowercased()
    if s.contains("žied") || s.contains("roundabout") { return "arrow.triangle.turn.up.right.circle" }
    if s.contains("kair") || s.contains("left") { return "arrow.turn.up.left" }
    if s.contains("dešin") || s.contains("right") { return "arrow.turn.up.right" }
    if s.contains("atvyk") || s.contains("arrive") || s.contains("destination") { return "flag.checkered" }
    return "arrow.up"
}

func formatDistance(_ m: CLLocationDistance) -> String {
    m >= 1000 ? String(format: "%.1f km", m / 1000) : "\(Int(m / 10) * 10) m"
}
