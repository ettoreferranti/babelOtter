import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Choosing a target among three or more languages (#81)")
struct TargetChoiceTests {

    private let english = LanguageCode("en")
    private let german = LanguageCode("de-ch")
    private let french = LanguageCode("fr")
    private let italian = LanguageCode("it")

    private func enabling(_ codes: [LanguageCode]) -> Configuration {
        var configuration = Configuration.default
        for index in configuration.languages.indices {
            configuration.languages[index].enabled = codes.contains(configuration.languages[index].code)
        }
        return configuration
    }

    @Test("the menu offers the other enabled languages, in configuration order")
    func menuTargets() {
        let three = enabling([english, german, french])
        #expect(TargetChoice.menuTargets(source: french, configuration: three) == [english, german])
        #expect(TargetChoice.menuTargets(source: english, configuration: three) == [german, french])
        let four = enabling([english, german, french, italian])
        #expect(TargetChoice.menuTargets(source: german, configuration: four) == [english, french, italian])
    }

    @Test("a menu with three or more languages; the Swap button with two")
    func usesMenu() {
        #expect(!TargetChoice.usesMenu(configuration: .default))
        #expect(TargetChoice.usesMenu(configuration: enabling([english, german, french])))
        #expect(TargetChoice.usesMenu(configuration: enabling([english, german, french, italian])))
    }

    @Test("the stored memory reads back as language codes, normalised")
    func memoryReadsBack() {
        #expect(TargetChoice.memory(from: [:]).isEmpty)
        #expect(TargetChoice.memory(from: ["fr": "de-ch", "IT": " EN "]) == [french: german, italian: english])
    }

    @Test("remembering a target replaces the one stored for that source only")
    func remembering() {
        let stored = TargetChoice.remembering(german, for: french, in: ["it": "en"])
        #expect(stored == ["it": "en", "fr": "de-ch"])
        #expect(TargetChoice.remembering(english, for: french, in: stored) == ["it": "en", "fr": "en"])
        #expect(TargetChoice.memory(from: stored) == [italian: english, french: german])
    }
}
