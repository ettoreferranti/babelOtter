import Testing
import Foundation
@testable import BabelOtterKit

/// NFR-P5: user content must not reach a log. Prompts in the unified log can be
/// swept into a sysdiagnose bundle and carried to Apple, so the accidental path
/// — interpolating a value into a log line — has to be safe by default.
@Suite("UserText redacts by default")
struct UserTextTests {

    let secret = "Sehr geehrte Frau Muster, anbei die Unterlagen zum Modul."

    @Test("string interpolation is redacted")
    func interpolationIsRedacted() {
        let text = UserText(secret)
        #expect(!"\(text)".contains("Muster"))
        #expect(!"\(text)".contains("Modul"))
    }

    @Test("description and debugDescription are redacted")
    func descriptionsAreRedacted() {
        let text = UserText(secret)
        #expect(!String(describing: text).contains("Muster"))
        #expect(!String(reflecting: text).contains("Muster"))
        #expect(!text.debugDescription.contains("Muster"))
    }

    @Test("the redaction reveals length but never content")
    func redactionShowsLengthOnly() {
        let text = UserText("Hallo Welt")
        #expect("\(text)" == "⟨redacted 10 chars⟩")
    }

    @Test("no substring of the original survives redaction")
    func noSubstringSurvives() {
        let text = UserText(secret)
        let rendered = "\(text)"
        for length in [4, 8, 16] where secret.count >= length {
            let fragment = String(secret.prefix(length))
            #expect(!rendered.contains(fragment))
        }
    }

    @Test("the explicit unwrap returns the real content")
    func explicitUnwrapReturnsContent() {
        #expect(UserText(secret).value == secret)
    }

    @Test("character count uses grapheme clusters")
    func characterCountIsGraphemeAware() {
        #expect(UserText("Grüezi").characterCount == 6)
        #expect(UserText("👩‍👩‍👧").characterCount == 1)
    }

    @Test("empty and whitespace-only text are reported as empty")
    func emptyDetection() {
        #expect(UserText("").isEmpty)
        #expect(UserText("   \n\t ").isEmpty)
        #expect(!UserText("a").isEmpty)
    }

    @Test("a summary carries metadata and no content")
    func summaryCarriesMetadataOnly() {
        let summary = UserText(secret).summary(languageCode: "de-CH", action: "translate")
        let rendered = "\(summary)"
        #expect(rendered.contains("de-CH"))
        #expect(rendered.contains("translate"))
        #expect(rendered.contains("\(secret.count)"))
        #expect(!rendered.contains("Muster"))
    }
}
