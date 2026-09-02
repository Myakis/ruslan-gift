import Foundation
import WplanCore

/// Skeleton menu-bar view model — real for the login/VPN status it shows, but not yet
/// wired to `AutoclickScheduler`/`WplanAutomationAgent` (that needs the login window
/// and settings UI from a later plan; this only proves the app target links WplanCore
/// correctly end to end).
@MainActor
final class MenuBarModel: ObservableObject {
    @Published var isLoggedIn = false
    @Published var vpnStatusText = "Проверка…"

    private let keychain = KeychainStore(service: "ru.itmo.wplanwidget")
    private let vpnChecker = VPNNetworkChecker()

    func refresh() async {
        isLoggedIn = (try? keychain.load()) != nil
        let available = await vpnChecker.isNetworkAvailable()
        vpnStatusText = available ? "VPN: подключён, Wplan доступен" : "VPN: недоступен"
    }
}
