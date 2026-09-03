import SwiftUI
import WplanCore

/// Drives the menu-bar icon itself — reads the same `WidgetSnapshot` the widget
/// does (cheap: just a local UserDefaults read, no network) and re-renders every
/// 15s so the elapsed time visibly ticks, independent of how often the snapshot
/// itself gets refreshed by `AutomationController`.
@MainActor
final class MenuBarStatusModel: ObservableObject {
    @Published private(set) var snapshot: WidgetSnapshot?
    @Published private(set) var now = Date()
    private var refreshTask: Task<Void, Never>?

    init() {
        refresh()
        refreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self.refresh()
            }
        }
    }

    func refresh() {
        snapshot = WidgetSnapshotStore.load(appGroupIdentifier: MenuBarModel.appGroupIdentifier)
        now = Date()
    }
}

/// Design doc screen `1b`'s menu-bar look: a colored status dot + a monospaced
/// elapsed timer while the day is running, falling back to a plain icon otherwise.
struct MenuBarLabelView: View {
    @StateObject private var status = MenuBarStatusModel()

    private var vpnStatus: VPNNetworkChecker.Status {
        status.snapshot?.vpnStatus ?? .disconnected
    }

    private var isRunning: Bool? {
        status.snapshot?.isStart.map { !$0 }
    }

    private var elapsedText: String? {
        guard vpnStatus == .connected, isRunning == true, let startedAt = status.snapshot?.startedAt else { return nil }
        let elapsedMinutes = max(0, Int(status.now.timeIntervalSince(startedAt) / 60))
        return "\(elapsedMinutes / 60):\(String(format: "%02d", elapsedMinutes % 60))"
    }

    /// The brand icon carries its own (always-green) dot, so it only needs an
    /// overlay badge when something's actually worth flagging — a clean VPN
    /// connection doesn't need decoration.
    private var alertBadgeColor: Color? {
        switch vpnStatus {
        case .disconnected: return .red
        case .connecting: return .orange
        case .connected: return nil
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon")
                .renderingMode(.original)
                .opacity(vpnStatus == .disconnected ? 0.5 : 1)
                .overlay(alignment: .topTrailing) {
                    if let alertBadgeColor {
                        Circle()
                            .fill(alertBadgeColor)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
            if let elapsedText {
                Text(elapsedText)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }
}
