import WidgetKit
import SwiftUI

/// Static placeholder for the "кольцо дня" screen (design doc `1a`) — proves the
/// widget extension target builds and links against WplanCore, no live data yet.
/// Wiring this to `AutoclickScheduler`'s real state is a later plan (needs the
/// App Group-shared state the host app writes to).
struct WplanRingProvider: TimelineProvider {
    func placeholder(in context: Context) -> WplanRingEntry {
        WplanRingEntry(date: Date(), statusText: "День идёт", workedHoursText: "5:42")
    }

    func getSnapshot(in context: Context, completion: @escaping (WplanRingEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WplanRingEntry>) -> Void) {
        let entry = placeholder(in: context)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct WplanRingEntry: TimelineEntry {
    let date: Date
    let statusText: String
    let workedHoursText: String
}

struct WplanRingWidgetView: View {
    let entry: WplanRingEntry

    var body: some View {
        VStack(spacing: 4) {
            Text("ITMO")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: 0.71)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(entry.workedHoursText)
                    .font(.system(size: 18, weight: .medium))
            }
            .padding(6)
            Text(entry.statusText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct WplanRingWidget: Widget {
    let kind = "WplanRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WplanRingProvider()) { entry in
            WplanRingWidgetView(entry: entry)
        }
        .configurationDisplayName("Wplan")
        .description("Показывает статус рабочего дня в Wplan.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct WplanWidgetBundle: WidgetBundle {
    var body: some Widget {
        WplanRingWidget()
    }
}
