import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: MenuBarModel
    @ObservedObject var automation: AutomationController
    @Environment(\.openWindow) private var openWindow

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isLoggedIn {
                StatusCard(
                    eyebrow: "WPLAN · \(automation.isRunning ? "АВТО ВКЛ" : "АВТО ВЫКЛ")",
                    vpnStatus: model.vpnStatus,
                    dotColor: MenuBarStyle.vpnColor(model.vpnStatus, isRunning: model.isRunningDay),
                    headline: headline,
                    subtitle: subtitle
                )

                VStack(spacing: 2) {
                    MenuActionButton(title: "Обновить", systemImage: "arrow.clockwise") {
                        Task {
                            await model.refresh()
                            await automation.refreshWidgetSnapshot()
                        }
                    }
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
                    MenuActionButton(
                        title: model.isRunningDay == true ? "Завершить" : "Начать",
                        systemImage: model.isRunningDay == true ? "stop.circle" : "play.circle",
                        tint: model.isRunningDay == true ? .red : .green,
                        isLoading: automation.isPerformingManualAction
                    ) {
                        let isStart = model.isRunningDay != true
                        Task {
                            await automation.performManualClick(isStart: isStart)
                            await model.checkButtonState()
                        }
                    }
                    if let manualActionText = automation.manualActionText {
                        Text(manualActionText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                    }
                }

                VStack(spacing: 2) {
                    MenuActionButton(title: "Настройки…", systemImage: "gearshape") {
                        openWindow(id: "settings")
                    }
                    MenuActionButton(title: "Выйти из аккаунта", systemImage: "person.crop.circle.badge.minus") {
                        model.logout()
                    }
                }
            } else {
                LoginView(model: model)
            }

            Divider()

            MenuActionButton(title: "Выход", systemImage: "xmark.circle") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 280)
        .task {
            await model.refresh()
            if model.isLoggedIn { await model.checkButtonState() }
        }
    }
}
