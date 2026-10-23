import Testing

@testable import BabelOtterKit

@Suite("Configuration answers which model and which German")
struct ConfigurationTests {

    @Test("a configured model is the one an action uses")
    func configuredModel() {
        var configuration = Configuration.default
        configuration.models[.explain] = "llama3.1:8b"
        #expect(configuration.model(for: .explain) == "llama3.1:8b")
        #expect(configuration.model(for: .translate) == Configuration.defaultModel)
    }

    @Test("an action with no configured model uses the default")
    func defaultModel() {
        var configuration = Configuration.default
        configuration.models = [:]
        #expect(configuration.model(for: .correct) == Configuration.defaultModel)
    }
}
