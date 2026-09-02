import SwiftUI

struct LoginView: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Вход в Wplan")
                .font(.headline)

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

            Button {
                Task { await model.login() }
            } label: {
                if model.isLoggingIn {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Войти")
                }
            }
            .disabled(model.isLoggingIn || model.username.isEmpty || model.password.isEmpty)

            Text(model.vpnStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
