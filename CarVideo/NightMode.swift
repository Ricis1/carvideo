import Foundation
import CoreLocation

/// Saulėtekio ir saulėlydžio laikas (supaprastinta NOAA formulė, tikslumas ~ kelios minutės).
struct SunTimes {
    let rise: Date
    let set: Date

    init(date: Date = Date(), coordinate c: CLLocationCoordinate2D) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let n = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let lat = c.latitude * .pi / 180
        let decl = 23.44 * .pi / 180 * sin(2 * .pi * (284 + n) / 365)
        let cosHa = (sin(-0.833 * .pi / 180) - sin(lat) * sin(decl)) / (cos(lat) * cos(decl))
        let ha = acos(max(-1, min(1, cosHa))) * 180 / .pi
        let b = 2 * .pi * (n - 81) / 364
        let eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)
        let noonMin = 720 - 4 * c.longitude - eot
        let midnight = cal.startOfDay(for: date)
        rise = midnight.addingTimeInterval((noonMin - 4 * ha) * 60)
        set = midnight.addingTimeInterval((noonMin + 4 * ha) * 60)
    }

    static let vilnius = CLLocationCoordinate2D(latitude: 54.69, longitude: 25.28)
}

/// "auto" = pagal saulę, "day", "night".
func isNightNow(mode: String, coordinate: CLLocationCoordinate2D?) -> Bool {
    switch mode {
    case "day": return false
    case "night": return true
    default:
        let t = SunTimes(coordinate: coordinate ?? SunTimes.vilnius)
        let now = Date()
        return now < t.rise || now > t.set
    }
}
