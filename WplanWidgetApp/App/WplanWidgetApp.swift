import SwiftUI

@main
struct WplanWidgetApp: App {
    @StateObject private var model = MenuBarModel()
    @StateObject private var automation = AutomationController(appGroupIdentifier: MenuBarModel.appGroupIdentifier)

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model, automation: automation)
        } label: {
            MenuBarLabelView()
        }
        .menuBarExtraStyle(.window)

        Window("Настройки Wplan", id: "settings") {
            SettingsView(automation: automation)
        }
    }
}
