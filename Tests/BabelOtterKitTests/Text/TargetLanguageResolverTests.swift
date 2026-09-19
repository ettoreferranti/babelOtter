import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Target resolution is driven by configuration, not by code")
struct TargetLanguageResolverTests {

    private let standard = TargetLanguageResolver(
        languages: [LanguageConfig.english, LanguageConfig.swissGerman])

    private func confident(_ code: String) -> Detection {
        .confident(LanguageCode(code), confidence: 0.9)
    }

    @Test("English detected with EN and de-CH enabled resolves to de-CH")
    func englishToSwissGerman() {
        #expect(
            standard.resolve(confident("en"))
                == .resolved(source: LanguageCode("en"), target: LanguageCode("de-ch")))
    }

    /// The regional-subtag case. `NLLanguageRecognizer` reports `de`; the
    /// enabled language is `de-CH`. Comparing full tags would report German as
    /// "not enabled" for every German selection.
    @Test("a detected base subtag matches an enabled regional variant")
    func baseSubtagMatchesRegional() {
        #expect(
            standard.resolve(confident("de"))
                == .resolved(source: LanguageCode("de-ch"), target: LanguageCode("en")))
    }

    @Test("an exact regional match works too")
    func exactRegionalMatch() {
        #expect(
            standard.resolve(confident("de-CH"))
                == .resolved(source: LanguageCode("de-ch"), target: LanguageCode("en")))
    }

    @Test("a detected language that is not enabled is reported, not mistranslated")
    func notEnabled() {
        #expect(standard.resolve(confident("fr")) == .notEnabled(LanguageCode("fr")))
    }

    @Test("a disabled language does not count toward the pair")
    func disabledDoesNotCount() {
        var french = LanguageConfig(
            code: LanguageCode("fr"), displayName: "French", localeRules: [], enabled: false)
        french.enabled = false
        let resolver = TargetLanguageResolver(
            languages: [.english, .swissGerman, french])
        #expect(
            resolver.resolve(confident("en"))
                == .resolved(source: LanguageCode("en"), target: LanguageCode("de-ch")))
    }

    @Test("more than two enabled languages surfaces ambiguity rather than guessing")
    func threeEnabledIsAmbiguous() {
        let french = LanguageConfig(
            code: LanguageCode("fr"), displayName: "French", localeRules: [], enabled: true)
        let resolver = TargetLanguageResolver(languages: [.english, .swissGerman, french])
        #expect(
            resolver.resolve(confident("en"))
                == .ambiguousPairing(candidates: [LanguageCode("de-ch"), LanguageCode("fr")]))
    }

    @Test("a single enabled language has no other side")
    func oneEnabled() {
        let resolver = TargetLanguageResolver(languages: [.english])
        #expect(resolver.resolve(confident("en")) == .ambiguousPairing(candidates: []))
    }

    @Test("an ambiguous detection passes through, carrying its reason")
    func ambiguousDetectionPassesThrough() {
        let detection = Detection.ambiguous(.tooShort(length: 2, minimum: 12))
        #expect(
            standard.resolve(detection) == .needsUserChoice(.tooShort(length: 2, minimum: 12)))
    }

    @Test("a below-floor detection also asks rather than guessing")
    func belowFloorAsks() {
        let reason = AmbiguityReason.belowFloor(
            best: LanguageCode("de"), confidence: 0.4, floor: 0.65)
        #expect(standard.resolve(.ambiguous(reason)) == .needsUserChoice(reason))
    }

    /// FR-LNG-01's acceptance criterion, made executable: if anyone writes
    /// `if code == "de-ch"` in the resolver, this test fails.
    @Test("no language code is hardcoded in the logic")
    func noHardcodedCodes() {
        let xx = LanguageConfig(
            code: LanguageCode("xx"), displayName: "Invented A", localeRules: [], enabled: true)
        let yy = LanguageConfig(
            code: LanguageCode("yy"), displayName: "Invented B", localeRules: [], enabled: true)
        let resolver = TargetLanguageResolver(languages: [xx, yy])
        #expect(
            resolver.resolve(confident("xx"))
                == .resolved(source: LanguageCode("xx"), target: LanguageCode("yy")))
        #expect(
            resolver.resolve(confident("yy"))
                == .resolved(source: LanguageCode("yy"), target: LanguageCode("xx")))
    }

    @Test("with nothing enabled, the detected language is reported as not enabled")
    func noneEnabled() {
        // More precise than "ambiguous pairing": nothing is enabled, so the
        // detected language genuinely is not among the enabled ones, and that
        // is the message that tells the user what to fix.
        let resolver = TargetLanguageResolver(languages: [])
        #expect(resolver.resolve(confident("en")) == .notEnabled(LanguageCode("en")))
    }

    @Test("a resolver can be built straight from configuration")
    func fromConfiguration() {
        let resolver = TargetLanguageResolver(configuration: .default)
        #expect(
            resolver.resolve(confident("en"))
                == .resolved(source: LanguageCode("en"), target: LanguageCode("de-ch")))
    }
}
