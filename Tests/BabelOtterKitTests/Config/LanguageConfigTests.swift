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
