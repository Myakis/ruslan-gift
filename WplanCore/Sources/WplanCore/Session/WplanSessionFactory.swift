import Foundation

public enum WplanSessionFactory {
    /// - Parameter appGroupIdentifier: pass the app's App Group id (e.g. `"group.ru.itmo.wplanwidget"`)
    ///   so the host app, widget extension, and background scheduler share one cookie jar. Pass `nil`
    ///   in contexts without an App Group (tests, a CLI harness).
    public static func makeSession(appGroupIdentifier: String?) -> URLSession {
        let configuration = URLSessionConfiguration.default
        if let appGroupIdentifier {
            configuration.httpCookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: appGroupIdentifier)
        }
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration)
    }
}
