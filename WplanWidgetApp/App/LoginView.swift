import SwiftUI

struct LoginView: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Вход в Wplan")
                    .font(.headline)
                Spacer()
                VPNBadge(status: model.vpnStatus)
            }

            TextField("Логин", text: $model.username)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isLoggingIn)

            SecureField("Пароль", text: $model.password)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isLoggingIn)
                .onSubmit { Task { await model.login() } }

            if let error = model.loginErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            MenuActionButton(
                title: "Войти",
                systemImage: "arrow.right.circle",
                tint: .green,
                isLoading: model.isLoggingIn
            ) {
                Task { await model.login() }
            }
            .disabled(model.username.isEmpty || model.password.isEmpty)
        }
    }
}
