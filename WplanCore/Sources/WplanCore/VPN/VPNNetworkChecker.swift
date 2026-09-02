import Foundation

/// Real `NetworkAvailabilityChecking` implementation: checks for an active VPN-style
/// network interface, then confirms Wplan itself is actually reachable over it.
/// Matches the spec's "детект VPN — наличие корпоративного сетевого интерфейса/маршрута
/// + пинг внутреннего хоста" — the interface check alone can't tell us the tunnel
/// actually routes to Wplan, so both checks run.
public final class VPNNetworkChecker: NetworkAvailabilityChecking {
    /// The three states the design doc's screen `3a` distinguishes visually. `connecting`
    /// means the tunnel interface is up but Wplan isn't answering yet — this could be a
    /// tunnel still establishing its route, or a genuine problem; we can't tell those
    /// apart from here, so it's an honest "in between" rather than a fake progress state.
    public enum Status: String, Codable, Equatable {
        case connected
        case connecting
        case disconnected
    }

    /// Interface name prefixes macOS uses for VPN tunnels (utun: IKEv2/WireGuard/Network
    /// Extension tunnels, ppp: legacy PPTP/L2TP, ipsec: IPSec).
    private static let vpnInterfacePrefixes = ["utun", "ppp", "ipsec"]

    private let probeURL: URL
    private let session: URLSession
    private let probeTimeout: TimeInterval

    public init(
        probeURL: URL = WplanClient.defaultBaseURL,
        session: URLSession = .shared,
        probeTimeout: TimeInterval = 5
    ) {
        self.probeURL = probeURL
        self.session = session
        self.probeTimeout = probeTimeout
    }

    public func currentStatus() async -> Status {
        guard Self.hasActiveVPNInterface() else { return .disconnected }
        return await canReachWplan() ? .connected : .connecting
    }

    public func isNetworkAvailable() async -> Bool {
        await currentStatus() == .connected
    }

    /// Walks the local interface list (`getifaddrs`) looking for an "up" VPN-style interface.
    static func hasActiveVPNInterface() -> Bool {
        var addrsPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrsPointer) == 0, let firstAddr = addrsPointer else { return false }
        defer { freeifaddrs(addrsPointer) }

        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let interface = current {
            let flags = Int32(interface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let name = String(cString: interface.pointee.ifa_name)
            if isUp && vpnInterfacePrefixes.contains(where: { name.hasPrefix($0) }) {
                return true
            }
            current = interface.pointee.ifa_next
        }
        return false
    }

    private func canReachWplan() async -> Bool {
        var request = URLRequest(url: probeURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = probeTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await session.data(for: request)
            // Any HTTP response (even 401/404) proves the tunnel actually routes to Wplan;
            // only a transport-level failure (timeout, no route, DNS failure) means "no VPN".
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }
}
