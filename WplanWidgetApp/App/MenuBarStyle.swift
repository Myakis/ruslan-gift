import SwiftUI
import WplanCore

/// Shared visual language for the popover — a subtle "card" grouping and icon
/// rows instead of the default flat button list, echoing the widget's look
/// (colored status dot, VPN capsule badge).
enum MenuBarStyle {
    static func vpnColor(_ status: VPNNetworkChecker.Status, isRunning: Bool?) -> Color {
        switch status {
        case .disconnected: return .red
        case .connecting: return .orange
        case .connected: return isRunning == true ? .green : .secondary
        }
    }
}

struct VPNBadge: View {
    let status: VPNNetworkChecker.Status

    private var color: Color {
        switch status {
        case .disconnected: return .red
        case .connecting: return .orange
        case .connected: return .green
        }
    }

    private var text: String {
        switch status {
        case .disconnected: return "VPN выкл."
        case .connecting: return "VPN…"
        case .connected: return "VPN"
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

/// The top summary block: eyebrow label + VPN badge, status dot + headline (with
/// an optional trailing refresh icon), subtitle.
struct StatusCard: View {
    let eyebrow: String
    let vpnStatus: VPNNetworkChecker.Status
    let dotColor: Color
    let headline: String
    let subtitle: String?
    var onRefresh: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                VPNBadge(status: vpnStatus)
            }
            HStack(spacing: 6) {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                Text(headline)
                    .font(.system(size: 14, weight: .semibold))
                if let onRefresh {
                    Spacer()
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Обновить статус")
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// An icon + label row button, filling the popover's width, with a subtle
/// hover/press background instead of the default macOS button chrome.
struct MenuRowButtonStyle: ButtonStyle {
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.06))
            )
            .contentShape(Rectangle())
    }
}

struct MenuActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .primary
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label(title, systemImage: systemImage)
                }
            }
        }
        .buttonStyle(MenuRowButtonStyle(tint: tint))
        .disabled(isLoading)
    }
}

/// The popover's primary action. Starting is a plain click; finishing needs a
/// ~1s press-and-hold (a fill sweeps across while held), so a stray click can't
/// end the day.
struct DayActionButton: View {
    let isRunning: Bool
    let startedAt: Date?
    var isLoading = false
    let action: () -> Void

    @State private var holdProgress: CGFloat = 0
    private static let holdDuration: Double = 1.0
    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        if isRunning {
            finishButton
        } else {
            startButton
        }
    }

    private var startButton: some View {
        Button(action: action) {
            label(title: "Начать день", systemImage: "play.fill", detail: nil)
                .foregroundStyle(.white)
                .background(shape.fill(Color.green.opacity(0.85)))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var finishButton: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            label(title: "Завершить день", systemImage: "stop.fill", detail: finishDetail(now: context.date))
                .foregroundStyle(.red)
                .background {
                    ZStack(alignment: .leading) {
                        shape.fill(Color.red.opacity(0.14))
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.red.opacity(0.28))
                                .frame(width: geo.size.width * holdProgress)
                        }
                    }
                    .clipShape(shape)
                }
                .contentShape(shape)
        }
        .onLongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 24) {
            holdProgress = 0
            action()
        } onPressingChanged: { isPressing in
            guard !isLoading else { return }
            withAnimation(isPressing ? .linear(duration: Self.holdDuration) : .easeOut(duration: 0.2)) {
                holdProgress = isPressing ? 1 : 0
            }
        }
        .allowsHitTesting(!isLoading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .help("Удерживайте, чтобы завершить рабочий день")
    }

    private func finishDetail(now: Date) -> String {
        guard let startedAt else { return "удерживайте" }
        let minutes = max(0, Int(now.timeIntervalSince(startedAt) / 60))
        return "\(minutes / 60):\(String(format: "%02d", minutes % 60)) · удерживайте"
    }

    private func label(title: String, systemImage: String, detail: String?) -> some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 6)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .opacity(0.8)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 38)
    }
}
