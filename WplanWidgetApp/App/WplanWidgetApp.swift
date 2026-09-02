import SwiftUI

@main
struct WplanWidgetApp: App {
    @StateObject private var model = MenuBarModel()

    var body: some Scene {
        MenuBarExtra("Wplan", systemImage: "clock") {
            MenuBarContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
