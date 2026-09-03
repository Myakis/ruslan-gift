import ServiceManagement

/// Registers/unregisters the app itself (not a separate helper) as a login item,
/// via the modern `SMAppService` API — no extra entitlement needed, just the
/// app's own decision at runtime.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status == .enabled else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}
