import Foundation
import Testing

@testable import BabelOtterKit

@Suite("The language Correct and Explain work on (#81)")
struct TextLanguageTests {

    private let english = LanguageCode("en")
    private let german = LanguageCode("de-ch")
    private let french = LanguageCode("fr")
    private let italian = LanguageCode("it")

    private func confident(_ code: String) -> Detection {
        .confident(LanguageCode(code), confidence: 0.9)
    }

    private let tooShort = Detection.ambiguous(.tooShort(length: 4, minimum: 12))
    private let belowFloor = Detection.ambiguous(
        .belowFloor(best: LanguageCode("fr"), confidence: 0.4, floor: 0.65))
    private let nothing = Detection.ambiguous(.noHypothesis)

    private func configuration(_ enabled: [LanguageCode], mine: LanguageCode? = nil) -> Configuration {
        var configuration = Configuration.default
        for index in configuration.languages.indices {
            configuration.languages[index].enabled = enabled.contains(configuration.languages[index].code)
        }
        configuration.myLanguage = mine
        return configuration
    }

    private func resolve(
        _ detection: Detection, _ configuration: Configuration, excludingMine: Bool = false
    ) -> TextLanguageResolution {
        TextLanguage.resolve(detection, configuration: configuration, excludingMine: excludingMine)
    }

    @Test("today's setup is unchanged: German detected or assumed, English mine")
    func todaysSetup() {
        let today = configuration([english, german])
        #expect(resolve(confident("de"), today) == .known(german))
        #expect(resolve(confident("de"), today, excludingMine: true) == .known(german))
        for unsure in [tooShort, belowFloor, nothing] {
            #expect(resolve(unsure, today) == .known(german))
            #expect(resolve(unsure, today, excludingMine: true) == .known(german))
        }
    }

    @Test("a confident enabled language is the one, matched by base code")
    func confidentEnabled() {
        let three = configuration([english, german, french])
        #expect(resolve(confident("fr"), three) == .known(french))
        #expect(resolve(confident("de-CH"), three) == .known(german))
        #expect(resolve(confident("en"), three) == .known(english))
    }

    @Test("a confident language that is not enabled is reported")
    func notEnabled() {
        #expect(resolve(confident("it"), configuration([english, german])) == .notEnabled(italian))
        #expect(resolve(confident("es"), configuration([english, german]), excludingMine: true)
            == .notEnabled(LanguageCode("es")))
    }

    @Test("for Explain, my language is refused; for Correct it is a language like any other")
    func mine() {
        let three = configuration([english, german, french])
        #expect(resolve(confident("en"), three, excludingMine: true) == .mine(english))
        let italianMine = configuration([english, german, italian], mine: italian)
        #expect(resolve(confident("it"), italianMine, excludingMine: true) == .mine(italian))
        #expect(resolve(confident("it"), italianMine) == .known(italian))
        #expect(resolve(confident("en"), italianMine, excludingMine: true) == .known(english))
    }

    @Test("unsure with several others asks: Correct offers all, Explain all but mine")
    func asks() {
        let three = configuration([english, german, french])
        #expect(resolve(tooShort, three) == .ask([english, german, french]))
        #expect(resolve(belowFloor, three, excludingMine: true) == .ask([german, french]))
        let germanMine = configuration([english, german, french], mine: german)
        #expect(resolve(nothing, germanMine, excludingMine: true) == .ask([english, french]))
    }

    @Test("unsure with one other assumes it, whichever language is mine")
    func assumesTheOnlyOther() {
        let germanMine = configuration([english, german], mine: german)
        #expect(resolve(tooShort, germanMine) == .known(english))
        #expect(resolve(tooShort, germanMine, excludingMine: true) == .known(english))
    }
}
