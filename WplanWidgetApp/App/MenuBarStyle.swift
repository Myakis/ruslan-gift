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
