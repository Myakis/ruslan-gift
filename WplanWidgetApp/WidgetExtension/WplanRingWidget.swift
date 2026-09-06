import WidgetKit
import SwiftUI
import AppIntents
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
    @Environment(\.widgetFamily) private var family
    let entry: WplanRingEntry

    /// `false` only for the gallery placeholder / a fresh install that has never
    /// written a snapshot yet — distinct from a real, confirmed VPN-disconnected
    /// reading, which also has `snapshot != nil`. Without this, both cases render
    /// identically red, which reads as "something is broken" even when nothing
    /// has actually been checked yet.
    private var hasData: Bool {
        entry.snapshot != nil
    }

    /// Today isn't in the configured schedule — the host app skips the VPN/Wplan
    /// check entirely on such days (see `AutomationController.refreshWidgetSnapshot`),
    /// so this takes priority over every other state below.
    private var isRestDay: Bool {
        entry.snapshot?.isRestDay ?? false
    }

    private var vpnStatus: VPNNetworkChecker.Status {
        entry.snapshot?.vpnStatus ?? .disconnected
    }

    /// WidgetSnapshot.isStart: true means the *next* action is "start" (day not
    /// running); false means the day is running (next action is "finish").
    private var isRunning: Bool? {
        entry.snapshot?.isStart.map { !$0 }
    }

    /// The Wplan API's own button state can't tell "never started today" apart
    /// from "already finished today" — `finishedAt` is our own reliable signal
    /// for the latter (see `DayState.autoStartSuppressedToday`).
    private var isFinished: Bool {
        guard isRunning == false, let finishedAt = entry.snapshot?.finishedAt else { return false }
        return Calendar.current.isDateInToday(finishedAt)
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

    /// Clock times — "08:14–16:14" — instead of a duration.
    private var startEndText: String? {
        guard let startedAt = entry.snapshot?.startedAt,
              let finishAt = entry.snapshot?.scheduledFinishAt else { return nil }
        return "\(Self.formatClock(startedAt))–\(Self.formatClock(finishAt))"
    }

    private var startClockText: String? {
        entry.snapshot?.startedAt.map(Self.formatClock)
    }

    private var finishClockText: String? {
        entry.snapshot?.scheduledFinishAt.map(Self.formatClock)
    }

    /// How long the day has been running.
    private var elapsedText: String? {
        guard isRunning == true, let startedAt = entry.snapshot?.startedAt else { return nil }
        let elapsed = max(0, entry.date.timeIntervalSince(startedAt))
        return Self.formatDuration(elapsed)
    }

    /// The actual configured span (start → scheduled finish) — not hardcoded to
    /// 8h, since `autoCalculateEightHours` off lets the user pick any duration.
    private var totalDurationText: String? {
        guard let startedAt = entry.snapshot?.startedAt,
              let finishAt = entry.snapshot?.scheduledFinishAt,
              finishAt > startedAt else { return nil }
        return Self.formatDuration(finishAt.timeIntervalSince(startedAt))
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
        guard !isRestDay else { return .secondary }
        guard hasData else { return .secondary }
        switch vpnStatus {
        case .disconnected: return .red
        case .connecting: return .orange
        case .connected:
            if isRunning == true { return .green }
            return isFinished ? .blue : .secondary
        }
    }

    private var statusText: String {
        guard !isRestDay else { return "Выходной" }
        guard hasData else { return "Нет данных" }
        switch vpnStatus {
        case .disconnected: return "VPN выкл."
        case .connecting: return "Подключение…"
        case .connected:
            if isFinished { return "День завершён" }
            switch isRunning {
            case .some(true): return "День идёт"
            case .some(false): return "День не начат"
            case .none: return "Нет данных"
            }
        }
    }

    private var mediumHeadline: String {
        guard !isRestDay else { return "Выходной" }
        guard hasData else { return "Нет данных" }
        switch vpnStatus {
        case .disconnected: return "VPN не подключён"
        case .connecting: return "Подключение к VPN…"
        case .connected: return statusText
        }
    }

    private var mediumSubtitle: String? {
        guard !isRestDay else { return "Сегодня не рабочий день по расписанию" }
        guard hasData else { return "Откройте Wplan хотя бы раз, чтобы виджет начал получать данные" }
        switch vpnStatus {
        case .disconnected, .connecting:
            return "Включите VPN — клик выполнится сам"
        case .connected:
            if isRunning == true, let startClockText {
                return "начат в \(startClockText) · авто"
            }
            return nil
        }
    }

    private var updatedText: String {
        guard let updatedAt = entry.snapshot?.updatedAt else { return "" }
        return "обновлено \(Self.formatClock(updatedAt))"
    }

    private var iconName: String {
        guard !isRestDay else { return "moon.zzz" }
        guard hasData else { return "questionmark.circle" }
        switch vpnStatus {
        case .disconnected: return "wifi.slash"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .connected:
            if isRunning == true { return "checkmark" }
            return isFinished ? "checkmark.seal" : "clock"
        }
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumBody
            default:
                compactBody
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Compact (systemSmall)

    private var compactBody: some View {
        VStack(spacing: 4) {
            Text("WPLAN")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            ring(diameter: 74, lineWidth: 6) {
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
                Text("Прошло: \(elapsedText)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if isFinished {
                resetButton
            } else if !updatedText.isEmpty {
                Text(updatedText)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    // MARK: - Wide (systemMedium)

    private var mediumBody: some View {
        HStack(spacing: 16) {
            ring(diameter: 76, lineWidth: 7) {
                if isRestDay {
                    Image(systemName: iconName)
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 1) {
                        Text(elapsedText ?? "—")
                            .font(.system(size: 18, weight: .semibold))
                        Text("из \(totalDurationText ?? "8:00")")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("WPLAN")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !isRestDay {
                        Text("VPN")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ringColor.opacity(0.2))
                            .foregroundStyle(ringColor)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Circle().fill(ringColor).frame(width: 7, height: 7)
                    Text(mediumHeadline)
                        .font(.system(size: 14, weight: .semibold))
                }

                if let mediumSubtitle {
                    Text(mediumSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if isFinished {
                    resetButton
                }

                if vpnStatus == .connected, let fraction = progressFraction {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule().fill(ringColor).frame(width: geo.size.width * CGFloat(fraction))
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        Text(startClockText ?? "")
                        Spacer()
                        if let finishClockText {
                            Text("завершение \(finishClockText)")
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if !updatedText.isEmpty {
                    Text(updatedText)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
    }

    // MARK: - Reset button (isFinished only)

    private var resetButton: some View {
        Button(intent: ResetDayIntent()) {
            Label("Начать заново", systemImage: "arrow.counterclockwise")
                .font(.system(size: 10, weight: .medium))
        }
        .buttonStyle(.bordered)
        .tint(.blue)
        .controlSize(.mini)
    }

    // MARK: - Shared ring

    @ViewBuilder
    private func ring(diameter: CGFloat, lineWidth: CGFloat, @ViewBuilder center: () -> some View) -> some View {
        ZStack {
            if isRestDay {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)
            } else if !hasData || vpnStatus == .disconnected {
                Circle()
                    .stroke(ringColor.opacity(0.5), style: StrokeStyle(lineWidth: lineWidth, dash: [4, 4]))
            } else {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)
                if vpnStatus == .connected, isRunning == true, let fraction = progressFraction {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                } else if vpnStatus == .connected, isRunning == true {
                    Circle()
                        .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                } else if vpnStatus == .connecting {
                    Circle()
                        .trim(from: 0, to: 0.4)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
            center()
        }
        .frame(width: diameter, height: diameter)
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct WplanWidgetBundle: WidgetBundle {
    var body: some Widget {
        WplanRingWidget()
    }
}
