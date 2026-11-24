import ActivityKit
import WidgetKit
import SwiftUI

/// v10: užrakinto ekrano valdiklis. v17: pilnas Dynamic Island – posūkis, atstumas, greitis ir atvykimo laikas.
struct NavLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavActivityAttributes.self) { ctx in
            HStack(spacing: 12) {
                Image(systemName: ctx.state.turnSymbol ?? "location.north.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.turnLine(ctx.state)).font(.headline).lineLimit(1)
                    Text("\(ctx.attributes.destination) · \(ctx.state.arrival, style: .time)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text("\(ctx.state.minutesLeft) min").font(.title3.bold().monospacedDigit()).foregroundStyle(.green)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.6))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: ctx.state.turnSymbol ?? "location.north.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(.green).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let v = ctx.state.speedKmh {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(v)").font(.title2.bold().monospacedDigit()).foregroundStyle(v > (ctx.state.limitKmh ?? 999) ? .red : .white)
                            Text(ctx.state.limitKmh.map { "km/h · \($0)" } ?? "km/h").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Self.dist(ctx.state.turnDistance)).font(.title2.bold())
                        Text(ctx.state.turnText ?? ctx.attributes.destination).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(ctx.attributes.destination, systemImage: "flag.checkered").font(.caption).lineLimit(1)
                        Spacer()
                        Text("\(ctx.state.arrival, style: .time) · \(ctx.state.minutesLeft) min").font(.caption.bold()).foregroundStyle(.green)
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: ctx.state.turnSymbol ?? "location.north.fill").foregroundStyle(.green)
                    Text(Self.dist(ctx.state.turnDistance)).font(.caption.bold().monospacedDigit())
                }
            } compactTrailing: {
                Text("\(ctx.state.minutesLeft) min").font(.caption.bold().monospacedDigit()).foregroundStyle(.green)
            } minimal: {
                Image(systemName: ctx.state.turnSymbol ?? "location.north.fill").foregroundStyle(.green)
            }
            .keylineTint(.green)
        }
    }

    static func dist(_ m: Int?) -> String {
        guard let m else { return "—" }
        return m >= 1000 ? String(format: "%.1f km", Double(m) / 1000) : "\(m / 10 * 10) m"
    }
    static func turnLine(_ s: NavActivityAttributes.ContentState) -> String {
        guard let t = s.turnText else { return "Važiuojame" }
        return s.turnDistance != nil ? "\(dist(s.turnDistance)) · \(t)" : t
    }
}
