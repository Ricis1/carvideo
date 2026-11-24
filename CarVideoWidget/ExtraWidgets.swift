import WidgetKit
import SwiftUI

// v9: daugiau valdiklių – visi savi, be markių logotipų.
@main
struct CarVideoWidgets: WidgetBundle {
    var body: some Widget {
        HomeWidget()
        YearProgressWidget()
        QuoteWidget()
        NavLiveActivity()   // v10
    }
}

struct DayEntry: TimelineEntry { let date: Date }
struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) { completion(DayEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 3, to: .now)!
        completion(Timeline(entries: [DayEntry(date: .now)], policy: .after(next)))
    }
}

struct YearProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YearProgress", provider: DayProvider()) { e in
            let cal = Calendar.current
            let y0 = cal.date(from: cal.dateComponents([.year], from: e.date))!
            let y1 = cal.date(byAdding: .year, value: 1, to: y0)!
            let p = e.date.timeIntervalSince(y0) / y1.timeIntervalSince(y0)
            VStack(alignment: .leading) {
                Text("\(cal.component(.year, from: e.date)) METAI").font(.caption2).opacity(0.75)
                Spacer()
                Text(String(format: "%.1f%%", p * 100)).font(.system(size: 30, weight: .light))
                ProgressView(value: p).tint(.white)
            }
            .foregroundStyle(.white)
            .containerBackground(LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom), for: .widget)
        }
        .configurationDisplayName("Metų progresas")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct QuoteWidget: Widget {
    static let quotes = ["Geriausias kelias – tas, kuriuo grįžti namo.", "Lėčiau važiuoji – daugiau pamatai.", "Kelionė prasideda ne nuo rakto, o nuo noro.", "Saugiai šiandien – dar daug kelionių rytoj.", "Kiekvienas kilometras – nauja istorija."]
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Quote", provider: DayProvider()) { e in
            VStack(alignment: .leading, spacing: 6) {
                Text("DIENOS MINTIS").font(.caption2).opacity(0.7)
                Text("„\(Self.quotes[Calendar.current.component(.day, from: e.date) % Self.quotes.count])“").font(.system(size: 17, weight: .light))
            }
            .foregroundStyle(.white)
            .containerBackground(Color(white: 0.1), for: .widget)
        }
        .configurationDisplayName("Dienos mintis")
        .supportedFamilies([.systemMedium])
    }
}
