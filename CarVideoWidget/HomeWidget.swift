import WidgetKit
import SwiftUI

/// iPhone pradžios ekrano valdiklis „Važiuoti namo“.
/// Paspaudus atidaroma programėlė per carvideo://namo ir iškart pradedamas maršrutas namo.
struct HomeEntry: TimelineEntry { let date: Date }

struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry { HomeEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) { completion(HomeEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        completion(Timeline(entries: [HomeEntry(date: .now)], policy: .never))
    }
}

struct HomeWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "house.fill").font(.title).foregroundStyle(.white)
            Spacer()
            Text("Važiuoti").font(.caption).foregroundStyle(.white.opacity(0.8))
            Text("namo").font(.title2.bold()).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.05, green: 0.35, blue: 0.85), Color(red: 0.02, green: 0.12, blue: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "carvideo://namo"))
    }
}

struct HomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HomeWidget", provider: HomeProvider()) { _ in HomeWidgetView() }
            .configurationDisplayName("Važiuoti namo")
            .description("Vienu paspaudimu pradeda maršrutą namo.")
            .supportedFamilies([.systemSmall])
    }
}
