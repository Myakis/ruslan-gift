import Foundation
import WplanCore

/// Turns any error from a WplanCore call into a readable, copy-selectable string
/// for the popover — used by MenuBarModel and AutomationController alike so the
/// exact server response (GraphQL error text, HTTP status + body) is diagnosable
/// without opening Console.app.
func describeWplanError(_ error: Error) -> String {
    if let clientError = error as? GraphQLClient.ClientError {
        switch clientError {
        case .invalidResponse:
            return "неожиданный/пустой ответ сервера"
        case .http(let status, let body):
            return "HTTP \(status) — \(body)"
        case .graphQL(let messages):
            return messages.joined(separator: "; ")
        }
    }
    let nsError = error as NSError
    return "[\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)"
}
