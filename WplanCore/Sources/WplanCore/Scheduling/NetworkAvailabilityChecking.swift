public protocol NetworkAvailabilityChecking {
    func isNetworkAvailable() async -> Bool
}
