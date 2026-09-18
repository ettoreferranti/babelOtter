import Testing
import Foundation
@testable import BabelOtterKit

/// NFR-P2/P3: babelOtter opens no non-loopback connection, ever. This type is
/// where that is enforced — a non-loopback endpoint is unrepresentable.
@Suite("OllamaEndpoint enforces loopback")
struct OllamaEndpointTests {

    @Test("accepts every loopback spelling", arguments: [
        "127.0.0.1", "localhost", "LOCALHOST", "::1", "[::1]", " 127.0.0.1 ",
    ])
    func acceptsLoopback(host: String) {
        #expect(OllamaEndpoint(host: host) != nil, "\(host) is loopback and must be accepted")
    }

    @Test("rejects everything that is not loopback", arguments: [
        "ollama.example.com",
        "0.0.0.0",                  // wildcard bind, NOT loopback
        "192.168.1.5",
        "10.0.0.1",
        "127.0.0.1.evil.example",   // prefix trap
        "evil-localhost.example",   // substring trap
        "localhost.evil.example",   // suffix trap
        "",
        "   ",
        "::",
    ])
    func rejectsNonLoopback(host: String) {
        #expect(OllamaEndpoint(host: host) == nil, "\(host) is not loopback and must be rejected")
    }

    @Test("rejects out-of-range ports", arguments: [0, -1, 65_536, 99_999])
    func rejectsInvalidPorts(port: Int) {
        #expect(OllamaEndpoint(host: "127.0.0.1", port: port) == nil)
    }

    @Test("accepts boundary ports", arguments: [1, 11_434, 65_535])
    func acceptsBoundaryPorts(port: Int) {
        #expect(OllamaEndpoint(host: "127.0.0.1", port: port) != nil)
    }

    @Test("defaults to Ollama's port")
    func defaultsToOllamaPort() throws {
        let endpoint = try #require(OllamaEndpoint(host: "127.0.0.1"))
        #expect(endpoint.port == 11_434)
    }

    @Test("OLLAMA_HOST is deliberately ignored")
    func ignoresOllamaHostEnvironment() {
        // A shell profile, a dotfile sync, or a hostile environment could point
        // OLLAMA_HOST at a remote server. Honouring it would send the user's
        // writing off the machine. babelOtter always talks to loopback.
        let hostile = [
            "OLLAMA_HOST": "https://ollama.example.com:443",
            "OLLAMA_ORIGINS": "*",
        ]
        #expect(OllamaEndpoint.resolved(ignoring: hostile) == .loopback)
    }

    @Test("builds an IPv4 base URL")
    func buildsIPv4URL() throws {
        let endpoint = try #require(OllamaEndpoint(host: "127.0.0.1", port: 11_434))
        #expect(endpoint.baseURL.absoluteString == "http://127.0.0.1:11434")
    }

    @Test("brackets IPv6 hosts in the URL")
    func bracketsIPv6() throws {
        let endpoint = try #require(OllamaEndpoint(host: "::1", port: 11_434))
        #expect(endpoint.baseURL.absoluteString == "http://[::1]:11434")
    }

    @Test("appends API paths without doubling separators", arguments: [
        "api/chat", "/api/chat",
    ])
    func appendsPaths(path: String) throws {
        let endpoint = try #require(OllamaEndpoint(host: "127.0.0.1"))
        #expect(endpoint.url(path: path).absoluteString == "http://127.0.0.1:11434/api/chat")
    }

    @Test("loopback constant is the IPv4 default")
    func loopbackConstant() {
        #expect(OllamaEndpoint.loopback.host == "127.0.0.1")
        #expect(OllamaEndpoint.loopback.port == 11_434)
    }
}
