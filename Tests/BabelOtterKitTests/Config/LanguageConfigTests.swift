import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Languages are configuration, not code")
struct LanguageConfigTests {

    @Test("a language code is case-insensitive and stores lowercased")
    func codeNormalises() {
        #expect(LanguageCode("DE-CH") == LanguageCode("de-ch"))
        #expect(LanguageCode("DE-CH").rawValue == "de-ch")
    }

    @Test("a language code ignores surrounding whitespace, as a hand-edited file may carry it")
    func codeTrims() {
        #expect(LanguageCode("  de-CH \n") == LanguageCode("de-ch"))
    }

    @Test("the base subtag drops the region")
    func baseSubtag() {
        #expect(LanguageCode("de-CH").baseSubtag == LanguageCode("de"))
        #expect(LanguageCode("en").baseSubtag == LanguageCode("en"))
    }

    @Test("de-CH ships its ß rule as data, not as a special case in code")
    func swissGermanCarriesItsRule() {
        #expect(LanguageConfig.swissGerman.localeRules == [LocaleRule(replace: "ß", with: "ss")])
    }

    @Test("English ships with no locale rules")
    func englishHasNoRules() {
        #expect(LanguageConfig.english.localeRules.isEmpty)
    }

    @Test("English and de-CH are the enabled defaults")
    func shippedDefaults() {
        let enabled = LanguageConfig.shippedDefaults.filter(\.enabled).map(\.code)
        #expect(enabled == [LanguageCode("en"), LanguageCode("de-ch")])
    }

    @Test("French and Italian ship switched off, with their address forms and no rules (#81)")
    func frenchAndItalianShipOff() {
        #expect(LanguageConfig.shippedDefaults.map(\.code)
            == ["en", "de-ch", "fr", "it", "es"].map(LanguageCode.init))
        #expect(!LanguageConfig.french.enabled)
        #expect(!LanguageConfig.italian.enabled)
        #expect(LanguageConfig.french.addressForms == AddressForms(formal: "vous", informal: "tu"))
        #expect(LanguageConfig.italian.addressForms == AddressForms(formal: "Lei", informal: "tu"))
        #expect(LanguageConfig.french.localeRules.isEmpty)
        #expect(LanguageConfig.italian.localeRules.isEmpty)
    }

    @Test("Spanish ships switched off, with usted and tu and no rules (#132)")
    func spanishShipsOff() {
        #expect(!LanguageConfig.spanish.enabled)
        #expect(LanguageConfig.spanish.code == LanguageCode("es"))
        #expect(LanguageConfig.spanish.displayName == "Spanish")
        #expect(LanguageConfig.spanish.addressForms == AddressForms(formal: "usted", informal: "t\u{00FA}"))
        #expect(LanguageConfig.spanish.localeRules.isEmpty)
        #expect(LanguageConfig.spanish.writingNotes == nil)
        #expect(LanguageConfig.spanish.correctionNotes?.contains("quiero que vengas") == true)
        #expect(LanguageConfig.spanish.correctionNotes?.contains("Latin America") == true)
    }

    @Test("a file with only Spanish gained is the one-language difference (#132)")
    func spanishAppendedToFileFromEightyOne() throws {
        var fourLanguages = Configuration.default
        fourLanguages.languages = [.english, .swissGerman, .french, .italian]
        let added = try #require(fourLanguages.addingMissingShippedLanguages())
        #expect(added.languages.count == 5)
        #expect(added.languages[4] == .spanish)
        #expect(added.languages[4].enabled == false)
    }

    @Test("a Spanish entry under any es code keeps the shipped one out (#132)", arguments: ["es", "es-ES", "es-419"])
    func ownSpanishKept(_ code: String) {
        var custom = Configuration.default
        let own = LanguageConfig(
            code: LanguageCode(code), displayName: "Mine", localeRules: [], enabled: true)
        custom.languages = [.english, .swissGerman, .french, .italian, own]
        #expect(custom.addingMissingShippedLanguages() == nil)
    }

    @Test("a hand-written Spanish entry without notes takes the shipped ones and keeps its own settings")
    func handWrittenSpanish() throws {
        let json = #"""
            {"code": "es", "displayName": "Espanol", "localeRules": [], "enabled": true,
             "addressForms": {"formal": "usted", "informal": "tu"}}
            """#
        let language = try JSONDecoder().decode(LanguageConfig.self, from: Data(json.utf8))
        #expect(language.correctionNotes == LanguageConfig.spanish.correctionNotes)
        #expect(language.enabled)
        #expect(language.displayName == "Espanol")
        #expect(language.addressForms == AddressForms(formal: "usted", informal: "tu"))
        #expect(language.writingNotes == nil)
        // Saved again, the file keeps its shape: shipped notes are not written.
        let written = String(decoding: try JSONEncoder().encode(language), as: UTF8.self)
        #expect(!written.contains("correctionNotes"))
    }

    @Test("a file without French and Italian gains them, switched off, after its own languages")
    func missingShippedLanguagesAppended() throws {
        var twoLanguages = Configuration.default
        twoLanguages.languages = [.english, .swissGerman]
        let added = try #require(twoLanguages.addingMissingShippedLanguages())
        #expect(added.languages.map(\.code) == ["en", "de-ch", "fr", "it", "es"].map(LanguageCode.init))
        #expect(added.languages.filter(\.enabled).map(\.code) == [LanguageCode("en"), LanguageCode("de-ch")])
        #expect(added.languages[2] == .french)
        #expect(added.languages[3] == .italian)
        #expect(added.languages[4] == .spanish)
        // Only the languages change.
        var withoutLanguages = added
        withoutLanguages.languages = twoLanguages.languages
        #expect(withoutLanguages == twoLanguages)
    }

    @Test("a language sharing the base code counts as present; nothing missing gives nil")
    func missingShippedLanguagesBaseCode() throws {
        var custom = Configuration.default
        let swissFrench = LanguageConfig(
            code: LanguageCode("fr-CH"), displayName: "Swiss French", localeRules: [], enabled: true)
        let german = LanguageConfig(
            code: LanguageCode("de"), displayName: "German", localeRules: [], enabled: true)
        custom.languages = [swissFrench, .english, german]
        let added = try #require(custom.addingMissingShippedLanguages())
        #expect(added.languages.map(\.code) == ["fr-ch", "en", "de", "it", "es"].map(LanguageCode.init))
        #expect(added.addingMissingShippedLanguages() == nil)
        #expect(Configuration.default.addingMissingShippedLanguages() == nil)
    }

    @Test("an appended language is switched off even if the shipped one were on")
    func appendedAreOff() throws {
        var onlyFrench = Configuration.default
        onlyFrench.languages = [LanguageConfig.french]
        let added = try #require(onlyFrench.addingMissingShippedLanguages())
        // English and de-CH ship enabled, but are appended off like any other.
        #expect(added.languages.filter(\.enabled).isEmpty)
    }

    @Test("a language added purely as data round-trips through Codable")
    func addedByConfigurationAlone() throws {
        let french = LanguageConfig(
            code: LanguageCode("fr"),
            displayName: "French",
            localeRules: [LocaleRule(replace: "oe", with: "œ")],
            enabled: true
        )
        let data = try JSONEncoder().encode(french)
        #expect(try JSONDecoder().decode(LanguageConfig.self, from: data) == french)
    }

    @Test("a code decoded from a hand-edited file is normalised too")
    func decodingNormalises() throws {
        let data = Data(#""DE-CH""#.utf8)
        #expect(try JSONDecoder().decode(LanguageCode.self, from: data) == LanguageCode("de-ch"))
    }

    @Test("a code encodes as a plain string, so the config file stays readable")
    func encodesAsPlainString() throws {
        let data = try JSONEncoder().encode(LanguageCode("de-CH"))
        #expect(String(decoding: data, as: UTF8.self) == #""de-ch""#)
    }
}
