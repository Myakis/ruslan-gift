import Foundation

/// The shared App Group — `<TeamID>.com.wplanwidget.app`. Written into each
/// target's Info.plist at build time from `DEVELOPMENT_TEAM`, so building under
/// another Apple ID only needs a different team, not source edits.
public enum WplanAppGroup {
    public static let infoPlistKey = "WplanAppGroup"

    public static var identifier: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
              !value.isEmpty, !value.contains("$(")
        else {
            preconditionFailure("Info.plist has no resolved \(infoPlistKey) value")
        }
        return value
    }
}
