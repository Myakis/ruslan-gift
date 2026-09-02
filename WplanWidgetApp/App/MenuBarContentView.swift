import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.isLoggedIn ? "Учётные данные сохранены" : "Не авторизован")
                .font(.headline)
            Text(model.vpnStatusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button("Обновить") {
                Task { await model.refresh() }
            }
            Button("Выход") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
        .task { await model.refresh() }
    }
}
