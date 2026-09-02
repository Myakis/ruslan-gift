import SwiftUI

@main
struct WplanWidgetApp: App {
    @StateObject private var model = MenuBarModel()
    @StateObject private var automation = AutomationController(appGroupIdentifier: MenuBarModel.appGroupIdentifier)

    var body: some Scene {
        MenuBarExtra("Wplan", systemImage: "clock") {
            MenuBarContentView(model: model, automation: automation)
        }
        .menuBarExtraStyle(.window)

        Window("Настройки Wplan", id: "settings") {
            SettingsView(automation: automation)
        }
    }
}
