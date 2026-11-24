import Foundation

/// Mėgstamas YouTube kanalas, grojaraštis arba video.
struct Favorite: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String

    var kind: String {
        if url.contains("list=") { return "Grojaraštis" }
        if url.contains("/channel/") || url.contains("/@") || url.contains("/c/") || url.contains("/user/") { return "Kanalas" }
        return "Video"
    }

    /// Kelias YouTube grotuvui (embed): video ID arba "videoseries?list=…".
    /// Kanalas su /channel/UC… rodomas kaip jo įkeltų video grojaraštis (UU…).
    /// @vardas nuorodos be YouTube API neišverčiamos – tokiam kanalui įklijuok /channel/UC… nuorodą.
    var embedPath: String? {
        if let comps = URLComponents(string: url), let list = comps.queryItems?.first(where: { $0.name == "list" })?.value {
            return "videoseries?list=\(list)"
        }
        if let r = url.range(of: #"/channel/(UC[A-Za-z0-9_-]{22})"#, options: .regularExpression) {
            let id = String(url[r]).replacingOccurrences(of: "/channel/", with: "")
            return "videoseries?list=UU\(id.dropFirst(2))"
        }
        return youTubeID(from: url)
    }
}

@MainActor
final class FavoritesStore: ObservableObject {
    @Published var items: [Favorite] = [] { didSet { save() } }
    private let key = "favorites.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let f = try? JSONDecoder().decode([Favorite].self, from: d) { items = f }
    }

    func add(name: String, url: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        items.append(Favorite(name: n.isEmpty ? url : n, url: url.trimmingCharacters(in: .whitespaces)))
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
}
