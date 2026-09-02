import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isLoggedIn {
                Text("Учётные данные сохранены")
                    .font(.headline)
                Text(model.vpnStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                Button("Обновить") {
                    Task { await model.refresh() }
                }

                Button {
                    Task { await model.checkButtonState() }
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
