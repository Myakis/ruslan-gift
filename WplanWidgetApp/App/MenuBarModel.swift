import Foundation
import WplanCore

/// Menu-bar view model: real login (via `WplanClient.login`, credentials persisted
/// to `KeychainStore`), real VPN status, and a read-only day-status check. Manual
/// start/finish clicks live on `AutomationController` instead (so they go through
/// the same scheduler that runs the automatic schedule, keeping its day-bookkeeping
/// in sync — see its doc comment).
@MainActor
final class MenuBarModel: ObservableObject {
    static let appGroupIdentifier = "group.com.wplanwidget.app"

    @Published var isLoggedIn = false
    @Published var vpnStatus: VPNNetworkChecker.Status = .disconnected
    @Published var buttonStateText: String?
    @Published var isRunningDay: Bool?
    @Published var isCheckingButtonState = false

    @Published var username = ""
    @Published var password = ""
    @Published var isLoggingIn = false
    @Published var loginErrorMessage: String?

    private let keychain = KeychainStore(service: "com.wplanwidget.app")
    private let vpnChecker = VPNNetworkChecker()
    private let client: WplanClient

    init() {
        let session = WplanSessionFactory.makeSession(appGroupIdentifier: Self.appGroupIdentifier)
        client = WplanClient(session: session)
    }

    func refresh() async {
        isLoggedIn = (try? keychain.load()) != nil
        vpnStatus = await vpnChecker.currentStatus()
    }

    func login() async {
        guard !username.isEmpty, !password.isEmpty else {
            loginErrorMessage = "Введите логин и пароль"
            return
        }
        username = Self.normalizeUsername(username)
        isLoggingIn = true
        loginErrorMessage = nil
        defer { isLoggingIn = false }

        do {
            try await client.login(username: username, password: password)
            try keychain.save(WplanCredentials(username: username, password: password))
            password = ""
            isLoggedIn = true
        } catch {
            loginErrorMessage = "Не удалось войти: \(describeWplanError(error))"
        }
    }

    /// Bare usernames (no domain) are typed most often — "test.t" is treated as
    /// short for the corporate login "test.t@office.lan". Any input that already
    /// has an "@" is left alone (someone using a different domain deliberately).
    private static func normalizeUsername(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") ? trimmed : "\(trimmed)@office.lan"
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
            isRunningDay = !state.isStart
            buttonStateText = state.isStart
                ? "День не начат (кнопка = «Начать»)"
                : "День уже идёт (кнопка = «Завершить»)"
        } catch {
            buttonStateText = "Ошибка: \(describeWplanError(error))"
        }
    }
}
