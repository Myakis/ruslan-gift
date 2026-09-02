import Foundation
import WplanCore

/// Menu-bar view model: real login (via `WplanClient.login`, credentials persisted
/// to `KeychainStore`) and real VPN status. Not yet wired to `AutoclickScheduler`/
/// `WplanAutomationAgent` — that's the next step, once login is confirmed working
/// end to end against the real Wplan server.
@MainActor
final class MenuBarModel: ObservableObject {
    static let appGroupIdentifier = "group.ru.itmo.wplanwidget"

    @Published var isLoggedIn = false
    @Published var vpnStatusText = "Проверка…"

    @Published var username = ""
    @Published var password = ""
    @Published var isLoggingIn = false
    @Published var loginErrorMessage: String?

    private let keychain = KeychainStore(service: "ru.itmo.wplanwidget")
    private let vpnChecker = VPNNetworkChecker()
    private let client: WplanClient

    init() {
        let session = WplanSessionFactory.makeSession(appGroupIdentifier: Self.appGroupIdentifier)
        client = WplanClient(session: session)
    }

    func refresh() async {
        isLoggedIn = (try? keychain.load()) != nil
        let available = await vpnChecker.isNetworkAvailable()
        vpnStatusText = available ? "VPN: подключён, Wplan доступен" : "VPN: недоступен"
    }

    func login() async {
        guard !username.isEmpty, !password.isEmpty else {
            loginErrorMessage = "Введите логин и пароль"
            return
        }
        isLoggingIn = true
        loginErrorMessage = nil
        defer { isLoggingIn = false }

        do {
            try await client.login(username: username, password: password)
            try keychain.save(WplanCredentials(username: username, password: password))
            password = ""
            isLoggedIn = true
        } catch {
            let nsError = error as NSError
            loginErrorMessage = "Не удалось войти: [\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)"
        }
    }

    func logout() {
        try? keychain.delete()
        isLoggedIn = false
    }
}
