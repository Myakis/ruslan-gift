import WidgetKit
import SwiftUI
import WplanCore

/// "Кольцо дня" (design doc `1a`) + VPN states (design doc `3a`), reading the real
/// `WidgetSnapshot` the host app writes to the App Group container — see
/// `AutomationController` for the write side. The progress ring/elapsed-total text
/// come from `startedAt`/`scheduledFinishAt` (locally recorded + the configured
/// schedule) — the Wplan API itself exposes no real worked-hours value (see
/// WplanCore's foundation plan's Known Limitation), so this is an estimate, not a
/// server-verified duration.
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
        // Refresh every minute while a day is running, so the elapsed/progress text
        // keeps moving between the host app's own (much rarer) snapshot writes.
        let nextRefresh = entry.snapshot?.startedAt != nil
            ? Date().addingTimeInterval(60)
            : Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
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

    /// `nil` when running but we have no locally-recorded start/finish to estimate
    /// from (e.g. the day was started from the website itself, not this app).
    private var progressFraction: Double? {
        guard isRunning == true,
              let startedAt = entry.snapshot?.startedAt,
              let finishAt = entry.snapshot?.scheduledFinishAt,
              finishAt > startedAt else { return nil }
        let elapsed = entry.date.timeIntervalSince(startedAt)
        let total = finishAt.timeIntervalSince(startedAt)
        return min(max(elapsed / total, 0), 1)
    }

    /// Clock times at the ring's center — "08:14–16:14" — instead of a duration.
    private var startEndText: String? {
        guard let startedAt = entry.snapshot?.startedAt,
              let finishAt = entry.snapshot?.scheduledFinishAt else { return nil }
        return "\(Self.formatClock(startedAt))–\(Self.formatClock(finishAt))"
    }

    /// How long the day has been running, shown below the ring instead of inside it.
    private var elapsedText: String? {
        guard isRunning == true, let startedAt = entry.snapshot?.startedAt else { return nil }
        let elapsed = max(0, entry.date.timeIntervalSince(startedAt))
        return "Прошло: \(Self.formatDuration(elapsed))"
    }

    private static func formatClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        return "\(totalMinutes / 60):\(String(format: "%02d", totalMinutes % 60))"
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
                    if vpnStatus == .connected, isRunning == true, let fraction = progressFraction {
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    } else if vpnStatus == .connected, isRunning == true {
                        Circle()
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    } else if vpnStatus == .connecting {
                        Circle()
                            .trim(from: 0, to: 0.4)
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    }
                }
                if let startEndText {
                    Text(startEndText)
                        .font(.system(size: 11, weight: .medium))
                        .minimumScaleFactor(0.7)
                } else {
                    Image(systemName: iconName)
                        .foregroundStyle(vpnStatus == .connected ? .secondary : ringColor)
                }
            }
            .padding(6)
            if let elapsedText {
                Text(elapsedText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
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
