import SwiftUI
import WebKit

/// Ištraukia YouTube video ID iš įvairių nuorodų formų
/// (youtube.com/watch?v=, youtu.be/, /shorts/, /embed/) arba gryno ID.
func youTubeID(from input: String) -> String? {
    let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil { return s }
    guard let url = URL(string: s), let host = url.host?.lowercased() else { return nil }
    if host.contains("youtu.be") {
        return url.pathComponents.dropFirst().first
    }
    if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "v" })?.value {
        return v
    }
    let parts = url.pathComponents
    if let i = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }), i + 1 < parts.count {
        return parts[i + 1]
    }
    return nil
}

/// v18: YouTube kaip programėlėje – pilna m.youtube.com svetainė (paieška, rekomendacijos, prisijungimas, grojaraščiai).
/// Įterptas grotuvas (embed) programėlėse rodo klaidą 152-4, todėl jo nebenaudojam.
/// `videoID` – tuščias (YouTube pradžia), video ID arba "videoseries?list=…". `paused` = true sustabdo video važiuojant.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    let paused: Bool

    /// Telefono Safari naršyklės atpažinimas – YouTube rodo pilną mobilią versiją.
    static let safariUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()   // prisijungimas prie YouTube išlieka
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = Self.safariUA
        web.isOpaque = false
        web.backgroundColor = .black
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.isScrollEnabled = true
        web.navigationDelegate = context.coordinator
        load(videoID, in: web, context: context)
        context.coordinator.startTracking(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.paused = paused
        if !videoID.isEmpty, context.coordinator.loadedID != videoID {
            load(videoID, in: web, context: context)
        }
        if paused { Coordinator.pauseAll(web) }
    }

    private func load(_ id: String, in web: WKWebView, context: Context) {
        context.coordinator.loadedID = id
        let path: String
        if id.isEmpty { path = "" }
        else if id.hasPrefix("videoseries?list=") { path = "playlist?list=" + id.replacingOccurrences(of: "videoseries?list=", with: "") }
        else {
            let resume = Int(VideoProgress.position(for: id))
            path = "watch?v=\(id)" + (resume > 5 ? "&t=\(resume)s" : "")
        }
        guard let url = URL(string: "https://m.youtube.com/" + path) else { return }
        web.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedID: String?
        var paused = false
        private var timer: Timer?
        weak var web: WKWebView?

        static func pauseAll(_ web: WKWebView) {
            web.evaluateJavaScript("document.querySelectorAll('video').forEach(v => v.pause());")
        }

        /// Kas sekundę: važiuojant neleidžia paleisti video; kas 5 s išsaugo, kur sustota.
        func startTracking(_ web: WKWebView) {
            self.web = web
            timer?.invalidate()
            var tick = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, let web = self.web else { return }
                if self.paused { Self.pauseAll(web) }
                tick += 1; if tick % 5 == 0 { self.savePosition() }
            }
        }

        /// Dabartinio video ID iš adreso (m.youtube.com/watch?v=…).
        private var currentID: String? {
            guard let u = web?.url, let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return nil }
            if let v = c.queryItems?.first(where: { $0.name == "v" })?.value { return v }
            let p = u.pathComponents
            if let i = p.firstIndex(where: { $0 == "shorts" }), i + 1 < p.count { return p[i + 1] }
            return nil
        }

        func savePosition() {
            guard let web, let id = currentID else { return }
            UserDefaults.standard.set(id, forKey: "lastYouTube")
            web.evaluateJavaScript("(function(){var v=document.querySelector('video');return v?[v.currentTime,v.duration||0]:null})()") { res, _ in
                guard let a = res as? [Double], a.count == 2, a[0] > 0 else { return }
                VideoProgress.save(a[0], for: id, duration: a[1])
            }
        }

        /// Nuorodos į YouTube programėlę ar kitas svetaines lieka šiame lange, išskyrus aiškiai išorines (app store ir pan.).
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let u = action.request.url, let scheme = u.scheme, !["http", "https", "about", "blob", "data"].contains(scheme) {
                decisionHandler(.cancel); return   // pvz. youtube:// – liekam programėlėje
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if paused { Self.pauseAll(webView) }
        }

        deinit { timer?.invalidate() }
    }
}
