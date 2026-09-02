import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: MenuBarModel
    @ObservedObject var automation: AutomationController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isLoggedIn {
                Text("Учётные данные сохранены")
                    .font(.headline)
                Text(model.vpnStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(automation.isRunning ? "Автоматизация: включена" : "Автоматизация: выключена")
                    .font(.caption)
                    .foregroundStyle(automation.isRunning ? .green : .secondary)

                Divider()

                Button("Обновить") {
                    Task {
                        await model.refresh()
                        await automation.refreshWidgetSnapshot()
                    }
                }

                Button {
                    Task {
                        await model.checkButtonState()
                        await automation.refreshWidgetSnapshot()
                    }
                } label: {
                    if model.isCheckingButtonState {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Проверить статус дня")
                    }
                }
                .disabled(model.isCheckingButtonState)

                if let buttonStateText = model.buttonStateText {
                    Text(buttonStateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Divider()

                HStack {
                    Button("Начать сейчас") {
                        Task { await automation.performManualClick(isStart: true) }
                    }
                    Button("Завершить сейчас") {
                        Task { await automation.performManualClick(isStart: false) }
                    }
                }
                .disabled(automation.isPerformingManualAction)

                if automation.isPerformingManualAction {
                    ProgressView().controlSize(.small)
                } else if let manualActionText = automation.manualActionText {
                    Text(manualActionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Divider()

                Button("Настройки…") {
                    openWindow(id: "settings")
                }
                Button("Выйти из аккаунта") {
                    model.logout()
                }
            } else {
                LoginView(model: model)
            }

            Divider()

            Button("Выход") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
        .task { await model.refresh() }
    }
}
