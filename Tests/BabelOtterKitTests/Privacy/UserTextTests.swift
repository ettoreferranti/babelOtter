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

    // MARK: - Reflection bypass (Fix P1)
    //
    // `dump(_:)` and `Mirror(reflecting:)` read stored properties directly
    // and never consult `description`/`debugDescription` at all — so without
    // `UserText: CustomReflectable`, `dump(userText)` while debugging would
    // print the real content despite every test above passing. These tests
    // exercise that path directly, the way a reviewer's standalone probe did
    // when it found the gap.

    @Test("dump output contains no substring of the original")
    func dumpContainsNoSubstring() {
        let text = UserText(secret)
        var rendered = ""
        dump(text, to: &rendered)
        for length in [4, 8, 16] where secret.count >= length {
            let fragment = String(secret.prefix(length))
            #expect(!rendered.contains(fragment))
        }
    }

    @Test("Mirror children expose no substring of the original")
    func mirrorChildrenContainNoSubstring() {
        let text = UserText(secret)
        let mirror = Mirror(reflecting: text)
        for child in mirror.children {
            let rendered = String(describing: child.value)
            for length in [4, 8, 16] where secret.count >= length {
                let fragment = String(secret.prefix(length))
                #expect(!rendered.contains(fragment))
            }
        }
    }

    @Test("closing the reflection bypass does not regress the existing redaction paths")
    func reflectionFixDoesNotRegressExistingPaths() {
        let text = UserText(secret)
        #expect(!"\(text)".contains("Muster"))
        #expect(!String(describing: text).contains("Muster"))
        #expect(!String(reflecting: text).contains("Muster"))
        #expect(!text.debugDescription.contains("Muster"))
        #expect(text.description == "⟨redacted \(text.characterCount) chars⟩")
    }

    @Test("a UserText nested in another struct does not leak through the parent's dump")
    func nestedStructDumpDoesNotLeak() {
        let envelope = Envelope(userText: UserText(secret), tag: 7)
        var rendered = ""
        dump(envelope, to: &rendered)
        for length in [4, 8, 16] where secret.count >= length {
            let fragment = String(secret.prefix(length))
            #expect(!rendered.contains(fragment))
        }
    }

    // MARK: - Accidental Codable conformance (Fix P2)

    @Test("UserText does not conform to Encodable or Decodable")
    func userTextIsNotCodable() {
        // Persisting user content must be a deliberate, reviewable decision,
        // not something a future `extension UserText: Codable {}` grants
        // silently — that diff would contain no `.value` token anywhere for
        // review to catch, which is the exact bypass this type's whole
        // design depends on not existing. This test exists to make that
        // addition fail loudly instead of silently passing CI. If M3's
        // history genuinely needs UserText to serialise, delete this test in
        // the same commit that adds that conformance on purpose.
        #expect(!((UserText.self as Any) is Encodable.Type))
        #expect(!((UserText.self as Any) is Decodable.Type))
    }
}

/// Fixture for `nestedStructDumpDoesNotLeak`. Deliberately plain — no custom
/// `description` or reflection handling of its own — so the test proves the
/// protection comes from `UserText.customMirror`, not from something this
/// wrapper type does.
private struct Envelope {
    let userText: UserText
    let tag: Int
}
