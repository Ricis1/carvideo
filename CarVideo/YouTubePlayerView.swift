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

/// YouTube grotuvas WKWebView viduje. `videoID` – video ID arba "videoseries?list=…". `paused` = true sustabdo video.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    let paused: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        load(videoID, in: web, context: context)
        context.coordinator.startTracking(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if context.coordinator.loadedID != videoID {
            load(videoID, in: web, context: context)
        }
        if paused {
            web.evaluateJavaScript("document.querySelectorAll('video').forEach(v => v.pause());")
        }
    }

    private func load(_ id: String, in web: WKWebView, context: Context) {
        context.coordinator.loadedID = id
        // id gali būti video ID arba "videoseries?list=…" (grojaraštis / kanalo video).
        let sep = id.contains("?") ? "&" : "?"
        // v3: tęsiam nuo išsaugotos vietos (grojaraščiams – tik pavieniams video).
        let resume = id.contains("videoseries") ? 0 : Int(VideoProgress.position(for: id))
        let start = resume > 5 ? "&start=\(resume)" : ""
        guard let url = URL(string: "https://www.youtube.com/embed/\(id)\(sep)playsinline=1&autoplay=1&rel=0\(start)") else { return }
        var req = URLRequest(url: url)
        // YouTube reikalauja Referer, kitaip kai kurie video rodo klaidą 153.
        req.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        web.load(req)
    }

    final class Coordinator {
        var loadedID: String?
        private var timer: Timer?
        weak var web: WKWebView?

        /// Kas 5 s išsaugo, kur sustota.
        func startTracking(_ web: WKWebView) {
            self.web = web
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.savePosition() }
        }

        func savePosition() {
            guard let web, let id = loadedID, !id.contains("videoseries") else { return }
            web.evaluateJavaScript("(function(){var v=document.querySelector('video');return v?[v.currentTime,v.duration||0]:null})()") { res, _ in
                guard let a = res as? [Double], a.count == 2, a[0] > 0 else { return }
                VideoProgress.save(a[0], for: id, duration: a[1])
            }
        }

        deinit { timer?.invalidate() }
    }
}
