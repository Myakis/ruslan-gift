import SwiftUI
import WplanCore

@main
struct WplanWidgetApp: App {
    @StateObject private var sniffer: WplanQuerySniffer
    @StateObject private var model: MenuBarModel
    @StateObject private var automation: AutomationController

    init() {
        let sniffer = WplanQuerySniffer(
            hashStore: PersistedQueryHashStore(appGroupIdentifier: MenuBarModel.appGroupIdentifier),
            credentialsStore: KeychainStore(service: MenuBarModel.keychainService)
        )
        _sniffer = StateObject(wrappedValue: sniffer)
        _model = StateObject(wrappedValue: MenuBarModel(hashRefresher: sniffer))
        _automation = StateObject(wrappedValue: AutomationController(
            appGroupIdentifier: MenuBarModel.appGroupIdentifier,
            hashRefresher: sniffer
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model, automation: automation, sniffer: sniffer)
        } label: {
            MenuBarLabelView()
        }
        .menuBarExtraStyle(.window)
    }
}
