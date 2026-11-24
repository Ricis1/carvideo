import Foundation
import UserNotifications

// MARK: - Video tęsiasi nuo ten, kur sustojo

enum VideoProgress {
    private static let key = "videoProgress.v1"
    private static var all: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    /// Išsaugota vieta sekundėmis (0, jei nėra arba video beveik baigtas).
    static func position(for id: String) -> Double { all[id] ?? 0 }
    static func save(_ seconds: Double, for id: String, duration: Double? = nil) {
        var a = all
        if let duration, duration > 0, seconds > duration - 10 { a[id] = nil } else { a[id] = seconds }
        // Laikom tik 100 paskutinių įrašų.
        if a.count > 100 { a.removeValue(forKey: a.keys.first!) }
        all = a
    }
}

// MARK: - Parkavimo laikmatis (vietiniai priminimai)

enum ParkingTimer {
    private static let key = "parkingTimerEnd.v1"
    private static let ids = ["parking.10min", "parking.end"]

    static var end: Date? {
        let t = UserDefaults.standard.double(forKey: key)
        guard t > 0 else { return nil }
        let d = Date(timeIntervalSince1970: t)
        return d > Date() ? d : nil
    }

    /// Paleidžia laikmatį: priminimas likus 10 min ir kai laikas baigiasi.
    static func start(minutes: Int) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        cancel()
        let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        UserDefaults.standard.set(endDate.timeIntervalSince1970, forKey: key)
        if minutes > 11 {
            await add(id: ids[0], title: "Parkavimas baigsis po 10 min", body: "Laikas grįžti prie automobilio.", after: TimeInterval((minutes - 10) * 60))
        }
        await add(id: ids[1], title: "Parkavimo laikas baigėsi", body: "Pratęsk apmokėjimą arba patrauk automobilį.", after: TimeInterval(minutes * 60))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func add(id: String, title: String, body: String, after: TimeInterval) async {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, after), repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
    }
}
