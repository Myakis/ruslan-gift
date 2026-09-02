import WidgetKit
import SwiftUI
import WplanCore

/// "Кольцо дня" (design doc `1a`) + VPN states (design doc `3a`), reading the real
/// `WidgetSnapshot` the host app writes to the App Group container — see
/// `AutomationController` for the write side. No worked-hours field: the Wplan API
/// doesn't expose one (see WplanCore's foundation plan's Known Limitation), so this
/// shows only the isStart/isFinished boolean state, not an elapsed-time ring fill.
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

    private var vpnStatus: VPNNetworkChecker.Status {
        entry.snapshot?.vpnStatus ?? .disconnected
    }

    /// WidgetSnapshot.isStart: true means the *next* action is "start" (day not
    /// running); false means the day is running (next action is "finish").
    private var isRunning: Bool? {
        entry.snapshot?.isStart.map { !$0 }
    }

    private var ringColor: Color {
        switch vpnStatus {
        case .disconnected: return .red
        case .connecting: return .orange
        case .connected: return isRunning == true ? .green : .secondary
        }
    }

    private var statusText: String {
        switch vpnStatus {
        case .disconnected: return "VPN выкл."
        case .connecting: return "Подключение…"
        case .connected:
            switch isRunning {
            case .some(true): return "День идёт"
            case .some(false): return "День не начат"
            case .none: return "Нет данных"
            }
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
                if vpnStatus == .disconnected {
                    Circle()
                        .stroke(ringColor.opacity(0.5), style: StrokeStyle(lineWidth: 6, dash: [4, 4]))
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                    if vpnStatus == .connected && isRunning == true {
                        Circle()
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    } else if vpnStatus == .connecting {
                        Circle()
                            .trim(from: 0, to: 0.4)
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    }
                }
                Image(systemName: iconName)
                    .foregroundStyle(vpnStatus == .connected ? .secondary : ringColor)
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

    private var iconName: String {
        switch vpnStatus {
        case .disconnected: return "wifi.slash"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .connected: return isRunning == true ? "checkmark" : "clock"
        }
    }
}

struct WplanRingWidget: Widget {
    let kind = "WplanRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WplanRingProvider()) { entry in
            WplanRingWidgetView(entry: entry)
        }
        .configurationDisplayName("Wplan")
        .description("Показывает статус VPN и рабочего дня в Wplan.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct WplanWidgetBundle: WidgetBundle {
    var body: some Widget {
        WplanRingWidget()
    }
}
