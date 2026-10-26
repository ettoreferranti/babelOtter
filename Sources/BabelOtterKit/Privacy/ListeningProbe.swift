import Foundation

/// Where Ollama's port is open, as macOS reports it (#73, `FR-ONB-04`).
public enum ListeningExposure: Sendable, Equatable {
    /// Only loopback addresses: this Mac alone can reach it.
    case loopbackOnly([String])
    /// At least one other address. `everywhere` for a wildcard (`*`,
    /// `0.0.0.0`, `::`): every network the Mac is on.
    case exposed([String], everywhere: Bool)
    /// Nothing reported: Ollama not running, or not visible. Never "safe".
    case unknown
}

/// Reads `lsof -nP -iTCP:<port> -sTCP:LISTEN -F n` output. The app runs
/// the tool; this only parses, so it is tested.
public enum ListeningProbe {

    /// The lines read, at most: a port has a handful of listeners.
    static let lineLimit = 64

    /// The arguments for the port lingoSwen talks to.
    public static func arguments(port: Int = OllamaEndpoint.defaultPort) -> [String] {
        ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-F", "n"]
    }

    /// The arguments for which processes listen on `port` (#126).
    public static func ownerArguments(port: Int) -> [String] {
        ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-F", "p"]
    }

    /// Each `p` line is a listening process's id.
    public static func owners(_ output: String) -> Set<Int32> {
        var pids: Set<Int32> = []
        for line in output.split(whereSeparator: \.isNewline).prefix(lineLimit) {
            guard line.first == "p" else { continue }
            if let pid = Int32(line.dropFirst()) { pids.insert(pid) }
        }
        return pids
    }

    /// Each `n` line is a listening address, `host:port`.
    public static func parse(_ output: String) -> ListeningExposure {
        var addresses: [String] = []
        for line in output.split(whereSeparator: \.isNewline).prefix(lineLimit) {
            guard line.first == "n" else { continue }
            let address = String(line.dropFirst())
            guard let colon = address.lastIndex(of: ":") else { continue }
            let host = String(address[..<colon])
            if !addresses.contains(host) { addresses.append(host) }
        }
        if addresses.isEmpty { return .unknown }
        var exposed: [String] = []
        var everywhere = false
        for host in addresses {
            if isLoopback(host) { continue }
            exposed.append(host)
            if isWildcard(host) { everywhere = true }
        }
        if exposed.isEmpty { return .loopbackOnly(addresses) }
        return .exposed(exposed, everywhere: everywhere)
    }

    static func isLoopback(_ host: String) -> Bool {
        if host == "[::1]" { return true }
        if host == "localhost" { return true }
        return host.hasPrefix("127.")
    }

    static func isWildcard(_ host: String) -> Bool {
        if host == "*" { return true }
        if host == "0.0.0.0" { return true }
        return host == "[::]"
    }
}
