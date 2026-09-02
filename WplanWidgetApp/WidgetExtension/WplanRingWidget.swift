import WidgetKit
import SwiftUI
import WplanCore

/// "Кольцо дня" (design doc `1a`), now reading the real `WidgetSnapshot` the host
/// app writes to the App Group container — see `AutomationController` for the
/// write side. No worked-hours field: the Wplan API doesn't expose one (see
/// WplanCore's foundation plan's Known Limitation), so this shows only the
/// isStart/isFinished boolean state, not an elapsed-time ring fill.
private let appGroupIdentifier = "group.ru.itmo.wplanwidget"

struct WplanRingProvider: TimelineProvider {
    func placeholder(in context: Context) -> WplanRingEntry {
        WplanRingEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WplanRingEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WplanRingEntry>) -> Void) {
        let entry = currentEntry()
        // The host app pushes a reload via WidgetCenter whenever it has fresher data;
        // this policy is just a safety net in case that never fires.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func currentEntry() -> WplanRingEntry {
        WplanRingEntry(date: Date(), snapshot: WidgetSnapshotStore.load(appGroupIdentifier: appGroupIdentifier))
    }
}

struct WplanRingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct WplanRingWidgetView: View {
    let entry: WplanRingEntry

    private var isRunning: Bool? {
        // WidgetSnapshot.isStart: true means the *next* action is "start" (day not
        // running); false means the day is running (next action is "finish").
        entry.snapshot.map { !$0.isStart }
    }

    private var statusText: String {
        switch isRunning {
        case .some(true): return "День идёт"
        case .some(false): return "День не начат"
        case .none: return "Нет данных"
        }
    }

    private var updatedText: String {
        guard let updatedAt = entry.snapshot?.updatedAt else { return "" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "обновлено \(formatter.string(from: updatedAt))"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("ITMO")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                if isRunning == true {
                    Circle()
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                }
                Image(systemName: isRunning == true ? "checkmark" : "clock")
                    .foregroundStyle(.secondary)
            }
            .padding(6)
            Text(statusText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if !updatedText.isEmpty {
                Text(updatedText)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
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
