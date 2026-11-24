import ActivityKit

/// v10: užrakinto ekrano valdiklis (Live Activity) – bendras programėlei ir valdiklių plėtiniui.
/// v17: papildyta Dynamic Island duomenimis (posūkis, atstumas, greitis). Nauji laukai neprivalomi.
struct NavActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var minutesLeft: Int
        var arrival: Date
        var traffic: String   // „mažas“, „vidutinis“, „didelis“
        // v17
        var turnSymbol: String? = nil      // SF Symbol, pvz. "arrow.turn.up.left"
        var turnText: String? = nil        // „Sukite kairėn į Gedimino pr.“
        var turnDistance: Int? = nil       // metrais
        var speedKmh: Int? = nil
        var limitKmh: Int? = nil
    }
    var destination: String
}
