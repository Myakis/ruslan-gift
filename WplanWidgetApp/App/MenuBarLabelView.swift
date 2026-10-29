import SwiftUI
import WplanCore

/// Drives the menu-bar icon itself — reads the same `WidgetSnapshot` the widget
/// does (cheap: just a local UserDefaults read, no network) and re-renders every
/// 15s so the progress ring visibly advances, independent of how often the snapshot
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

/// Menu-bar look: the brand icon, a VPN alert badge when needed, and a progress
/// ring toward the scheduled finish while the day is running.
struct MenuBarLabelView: View {
    @StateObject private var status = MenuBarStatusModel()

    private var vpnStatus: VPNNetworkChecker.Status {
        status.snapshot?.vpnStatus ?? .disconnected
    }

    private var isRunning: Bool? {
        status.snapshot?.isStart.map { !$0 }
    }

    /// Same formula as the widget's ring: start → scheduled finish.
    private var progressFraction: Double? {
        guard vpnStatus == .connected, isRunning == true,
              let startedAt = status.snapshot?.startedAt,
              let finishAt = status.snapshot?.scheduledFinishAt,
              finishAt > startedAt else { return nil }
        let fraction = status.now.timeIntervalSince(startedAt) / finishAt.timeIntervalSince(startedAt)
        return min(max(fraction, 0), 1)
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

    /// `MenuBarExtra` keeps only one image and one text from its label, dropping
    /// shapes and any extra image — so the icon, VPN badge and progress ring are
    /// rasterized together into that single image.
    private var iconImage: NSImage? {
        let content = HStack(spacing: 4) {
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
            if let fraction = progressFraction {
                MenuBarProgressRing(fraction: fraction)
            }
        }
        .padding(2)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }

    var body: some View {
        if let iconImage {
            Image(nsImage: iconImage)
        } else {
            Image("MenuBarIcon").renderingMode(.original)
        }
    }
}

private struct MenuBarProgressRing: View {
    let fraction: Double
    private let lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.45), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.green, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .frame(width: 16, height: 16)
    }
}
