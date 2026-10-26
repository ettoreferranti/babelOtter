import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Model server: built-in or the user's own Ollama (#126)")
struct ModelServerTests {

    private func decode(_ json: String) throws -> Configuration {
        try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
    }

    private func encoded(_ configuration: Configuration) throws -> String {
        String(decoding: try JSONEncoder().encode(configuration), as: UTF8.self)
    }

    @Test("a new install uses the built-in server, on its own port")
    func newInstall() {
        #expect(Configuration.default.modelServer == .builtIn)
        #expect(Configuration.default.server == .builtIn)
        #expect(Configuration.default.endpoint == .builtIn)
        #expect(OllamaEndpoint.builtIn.host == "127.0.0.1")
        #expect(OllamaEndpoint.builtIn.port == 47_434)
    }

    @Test("a file from before #126 keeps the user's own Ollama, and stays without the key")
    func existingFile() throws {
        var configuration = Configuration.default
        configuration.modelServer = nil
        let decoded = try decode(try encoded(configuration))
        #expect(decoded.modelServer == nil)
        #expect(decoded.server == .own)
        #expect(decoded.endpoint == .loopback)
        #expect(!(try encoded(decoded)).contains("modelServer"))
    }

    @Test("each mode round-trips under a readable name", arguments: [
        (ModelServer.builtIn, #""modelServer":"builtIn""#),
        (ModelServer.own, #""modelServer":"own""#),
    ])
    func roundTrip(server: ModelServer, json: String) throws {
        var configuration = Configuration.default
        configuration.modelServer = server
        let text = try encoded(configuration)
        #expect(text.contains(json))
        #expect(try decode(text).server == server)
    }

    @Test("each mode names its endpoint and its display name")
    func endpoints() {
        #expect(ModelServer.builtIn.endpoint == .builtIn)
        #expect(ModelServer.own.endpoint == .loopback)
        #expect(ModelServer.builtIn.displayName == "Built-in")
        #expect(ModelServer.own.displayName == "My own Ollama")
    }

    @Test("an unknown mode is a decoding error, not a silent default")
    func unknownMode() throws {
        var text = try encoded(.default)
        text = text.replacingOccurrences(of: #""modelServer":"builtIn""#, with: #""modelServer":"cloud""#)
        #expect(throws: DecodingError.self) { try decode(text) }
    }
}
