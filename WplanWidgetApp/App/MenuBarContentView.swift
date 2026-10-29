import SwiftUI
import WplanCore

struct MenuBarContentView: View {
    @ObservedObject var model: MenuBarModel
    @ObservedObject var automation: AutomationController
    let sniffer: WplanQuerySniffer
    /// Settings used to be a separate `Window` scene — now it's just another
    /// screen inside the same popover, toggled in place, so the menu-bar icon
    /// stays the single entry point instead of spawning a second window.
    @State private var showSettings = false
    @StateObject private var status = MenuBarStatusModel()

    private var headline: String {
        switch model.vpnStatus {
        case .disconnected: return "VPN не подключён"
        case .connecting: return "Подключение к VPN…"
        case .connected:
            switch model.isRunningDay {
            case .some(true): return "День идёт"
            case .some(false): return "День не начат"
            case .none: return "Учётные данные сохранены"
            }
        }
    }

    private var subtitle: String? {
        if let buttonStateText = model.buttonStateText { return buttonStateText }
        if model.vpnStatus != .connected { return "Включите VPN — клик выполнится сам" }
        return nil
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Wplan \(version) (\(build))"
    }

    var body: some View {
        Group {
            if showSettings {
                settingsBody
            } else {
                menuBody
            }
        }
        .task {
            await model.refresh()
            if model.isLoggedIn { await model.checkButtonState() }
        }
    }

    private var settingsBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { showSettings = false }) {
                Label("Назад", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            SettingsView(automation: automation, sniffer: sniffer)
        }
        .padding(10)
        .frame(width: 340)
    }

    private var menuBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isLoggedIn {
                StatusCard(
                    eyebrow: "WPLAN · \(automation.isRunning ? "АВТО ВКЛ" : "АВТО ВЫКЛ")",
                    vpnStatus: model.vpnStatus,
                    dotColor: MenuBarStyle.vpnColor(model.vpnStatus, isRunning: model.isRunningDay),
                    headline: headline,
                    subtitle: subtitle,
                    onRefresh: {
                        Task {
                            await model.refresh()
                            await automation.refreshWidgetSnapshot()
                        }
                    }
                )

                VStack(spacing: 6) {
                    DayActionButton(
                        isRunning: model.isRunningDay == true,
                        startedAt: status.snapshot?.startedAt,
                        isLoading: automation.isPerformingManualAction || model.isCheckingButtonState
                    ) {
                        let isStart = model.isRunningDay != true
                        Task {
                            await automation.performManualClick(isStart: isStart)
                            await model.checkButtonState()
                            status.refresh()
                        }
                    }
                    if let manualActionText = automation.manualActionText {
                        Text(manualActionText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                    }
                }

                VStack(spacing: 2) {
                    MenuActionButton(
                        title: "Проверить статус дня",
                        systemImage: "checkmark.circle",
                        isLoading: model.isCheckingButtonState
                    ) {
                        Task {
                            await model.checkButtonState()
                            await automation.refreshWidgetSnapshot()
                        }
                    }
                }

                VStack(spacing: 2) {
                    MenuActionButton(title: "Настройки…", systemImage: "gearshape") {
                        showSettings = true
                    }
                    MenuActionButton(title: "Выйти из аккаунта", systemImage: "person.crop.circle.badge.minus") {
                        model.logout()
                    }
                }
            } else {
                LoginView(model: model)
            }

            Divider()

            HStack {
                Text(versionText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Выйти из Wplan")
            }
            .padding(.horizontal, 6)
        }
        .padding(10)
        .frame(width: 280)
    }
}
