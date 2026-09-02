import WplanCore

final class FakeNetworkAvailability: NetworkAvailabilityChecking, @unchecked Sendable {
    var isAvailable = true

    func isNetworkAvailable() async -> Bool { isAvailable }
}
