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

    @Test("German is the enabled German language, whatever its region")
    func enabledGerman() {
        var configuration = Configuration.default
        let german = LanguageConfig(
            code: LanguageCode("de-DE"), displayName: "German", localeRules: [], enabled: true)
        configuration.languages = [.english, german]
        #expect(configuration.germanLanguage == german)
    }

    @Test("with no German enabled, German is Swiss Standard German")
    func fallbackGerman() {
        var configuration = Configuration.default
        let german = LanguageConfig(
            code: LanguageCode("de-AT"), displayName: "Austrian", localeRules: [], enabled: false)
        configuration.languages = [.english, german]
        #expect(configuration.germanLanguage == .swissGerman)
    }
}
