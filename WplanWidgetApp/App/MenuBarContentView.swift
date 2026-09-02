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
