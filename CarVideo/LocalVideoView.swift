import SwiftUI
import AVKit

/// Video failas iš telefono (Files programos). v3: tęsiasi nuo ten, kur sustojo.
struct LocalVideoView: View {
    let url: URL
    let paused: Bool
    @State private var player = AVPlayer()
    @State private var observer: Any?
    @State private var resumedFrom: Double = 0

    var body: some View {
        VideoPlayer(player: player)
            .overlay(alignment: .topLeading) {
                if resumedFrom > 5 {
                    Text("Tęsiama nuo \(Int(resumedFrom) / 60):\(String(format: "%02d", Int(resumedFrom) % 60))")
                        .font(.caption).padding(6)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        .padding(8)
                        .task { try? await Task.sleep(for: .seconds(3)); resumedFrom = 0 }
                }
            }
            .onAppear { open(url) }
            .onChange(of: url) { old, newURL in
                save(for: old)
                open(newURL)
            }
            .onChange(of: paused) { _, isPaused in
                if isPaused { player.pause(); save(for: url) }
            }
            .onDisappear {
                save(for: url)
                if let observer { player.removeTimeObserver(observer) }
                observer = nil
            }
    }

    private func key(_ u: URL) -> String { "file:" + u.lastPathComponent }

    private func open(_ u: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: u))
        let t = VideoProgress.position(for: key(u))
        if t > 5 {
            player.seek(to: CMTime(seconds: t, preferredTimescale: 600))
            resumedFrom = t
        }
        player.play()
        if observer == nil {
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { _ in
                if let current = (player.currentItem?.asset as? AVURLAsset)?.url { save(for: current) }
            }
        }
    }

    private func save(for u: URL) {
        let t = player.currentTime().seconds
        let d = player.currentItem?.duration.seconds
        guard t.isFinite, t > 0 else { return }
        VideoProgress.save(t, for: key(u), duration: (d?.isFinite ?? false) ? d : nil)
    }
}
