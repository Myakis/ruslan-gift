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
    @Published var buttonStateText: String?
    @Published var isCheckingButtonState = false

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
        } catch let error as GraphQLClient.ClientError {
            switch error {
            case .invalidResponse:
                loginErrorMessage = "Не удалось войти: неожиданный/пустой ответ сервера"
            case .http(let status):
                loginErrorMessage = "Не удалось войти: HTTP \(status)"
            case .graphQL(let messages):
                loginErrorMessage = "Не удалось войти: \(messages.joined(separator: "; "))"
            }
        } catch {
            let nsError = error as NSError
            loginErrorMessage = "Не удалось войти: [\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)"
        }
    }

    func logout() {
        try? keychain.delete()
        isLoggedIn = false
    }

    /// Sanity check that the session cookie from `login()` is actually reused —
    /// this is the thing that decides whether AutoclickScheduler can work at all.
    func checkButtonState() async {
        isCheckingButtonState = true
        defer { isCheckingButtonState = false }
        do {
            let state = try await client.fetchButtonState()
            buttonStateText = state.isStart
                ? "День не начат (кнопка = «Начать»)"
                : "День уже идёт (кнопка = «Завершить»)"
        } catch let error as GraphQLClient.ClientError {
            switch error {
            case .invalidResponse:
                buttonStateText = "Ошибка: неожиданный/пустой ответ сервера"
            case .http(let status):
                buttonStateText = "Ошибка: HTTP \(status)"
            case .graphQL(let messages):
                buttonStateText = "Ошибка: \(messages.joined(separator: "; "))"
            }
        } catch {
            let nsError = error as NSError
            buttonStateText = "Ошибка: [\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)"
        }
    }
}
