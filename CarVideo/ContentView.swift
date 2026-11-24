import SwiftUI
import MapKit
import UniformTypeIdentifiers

enum VideoSource: Equatable {
    case none
    case youtube(String)
    case file(URL)
}

struct ContentView: View {
    @StateObject private var loc = LocationManager()
    @StateObject private var nav = RouteManager()
    @StateObject private var road = RoadInfoService()
    @StateObject private var trips = TripStore()
    @StateObject private var favs = FavoritesStore()
    @StateObject private var stations = StationFinder()
    @StateObject private var weather = RouteWeather()
    // v11: vairuotojų pranešimai
    @ObservedObject private var roadAlerts = RoadAlertShared.service
    @AppStorage("f.alerts") private var alertsOn = true
    @State private var showReport = false
    // v12
    @StateObject private var voice = VoiceListener()
    @StateObject private var friendsSvc = FriendsService()
    @StateObject private var zones = AvgSpeedZones()
    // v13
    @StateObject private var lanes = LaneService()
    @StateObject private var breakRem = BreakReminder()
    @AppStorage("f.lanes") private var lanesOn = true
    @AppStorage("f.calm") private var calmOn = true
    @AppStorage("calmAuto") private var calmAuto = true
    @AppStorage("f.parkphoto") private var parkPhotoOn = true
    @AppStorage("units") private var unitsV13 = "kmh"
    @State private var showCalm = false
    @State private var lastTouch = Date()
    @State private var showParkDetail = false
    // v14
    @StateObject private var radio = RadioPlayer()
    @StateObject private var fuelPrices = FuelPriceService()
    @AppStorage("f.musicsplit") private var musicSplitOn = true
    @AppStorage("f.fuelprices") private var fuelPricesOn = true
    @State private var showMusic = false
    // v15
    @ObservedObject private var offlineMaps = OfflineMaps.shared
    // v16
    @StateObject private var multiStop = MultiStopTrip()
    @AppStorage("f.stops") private var stopsOn = true
    @AppStorage("f.evplan") private var evPlanOn = true
    @State private var showStops = false
    @State private var showEV = false
    // v17
    @StateObject private var vig = VignetteChecker()
    @AppStorage("f.tolls") private var tollsOn = true
    @AppStorage("f.scenic") private var scenicOn = true
    @State private var showRouteOpts = false
    @AppStorage("f.voice") private var voiceOn = true
    @AppStorage("f.friends") private var friendsOn = true
    @Environment(\.openURL) private var openURL
    @AppStorage("homeAddress") private var homeAddress = ""
    @AppStorage("etaRecipient") private var etaRecipient = ""
    @State private var parked: ParkedCar? = ParkingStore.load()
    @State private var showStations = false
    @State private var stationTab = 0
    @State private var parkEnd: Date? = ParkingTimer.end
    @AppStorage("bigMap") private var bigMap = false
    /// v4: viena programėlė per visą ekraną ("video" arba "map"); nil – pagrindinis vaizdas (didelis video + žemėlapis šone).
    @State private var solo: String? = nil
    /// Žemėlapio dalis ekrano pločio (mažas / didelis režimas) – keičiama tempiant ribą.
    @AppStorage("splitSmall") private var splitSmall: Double = 0.5   // v12: numatytai per pusę
    @AppStorage("splitBig") private var splitBig: Double = 0.5
    @AppStorage("videoMode") private var videoMode = "split"   // v12: split | full | app
    @AppStorage("split.v12") private var splitMigrated = false
    @AppStorage("mapOnRight") private var mapOnRight = false
    /// "auto" (pagal saulę), "day", "night"
    @AppStorage("nightMode") private var nightMode = "auto"
    // v6: kuro sąnaudos išimtos; spidometras pagal markę
    @AppStorage("carMake") private var carMake = "BMW"
    @AppStorage("gaugeStyle") private var gaugeStyleRaw = "auto"
    // v7: Apple (čia), Waze arba Google Maps
    @AppStorage("navProvider") private var navProviderRaw = NavProvider.apple.rawValue
    private var navProvider: NavProvider { .apple }   // v19: navigacija visada programėlės viduje (Waze / Google nebeatidaromi)
    @State private var showTools = false   // v19
    @State private var showSearch = false   // v19
    // v8: žemėlapis programėlėje – Apple arba Google (su savo API raktu)
    @AppStorage("mapEngine") private var mapEngine = "apple"
    @AppStorage("googleApiKey") private var googleApiKey = ""
    private var useGoogleMap: Bool { mapEngine == "google" && GoogleMapsSetup.configure(googleApiKey) }
    @AppStorage("camerasOn") private var camerasOn = true
    @AppStorage("beepOn") private var beepOn = true
    /// "standard", "satellite" arba "satellite3d"
    @AppStorage("mapMode") private var mapMode = "satellite3d"

    @AppStorage("speedLimitKmh") private var speedLimitKmh: Double = 300
    @AppStorage("lastDestination") private var destination: String = ""
    @AppStorage("lastYouTube") private var lastYouTube: String = ""

    @State private var source: VideoSource = .none
    @State private var showLinkSheet = false
    @State private var showFilePicker = false
    @State private var showSettings = false
    @State private var showTrips = false
    @State private var showFavs = false
    @State private var newFavName = ""
    @State private var newFavURL = ""
    @State private var now = Date()
    @State private var dragStartSplit: Double?
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var night: Bool { _ = now; return isNightNow(mode: nightMode, coordinate: loc.location?.coordinate) }
    @State private var linkInput = ""
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    /// Video blokuojamas, kai važiuojama greičiau nei nustatyta riba.
    // v10: keleivio režimas – patvirtinus, video nesustoja iki kelionės pabaigos (kol sustosi).
    @AppStorage("f.passenger") private var passengerOn = true
    @State private var passengerConfirmed = false
    @AppStorage("f.live") private var liveOn = true
    private var lockedByMotion: Bool { loc.speedKmh > speedLimitKmh && !(passengerOn && passengerConfirmed) }

    private var mapStyle: MapStyle {
        switch mapMode {
        // v3: rodomi kamščiai (žalia / oranžinė / raudona kelio linija).
        case "standard": return .standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: true)
        case "satellite": return .hybrid(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: true)
        default: return .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: true)
        }
    }

    /// 3D režime kamera seka automobilį iš galo, pakreipta 60°.
    private func follow3D(_ l: CLLocation) {
        guard mapMode == "satellite3d" else { return }
        let heading = l.course >= 0 ? l.course : 0
        let distance: Double = bigMap ? 700 : 450
        withAnimation(.linear(duration: 1)) {
            camera = .camera(MapCamera(centerCoordinate: l.coordinate, distance: distance,
                                       heading: heading, pitch: 60))
        }
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            if landscape {
                // Gulsčiai: žemėlapis ir video šalia, riba tarp jų tempiama pirštu.
                let total = geo.size.width - 16 - 48   // v19: juosta su mygtukais tarp žemėlapio ir video
                let frac = bigMap ? splitBig : splitSmall
                HStack(spacing: 0) {
                    if solo == "video" {
                        controlRail(total: total, drag: false)
                        mediaPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if solo == "map" {
                        mapPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                        controlRail(total: total, drag: false)
                    } else if mapOnRight {
                        mediaPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                        controlRail(total: total, drag: true)
                        mapPane.frame(width: total * frac)
                    } else {
                        mapPane.frame(width: total * frac)
                        controlRail(total: total, drag: true)
                        mediaPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(8)
            } else {
                VStack(spacing: 8) {
                    if bigMap {
                        mapPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                        HStack(spacing: 22) { railButtons }.foregroundStyle(.white).buttonStyle(.plain).frame(height: 36)
                        mediaPane.frame(height: geo.size.height * 0.38)
                    } else {
                        mediaPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                        HStack(spacing: 22) { railButtons }.foregroundStyle(.white).buttonStyle(.plain).frame(height: 36)
                        mapPane.frame(height: geo.size.height * 0.38)
                    }
                }
                .padding(8)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTrips) { tripsSheet }
        .sheet(isPresented: $showFavs) { favoritesSheet }
        .onReceive(minuteTimer) { now = $0; parkEnd = ParkingTimer.end }
        .onAppear {
            syncRoadSettings()
            trips.onFinish = { l, dest in
                let p = ParkedCar(latitude: l.coordinate.latitude, longitude: l.coordinate.longitude, date: Date(), place: dest)
                parked = p
                ParkingStore.save(p)
            }
        }
        .sheet(isPresented: $showStations) { stationsSheet }
        .onChange(of: nav.route) { _, r in
            weather.voiceOn = nav.voiceOn
            if let r { Task { await weather.check(route: r) } } else { weather.dismiss() }
            // v10: užrakinto ekrano valdiklis (Live Activity)
            if liveOn, let r { LiveRoute.start(to: destination, minutes: Int(r.expectedTravelTime / 60)) } else { LiveRoute.end() }
        }
        .onChange(of: nav.remainingTime) { _, t in if liveOn { LiveRoute.update(minutes: Int(t / 60)) } }
        // iPhone valdiklis „Važiuoti namo“ atidaro carvideo://namo
        // v11: automatinis paleidimas (Spartieji klavišai → „CarVideo automobilyje“)
        .onReceive(NotificationCenter.default.publisher(for: .carActionRequested)) { _ in runCarAction() }
        .onReceive(NotificationCenter.default.publisher(for: .voiceCommand)) { n in runVoice(n.object as? String ?? "") }
        .onAppear {
            runCarAction()
            if !splitMigrated { splitSmall = 0.5; splitBig = 0.5; splitMigrated = true }   // v12: video ir žemėlapis per pusę
        }
        .sheet(isPresented: $showReport) { ReportAlertSheet { k in if let c = loc.location?.coordinate { roadAlerts.report(k, at: c) } } }
        .onOpenURL { url in
            guard url.scheme == "carvideo", url.host == "namo" else { return }
            let home = homeAddress.trimmingCharacters(in: .whitespaces)
            if home.isEmpty { showSettings = true; return }
            destination = home
            bigMap = true
            startRoute()
        }
        .onChange(of: camerasOn) { _, _ in syncRoadSettings() }
        .onChange(of: beepOn) { _, _ in syncRoadSettings() }
        .onChange(of: nav.voiceOn) { _, _ in syncRoadSettings() }
        .sheet(isPresented: $showLinkSheet) { linkSheet }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.movie, .video, .mpeg4Movie]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                source = .file(url)
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onChange(of: loc.location) { _, newLocation in
            if let newLocation {
                nav.update(with: newLocation)
                road.update(with: newLocation, speedKmh: loc.speedKmh)
                roadAlerts.update(with: newLocation)
                zones.update(with: newLocation)
                friendsSvc.update(location: newLocation, destination: nav.isNavigating ? destination : nil)
                trips.update(with: newLocation, destination: nav.isNavigating ? destination : nil)
                if loc.speedKmh < 3, trips.current == nil { passengerConfirmed = false }
                follow3D(newLocation)
                breakRem.update(speedKmh: loc.speedKmh) { nav.voiceOn ? nav.speakText($0) : () }   // v13
                SpeedVolume.apply(speedKmh: loc.speedKmh)   // v13
            }
        }
        // v13
        .onChange(of: nav.currentStep) { _, s in lanes.update(step: s) }
        .simultaneousGesture(TapGesture().onEnded { lastTouch = Date() })
        .onReceive(minuteTimer) { _ in
            if calmOn, calmAuto, night, !showCalm, Date().timeIntervalSince(lastTouch) > 60 { showCalm = true }
        }
        .overlay {
            if showCalm {
                CalmScreen(speedKmh: loc.speedKmh,
                           turn: nav.currentStep.map { formatDistance(nav.distanceToStep) + " · " + $0.instructions },
                           mph: unitsV13 == "mph") { showCalm = false; lastTouch = Date() }
            }
        }
        .sheet(isPresented: $breakRem.due) {
            BreakSheet(driven: breakRem.drivenText, onFind: {
                breakRem.rested(); destination = "rest area"; startRoute()
            }, onLater: { breakRem.later() })
        }
        // v16
        .sheet(isPresented: $showStops) {
            StopsSheet(trip: multiStop) { optimize in
                Task { if await multiStop.prepare(near: loc.location, optimize: optimize), let first = multiStop.current { destination = first.name ?? ""; await nav.start(to: first, from: loc.location) } }
            }
        }
        .sheet(isPresented: $showEV) {
            EVPlanSheet(location: loc.location) { items in
                multiStop.setItems(items)
                if let first = multiStop.current { destination = first.name ?? ""; Task { await nav.start(to: first, from: loc.location) } }
            }
        }
        .overlay(alignment: .bottom) {
            if multiStop.active, let cur = multiStop.current {
                HStack {
                    Text("\(multiStop.index + 1)/\(multiStop.items.count) → \(cur.name ?? "")").font(.subheadline.bold()).lineLimit(1)
                    if multiStop.hasNext {
                        Button("Toliau") { multiStop.advance(); if let n = multiStop.current { destination = n.name ?? ""; Task { await nav.start(to: n, from: loc.location) } } }.buttonStyle(.borderedProminent)
                    }
                    Button { multiStop.cancel() } label: { Image(systemName: "xmark") }.buttonStyle(.bordered)
                }
                .padding(8).background(.blue.opacity(0.9), in: Capsule()).padding(.bottom, 64)
            }
        }
        .onChange(of: nav.route) { _, r in if let r { OfflineRouteCache.save(r) } }
        // v17
        .onChange(of: nav.route) { _, r in vig.check(r) }
        .onChange(of: nav.distanceToStep) { _, d in if liveOn, nav.isNavigating { LiveRoute17.update(step: nav.currentStep, distance: d, minutes: Int(nav.remainingTime / 60), speed: loc.speedKmh, limit: road.roadLimit) } }
        .sheet(isPresented: $showRouteOpts) { RouteOptionsSheet(vig: vig) { if nav.isNavigating { startRoute() } } }
        .overlay(alignment: .top) { VignetteBanner(vig: vig, onAvoid: { if nav.isNavigating { startRoute() } }, onInfo: { showRouteOpts = true }) }
        .sheet(isPresented: $showParkDetail) {
            ParkingDetailSheet(place: parked?.place ?? "", onShowMap: {
                if let p = parked { withAnimation { camera = .camera(MapCamera(centerCoordinate: p.coordinate, distance: 600, heading: 0, pitch: 0)) } }
            }, onForget: { parked = nil; ParkingStore.save(nil); ParkingTimer.cancel(); parkEnd = nil })
        }
    }

    // MARK: Video

    // v14: muzika arba video šalia žemėlapio
    @ViewBuilder
    private var mediaPane: some View {
        ZStack(alignment: .topTrailing) {
            if musicSplitOn && showMusic { MusicPane(radio: radio) } else { videoPane }   // v19: mygtukai perkelti į juostą tarp žemėlapio ir video
        }
    }

    private var videoPane: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.08))

            switch source {
            case .none:   // v18: YouTube kaip programėlėje – paieška, rekomendacijos, prisijungimas
                YouTubePlayerView(videoID: "", paused: lockedByMotion)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            case .youtube(let id):
                YouTubePlayerView(videoID: id, paused: lockedByMotion)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            case .file(let url):
                LocalVideoView(url: url, paused: lockedByMotion)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if lockedByMotion {
                VStack(spacing: 8) {
                    Image(systemName: "car.fill").font(.system(size: 40))
                    Text("Video sustabdytas važiuojant")
                        .font(.title3.bold())
                    Text("Tęsis, kai sustosi")
                        .font(.subheadline).opacity(0.8)
                    if passengerOn {
                        Button("Žiūri keleivis – tęsti video") { passengerConfirmed = true }
                            .buttonStyle(.bordered).tint(.white).padding(.top, 6)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: Map

    // v19: žemėlapis kaip Waze – paieška viršuje, mygtukai viename stulpelyje dešinėje, mažas spidometras kairėje apačioje.
    private var mapPane: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                Map(position: $camera) {
                    UserAnnotation()
                    if let r = nav.route {
                        MapPolyline(r.polyline)
                            .stroke(.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    }
                    if let d = nav.destinationItem {
                        Marker(item: d)
                    }
                    if let p = parked {
                        Marker("Automobilis", monogram: Text("P"), coordinate: p.coordinate).tint(.blue)
                    }
                    if friendsOn {
                        ForEach(friendsSvc.friends) { f in
                            if let la = f.lat, let lo = f.lon {
                                Annotation(f.name, coordinate: .init(latitude: la, longitude: lo)) {
                                    Text(String(f.name.prefix(1))).font(.caption.bold()).foregroundStyle(.white).frame(width: 28, height: 28).background(.green, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 2))
                                }
                            }
                        }
                    }
                    if alertsOn {
                        ForEach(roadAlerts.alerts.filter { roadAlerts.enabled($0.kind) }) { a in
                            Annotation(a.kind.title, coordinate: a.coordinate) {
                                Image(systemName: a.kind.symbol).font(.caption.bold()).foregroundStyle(.white)
                                    .padding(7).background(a.kind.color, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                    }
                }
                .mapStyle(mapStyle)
                .overlay(alignment: .topLeading) {
                    if let z = zones.active { AvgZoneBox(zone: z.zone, avg: z.avgKmh, left: z.metersLeft).padding(.top, 70).padding(.leading, 12) }
                }
                .overlay {   // v15: be interneto – žemėlapis iš telefono
                    if offlineMaps.useOffline {
                        OfflineMapView(center: loc.location?.coordinate)
                            .overlay(alignment: .bottom) { Label("Be interneto · žemėlapis iš telefono", systemImage: "wifi.slash").font(.caption.bold()).padding(8).background(.black.opacity(0.75), in: Capsule()).padding(.bottom, 70) }
                    }
                }
                .overlay {
                    if useGoogleMap {
                        GoogleMapView(route: nav.route, location: loc.location, night: night)
                    }
                }
                .overlay(alignment: .top) {
                    if let (a, m) = roadAlerts.approaching { AlertBanner(alert: a, meters: m) { roadAlerts.vote(stillThere: $0) }.padding(.top, 60) }
                }
                .environment(\.colorScheme, night ? .dark : .light)
                .mapControls { MapScaleView() }   // v19: Apple mygtukai nebedengia mūsų stulpelio
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .bottomTrailing) { mapButtonColumn.padding(8) }
                .overlay(alignment: .top) { if nav.isNavigating { turnBanner } else { searchBar.padding(8).padding(.trailing, 52) } }   // v19: posūkis žemėlapio viršuje, nebedengia YouTube

                infoCluster.padding(.leading, 8).padding(.bottom, 26)   // v19: virš Apple „Legal“ užrašo
            }
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    cameraWarning
                    weatherWarning
                    fasterRouteOffer
                }
                .padding(.top, nav.isNavigating ? 84 : 52)
            }

            if nav.isNavigating {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(nav.remainingTime / 60)) min · \(formatDistance(nav.remainingDistance))").font(.headline.monospacedDigit())
                        Text(destination).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button(role: .destructive) { nav.stop(); trips.finish() } label: { Label("Baigti", systemImage: "xmark") }
                        .buttonStyle(.borderedProminent).tint(.red)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            if let err = nav.errorText {
                Text(err).font(.caption).foregroundStyle(.orange)
            }
        }
        .sheet(isPresented: $showTools) { toolsSheet }
        .sheet(isPresented: $showSearch) {
            DestinationSearchSheet(location: loc.location, home: homeAddress) { item, title in
                destination = title
                camera = .userLocation(followsHeading: true, fallback: .automatic)
                Task { await nav.start(to: item, from: loc.location) }
            }
        }
    }

    /// v19: „Kur važiuojam?“ – kaip Waze.
    private var searchBar: some View {
        Button { showSearch = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(nav.isCalculating ? "Ieškau maršruto…" : "Kur važiuojam?").lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 40)
            .background(.black.opacity(0.72), in: Capsule())
        }
        .accessibilityLabel("Ieškoti tikslo")
    }

    /// v19: visi žemėlapio mygtukai viename stulpelyje – niekas nepersidengia.
    private var mapButtonColumn: some View {
        VStack(spacing: 8) {
            if alertsOn {
                roundButton("exclamationmark.triangle.fill", bg: .orange, label: "Pranešti apie kliūtį") { showReport = true }
            }
            if voiceOn {
                roundButton(voice.listening ? "waveform" : "mic.fill", bg: voice.listening ? .red : .blue, label: "Balso komanda") { voice.toggle() }
            }
            if calmOn {
                roundButton("moon.fill", bg: .black.opacity(0.65), label: "Ramus naktinis ekranas") { showCalm = true }
            }
            roundButton("location.fill", bg: .black.opacity(0.65), label: "Grįžti prie automobilio") {
                withAnimation { camera = .userLocation(followsHeading: true, fallback: .automatic) }
            }
            roundButton("square.grid.2x2.fill", bg: .black.opacity(0.65), label: "Įrankiai") { showTools = true }
        }
    }

    private func roundButton(_ icon: String, bg: Color, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 42, height: 42).background(bg, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
        }
        .accessibilityLabel(Text(label))
    }

    /// v19: buvusi mygtukų eilė po žemėlapiu – dabar atskirame lange.
    private var toolsSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    if stopsOn { toolTile("Kelionė su sustojimais", "point.topleft.down.to.point.bottomright.curvepath") { if multiStop.names.allSatisfy(\.isEmpty) { multiStop.names = ["", destination] }; showStops = true } }
                    if tollsOn || scenicOn { toolTile("Maršruto parinktys", "slider.horizontal.3") { showRouteOpts = true } }
                    if evPlanOn { toolTile("Kelionė elektromobiliu", "bolt.car") { showEV = true } }
                    toolTile("Degalinės ir įkrovimas", "fuelpump.fill") { showStations = true; Task { await stations.search(near: loc.location) }; Task { await fuelPrices.load(near: loc.location, country: V14.country) } }
                    toolTile(solo == "map" ? "Žemėlapis ir video" : "Žemėlapis per visą ekraną", solo == "map" ? "rectangle.split.2x1" : "map") { withAnimation { solo = solo == "map" ? nil : "map" } }
                    toolTile(bigMap ? "Mažesnis žemėlapis" : "Didesnis žemėlapis", bigMap ? "play.rectangle.fill" : "map.fill") { bigMap.toggle() }
                    if let p = parked {
                        toolTile("Kur palikau automobilį", "parkingsign.circle.fill") {
                            if parkPhotoOn { showParkDetail = true } else { withAnimation { camera = .camera(MapCamera(centerCoordinate: p.coordinate, distance: 600, heading: 0, pitch: 0)) } }
                        }
                        Menu {
                            ForEach([15, 30, 60, 120], id: \.self) { m in
                                Button(m < 60 ? "\(m) min" : "\(m / 60) val.") { Task { await ParkingTimer.start(minutes: m); parkEnd = ParkingTimer.end } }
                            }
                            if parkEnd != nil { Button("Išjungti laikmatį", role: .destructive) { ParkingTimer.cancel(); parkEnd = nil } }
                            Button("Pamiršti vietą", role: .destructive) { parked = nil; ParkingStore.save(nil); ParkingTimer.cancel(); parkEnd = nil; ParkingExtras.clear() }
                        } label: { tileLabel(parkEnd.map { $0 > now ? "Parkavimas · \(max(1, Int($0.timeIntervalSince(now) / 60))) min" : "Parkavimo laikmatis" } ?? "Parkavimo laikmatis", "timer") }
                    }
                    toolTile("Mėgstami YouTube", "star.fill") { showFavs = true }
                    toolTile("Kelionės", "road.lanes") { showTrips = true }
                    if alertsOn { toolTile("Pranešti apie kliūtį", "exclamationmark.triangle.fill") { showReport = true } }
                    toolTile("Nustatymai", "gearshape.fill") { showSettings = true }
                }
                .padding()
            }
            .navigationTitle("Įrankiai").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Uždaryti") { showTools = false } } }
        }
    }

    private func toolTile(_ title: LocalizedStringKey, _ icon: String, action: @escaping () -> Void) -> some View {
        Button { showTools = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { action() } } label: { tileLabel(title, icon) }
            .buttonStyle(.plain)
    }

    private func tileLabel(_ title: LocalizedStringKey, _ icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2)
            Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 88)
        .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 14))
    }

    /// v19: juosta tarp žemėlapio ir video – video / muzikos mygtukai nebedengia YouTube paieškos ir meniu.
    @ViewBuilder
    private var railButtons: some View {
        Button { withAnimation { solo = solo == "video" ? nil : "video" } } label: {
            Image(systemName: solo == "video" ? "rectangle.split.2x1" : "arrow.up.left.and.arrow.down.right").font(.system(size: 16, weight: .semibold))
        }
        .accessibilityLabel(solo == "video" ? "Žemėlapis ir video" : "Video per visą ekraną")
        if musicSplitOn {
            Button { showMusic.toggle() } label: { Image(systemName: showMusic ? "play.rectangle.fill" : "music.note").font(.system(size: 16, weight: .semibold)) }
                .accessibilityLabel(showMusic ? "Rodyti video" : "Rodyti muziką")
        }
        Menu {
            Button("YouTube", systemImage: "play.rectangle") { showMusic = false; source = .none }
            Button("Failas iš telefono", systemImage: "folder") { showFilePicker = true }
        } label: { Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)) }
        .accessibilityLabel("Video šaltinis")
    }

    @ViewBuilder
    private func controlRail(total: CGFloat, drag: Bool) -> some View {
        VStack(spacing: 14) {
            railButtons
            Spacer(minLength: 8)
            if drag {
                Capsule().fill(dragStartSplit == nil ? Color(white: 0.4) : .accentColor).frame(width: 5, height: 56)
                    .accessibilityLabel("Tempk, kad pakeistum žemėlapio dydį")
            }
            Spacer(minLength: 8)
        }
        .foregroundStyle(.white).buttonStyle(.plain)
        .frame(width: 48).padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { g in
                let start = dragStartSplit ?? (bigMap ? splitBig : splitSmall)
                if dragStartSplit == nil { dragStartSplit = start }
                let delta = Double(g.translation.width / max(total, 1)) * (mapOnRight ? -1 : 1)
                let v = min(0.85, max(0.15, start + delta))
                if bigMap { splitBig = v } else { splitSmall = v }
            }
            .onEnded { _ in dragStartSplit = nil }, including: drag ? .all : .subviews)
    }

    /// v12: YouTube – šalia žemėlapio per pusę, per visą ekraną arba YouTube programėlėje.
    /// YouTube programėlėje matosi tavo paskyra, bet video nebus šalia žemėlapio ir CarVideo negalės jo sustabdyti važiuojant.
    private func playYouTube(_ idOrPath: String) {
        if videoMode == "app" {
            let web: String = idOrPath.hasPrefix("videoseries?list=")
                ? "www.youtube.com/playlist?list=" + idOrPath.replacingOccurrences(of: "videoseries?list=", with: "")
                : "www.youtube.com/watch?v=" + idOrPath
            if let app = URL(string: "youtube://" + web), UIApplication.shared.canOpenURL(app) { openURL(app) }
            else if let u = URL(string: "https://" + web) { openURL(u) }
            return
        }
        source = .youtube(idOrPath)
        withAnimation { solo = videoMode == "full" ? "video" : nil }
        if videoMode == "split" { splitSmall = 0.5; splitBig = 0.5 }
    }

    /// v12: balso komandos ir Siri.
    private func runVoice(_ cmd: String) {
        switch VoiceCommand(rawValue: cmd) {
        case .home: UserDefaults.standard.set("home", forKey: "pendingCarAction"); runCarAction()
        case .work: destination = UserDefaults.standard.string(forKey: "workAddress") ?? "Darbas"; bigMap = true; startRoute()
        case .police, .pothole, .crash:
            if let k = AlertKind(rawValue: cmd), let c = loc.location?.coordinate { roadAlerts.report(k, at: c) }
        case .video: withAnimation { solo = "video" }
        case .map: withAnimation { solo = "map" }
        case .half: withAnimation { solo = nil }; splitSmall = 0.5; splitBig = 0.5
        case .next, .pause, .play, .none: break   // muziką valdo Spotify / Apple Music (Siri: „kitas takelis“)
        }
    }

    /// v11: veiksmas prisijungus prie automobilio.
    private func runCarAction() {
        guard let a = PendingCarAction.take() else { return }
        switch a {
        case .home:
            let home = homeAddress.trimmingCharacters(in: .whitespaces)
            guard !home.isEmpty else { return }
            destination = home; bigMap = true; startRoute()
        case .music:
            if let u = URL(string: "spotify:") { openURL(u) }   // arba Apple Music: "music://"
        case .menu, .none: break
        }
    }

    private func startRoute() {
        guard !destination.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        camera = .userLocation(followsHeading: true, fallback: .automatic)
        Task { await nav.start(to: destination, from: loc.location) }
    }

    // MARK: Posūkio juosta

    @ViewBuilder
    private var turnBanner: some View {
        if let step = nav.currentStep {
            HStack(spacing: 10) {
                Image(systemName: maneuverIcon(for: step.instructions))
                    .font(.system(size: 30, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDistance(nav.distanceToStep))
                        .font(.system(.title2, design: .rounded).bold())
                    Text(step.instructions)
                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                }
                Spacer(minLength: 8)
                ShareLink(item: etaMessage) {
                    Image(systemName: "paperplane.fill").font(.title3)
                        .padding(10).background(.white.opacity(0.2), in: Circle())
                }
                .accessibilityLabel("Siųsti atvykimo laiką")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.green.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
            .padding(6)
            // v13: eismo juostos prieš posūkį
            .overlay(alignment: .bottomLeading) {
                if lanesOn, let info = lanes.info, nav.distanceToStep < 600 {
                    LaneStrip(info: info, instructions: step.instructions).padding(.leading, 16).offset(y: 52)
                }
            }
        }
    }

    // MARK: Sheets

    private var linkSheet: some View {
        NavigationStack {
            Form {
                TextField("https://youtu.be/...", text: $linkInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Įklijuoti iš iškarpinės") {
                    linkInput = UIPasteboard.general.string ?? linkInput
                }
            }
            .navigationTitle("YouTube nuoroda")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Atšaukti") { showLinkSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rodyti") {
                        if let id = youTubeID(from: linkInput) {
                            lastYouTube = linkInput
                            playYouTube(id)
                            showLinkSheet = false
                        }
                    }
                    .disabled(youTubeID(from: linkInput) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Video sustoja, kai greitis viršija") {
                    Stepper("\(Int(speedLimitKmh)) km/h", value: $speedLimitKmh, in: 0...300, step: 5)
                }
                Section("Žemėlapis") {
                    Picker("Vaizdas", selection: $mapMode) {
                        Text("Įprastas").tag("standard")
                        Text("Satelitas").tag("satellite")
                        Text("Satelitas 3D").tag("satellite3d")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Maršrutas") {
                    Toggle("Balso nurodymai", isOn: $nav.voiceOn)
                }
                Section {
                    Toggle("Greičio kameros", isOn: $camerasOn)
                    Toggle("Garsinis signalas", isOn: $beepOn)
                } header: { Text("Įspėjimai") } footer: { Text("Kameros ir kelių greičio ribos iš OpenStreetMap. Kai kurių gali trūkti.") }
                Section {
                    Picker("Režimas", selection: $nightMode) {
                        Text("Automatiškai").tag("auto")
                        Text("Diena").tag("day")
                        Text("Naktis").tag("night")
                    }
                    .pickerStyle(.segmented)
                } header: { Text("Naktinis režimas") } footer: {
                    let t = SunTimes(coordinate: loc.location?.coordinate ?? SunTimes.vilnius)
                    Text("Šiandien saulė teka \(t.rise.formatted(date: .omitted, time: .shortened)), leidžiasi \(t.set.formatted(date: .omitted, time: .shortened)).")
                }
                Section {
                    TextField("Namų adresas", text: $homeAddress)
                    TextField("Kam siunčiamas atvykimo laikas (nebūtina)", text: $etaRecipient)
                } header: { Text("Namai ir atvykimo žinutė") } footer: {
                    Text("Pridėk valdiklį „Važiuoti namo“ prie iPhone pradžios ekrano: paspaudus jį, maršrutas namo prasideda iškart.")
                }
                Section {
                    Picker("Žemėlapis", selection: $mapEngine) {
                        Text("Apple").tag("apple")
                        Text("Google").tag("google")
                    }
                    .pickerStyle(.segmented)
                    if mapEngine == "google" {
                        TextField("Google Maps API raktas (AIza…)", text: $googleApiKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } header: { Text("Žemėlapis programėlėje") } footer: {
                    Text("Google žemėlapiui reikia tavo Google Cloud rakto (Maps SDK for iOS). Rodymas nemokamas. Be rakto rodomas Apple žemėlapis. Pakeitus raktą, perkrauk programėlę.")
                }
                Section {
                    TextField("Automobilio markė (pvz. BMW)", text: $carMake)
                    Picker("Spidometras", selection: $gaugeStyleRaw) {
                        Text("Automatiškai pagal markę").tag("auto")
                        ForEach(GaugeStyle.allCases) { g in Text(g.title).tag(g.rawValue) }
                    }
                    HStack {
                        Spacer()
                        BrandGauge(style: gaugeStyle, speed: 120, limit: 300).frame(width: 110)
                        Spacer()
                    }
                } header: { Text("Spidometras") }
                Section("Išdėstymas") {
                    Toggle("Žemėlapis dešinėje", isOn: $mapOnRight)
                    Button("Per pusę (50/50)") { splitSmall = 0.5; splitBig = 0.5 }
                }
                Section {
                    Text("Dabartinis greitis: \(Int(loc.speedKmh.rounded())) km/h")
                    if !loc.authorized {
                        Text("Leisk vietos prieigą: Nustatymai → CarVideo → Vieta").foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Nustatymai")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Gerai") { showSettings = false } }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Išdėstymas

    private func divider(total: CGFloat) -> some View {
        ZStack {
            Color.clear.frame(width: 18)
            Capsule().fill(dragStartSplit == nil ? Color(white: 0.4) : .accentColor).frame(width: 5, height: 56)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { g in
                let start = dragStartSplit ?? (bigMap ? splitBig : splitSmall)
                if dragStartSplit == nil { dragStartSplit = start }
                let delta = Double(g.translation.width / max(total, 1)) * (mapOnRight ? -1 : 1)
                let v = min(0.85, max(0.15, start + delta))
                if bigMap { splitBig = v } else { splitSmall = v }
            }
            .onEnded { _ in dragStartSplit = nil })
        .accessibilityLabel("Tempk, kad pakeistum žemėlapio dydį")
    }

    private func syncRoadSettings() {
        road.camerasOn = camerasOn
        road.beepOn = beepOn
        road.voiceOn = nav.voiceOn
    }

    // MARK: Greitis, ženklas, kamera

    private var gaugeStyle: GaugeStyle {
        GaugeStyle(rawValue: gaugeStyleRaw) ?? GaugeStyle.forMake(carMake)
    }

    /// v19: mažas spidometras kaip Waze – greitis apskritime, šalia greičio riba.
    private var infoCluster: some View {
        let lim = road.roadLimit
        let overRoad = lim.map { loc.speedKmh > Double($0) + 3 } ?? false
        let metric = unitsV13 != "mph"
        let shown = metric ? loc.speedKmh : loc.speedKmh / 1.609
        return HStack(spacing: 6) {
            VStack(spacing: -2) {
                Text("\(Int(shown.rounded()))").font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                Text(metric ? "km/h" : "mph").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(overRoad || lockedByMotion ? .white : .primary)
            .frame(width: 58, height: 58)
            .background(Circle().fill(lockedByMotion ? Color.red : (overRoad ? Color.orange : Color(white: 0.12))))
            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1.5))
            .shadow(radius: 4)
            .accessibilityLabel("Greitis \(Int(shown.rounded()))")
            if let lim {
                Text("\(lim)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.white))
                    .overlay(Circle().stroke(Color(red: 0.88, green: 0.14, blue: 0.17), lineWidth: 4))
                    .accessibilityLabel("Greičio riba \(lim)")
            }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var cameraWarning: some View {
        if let cam = road.cameraAhead {
            let bad = cam.limit.map { loc.speedKmh > Double($0) } ?? false
            HStack(spacing: 8) {
                Image(systemName: "camera.fill").font(.title3)
                VStack(alignment: .leading, spacing: 0) {
                    Text(formatDistance(cam.distance)).font(.headline.monospacedDigit())
                    Text("Greičio kamera" + (cam.limit.map { " · riba \($0)" } ?? "")).font(.caption)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(bad ? Color.red : Color(white: 0.12).opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(bad ? Color.clear : Color.orange, lineWidth: 2))
            .padding(8)
        }
    }

    // MARK: Kelionės

    private var tripsSheet: some View {
        NavigationStack {
            List {
                let all = trips.trips
                let km = all.reduce(0) { $0 + $1.km }
                let mins = all.reduce(0) { $0 + $1.minutes }
                Section {
                    HStack {
                        stat(String(format: "%.1f", km), "km")
                        stat(mins > 0 ? "\(Int(km / (mins / 60)))" : "0", "vid. km/h")
                        stat("\(Int(all.map(\.maxKmh).max() ?? 0))", "maks. km/h")
                        stat("\(all.count)", "kelionės")
                    }
                }
                if let c = trips.current {
                    Section("Dabar") { tripRow(c) }
                }
                Section("Istorija") {
                    if all.isEmpty { Text("Kelionės įrašomos automatiškai, kai pradedi važiuoti.").foregroundStyle(.secondary) }
                    ForEach(all) { tripRow($0) }
                        .onDelete { trips.delete(at: $0) }
                }
            }
            .navigationTitle("Kelionės")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gerai") { showTrips = false } } }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func tripRow(_ t: Trip) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.destination ?? "Kelionė").font(.headline)
                Text("\(t.start.formatted(date: .abbreviated, time: .shortened)) · \(Int(t.minutes.rounded())) min · maks. \(Int(t.maxKmh)) km/h")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f km", t.km)).font(.headline.monospacedDigit())
                Text("\(Int(t.avgKmh)) km/h vid. · \(Int(t.maxKmh)) km/h maks.")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Mėgstami YouTube

    private var favoritesSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(favs.items) { f in
                        Button {
                            if let path = f.embedPath { playYouTube(path); showFavs = false }
                        } label: {
                            HStack {
                                Image(systemName: "play.rectangle.fill").foregroundStyle(.red).font(.title2)
                                VStack(alignment: .leading) {
                                    Text(f.name).font(.headline)
                                    Text(f.kind + (f.embedPath == nil ? " · nuoroda neatpažinta" : "")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { favs.items.remove(atOffsets: $0) }
                    .onMove { favs.items.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Kanalui naudok nuorodą su /channel/UC… – tada grojami jo naujausi video.")
                }
                Section("Pridėti") {
                    TextField("Pavadinimas", text: $newFavName)
                    TextField("YouTube nuoroda", text: $newFavURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Įklijuoti iš iškarpinės") { newFavURL = UIPasteboard.general.string ?? newFavURL }
                    Button("Pridėti") {
                        favs.add(name: newFavName, url: newFavURL)
                        newFavName = ""; newFavURL = ""
                    }
                    .disabled(newFavURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Mėgstami YouTube")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Gerai") { showFavs = false } }
            }
        }
    }

    // MARK: v3

    @ViewBuilder
    private var fasterRouteOffer: some View {
        if nav.fasterRoute != nil {
            HStack(spacing: 8) {
                Image(systemName: "car.2.fill").font(.title3).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Kamštis priekyje").font(.headline)
                    Text("Greitesnis kelias: −\(max(1, Int(nav.fasterSaving / 60))) min").font(.caption)
                }
                Spacer(minLength: 0)
                Button("Važiuoti") { nav.acceptFaster() }
                    .buttonStyle(.borderedProminent).tint(.green)
                Button("Ne") { nav.declineFaster() }
                    .buttonStyle(.bordered)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(red: 0.23, green: 0.11, blue: 0), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange, lineWidth: 2))
            .padding(8)
        }
    }

    // MARK: v2

    private var etaMessage: String {
        let arrival = Date().addingTimeInterval(nav.remainingTime).formatted(date: .omitted, time: .shortened)
        let place = nav.destinationItem?.name ?? destination
        let who = etaRecipient.trimmingCharacters(in: .whitespaces)
        return (who.isEmpty ? "" : who + ", ") + "būsiu \(place) apie \(arrival) (dar \(Int(nav.remainingTime / 60)) min)."
    }

    @ViewBuilder
    private var weatherWarning: some View {
        if let w = weather.warning {
            HStack(spacing: 8) {
                Image(systemName: w.title.contains("Rūkas") ? "cloud.fog.fill" : "snowflake").font(.title3).foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 0) {
                    Text(w.title).font(.headline)
                    Text(w.detail).font(.caption)
                }
                Spacer(minLength: 0)
                Button { weather.dismiss() } label: { Image(systemName: "xmark").padding(6) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(red: 0.35, green: 0.29, blue: 0), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow, lineWidth: 2))
            .padding(8)
        }
    }

    private var stationsSheet: some View {
        NavigationStack {
            List {
                Picker("", selection: $stationTab) {
                    Text("Degalinės").tag(0)
                    Text("Įkrovimas").tag(1)
                }
                .pickerStyle(.segmented)
                let list = stationTab == 0 ? stations.fuel : stations.ev
                if fuelPricesOn && stationTab == 0 && !fuelPrices.items.isEmpty {   // v14: kainos, pigiausios viršuje
                    FuelPriceSection(svc: fuelPrices) { s in
                        showStations = false; destination = s.name
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: s.coordinate)); item.name = s.name
                        if navProvider != .apple { ExternalNav.open(navProvider, query: s.name, coordinate: s.coordinate) }
                        else { Task { await nav.start(to: item, from: loc.location) } }
                    }
                }
                if stations.loading { ProgressView() }
                else if list.isEmpty { Text("Šalia nieko nerasta (5 km).").foregroundStyle(.secondary) }
                ForEach(list) { st in
                    Button {
                        showStations = false
                        destination = st.item.name ?? destination
                        if navProvider != .apple {
                            ExternalNav.open(navProvider, query: st.item.name ?? destination, coordinate: st.item.placemark.coordinate)
                        } else {
                            Task { await nav.start(to: st.item, from: loc.location) }
                        }
                    } label: {
                        HStack {
                            Image(systemName: st.isEV ? "bolt.car.fill" : "fuelpump.fill")
                                .foregroundStyle(st.isEV ? Color.green : Color.orange)
                            VStack(alignment: .leading) {
                                Text(st.item.name ?? "Be pavadinimo").font(.headline)
                                Text(formatDistance(st.distance)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Vesti").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Šalia tavęs")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gerai") { showStations = false } } }
        }
    }
}
