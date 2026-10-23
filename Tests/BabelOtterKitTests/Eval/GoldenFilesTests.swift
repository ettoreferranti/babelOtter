import Foundation
import Testing

@testable import BabelOtterKit

/// The real golden files must load, and must cover what the spec asks of
/// them (spec 2026-09-30, section 3). The content guard scans them too:
/// `evals` is one of `FixtureContentGuardTests.scannedDirectories`.
@Suite("Eval: the golden files are valid and cover the spec")
struct GoldenFilesTests {

    private static func golden() throws -> GoldenSet {
        let directory = SourceTree.repositoryRoot.appending(path: "evals/golden")
        return try GoldenSet.load(
            correction: Data(contentsOf: directory.appending(path: "correction.json")),
            translation: Data(contentsOf: directory.appending(path: "translation.json")))
    }

    @Test("both files load and validate")
    func valid() throws {
        _ = try Self.golden()
    }

    @Test("correction covers every category twice, clean texts and the special cases")
    func correctionCoverage() throws {
        let cases = try Self.golden().correction
        #expect(cases.count >= 25)
        let fixes = cases.flatMap(\.fixes)
        for category in ErrorCategory.allCases {
            #expect(fixes.filter { $0.category == category }.count >= 2, "\(category.rawValue)")
        }
        #expect(cases.filter(\.clean).count >= 5)
        #expect(cases.filter { $0.text.contains("\n\n") }.count >= 2)
        #expect(cases.contains { !$0.terms.isEmpty })
        #expect(cases.contains { $0.text.contains("\u{00DF}") })
        #expect(cases.contains { $0.profileID == "administration" })
        #expect(cases.contains { !$0.mustNot.isEmpty })
        #expect(!cases.filter(\.clean).contains { $0.text.contains("\u{00DF}") })
    }

    @Test("translation covers both directions, lists, paragraphs, terms and eszett targets")
    func translationCoverage() throws {
        let cases = try Self.golden().translation
        #expect(cases.count >= 18)
        #expect(cases.filter { $0.direction == .englishToSwissGerman }.count >= 7)
        #expect(cases.filter { $0.direction == .swissGermanToEnglish }.count >= 7)
        #expect(cases.filter { $0.text.contains("\n- ") || $0.text.hasPrefix("- ") }.count >= 2)
        #expect(cases.filter { $0.text.contains("\n\n") }.count >= 2)
        #expect(cases.filter { !$0.terms.isEmpty }.count >= 3)
        #expect(cases.contains { $0.profileID != "colleagues" })
        #expect(!cases.contains { testCase in
            testCase.direction.targetRules.contains { testCase.reference.contains($0.replace) }
        })
    }

    @Test("French and Italian to and from English: five cases each, with terms and profiles (#81)")
    func frenchAndItalianCoverage() throws {
        let cases = try Self.golden().translation
        for raw in ["en-fr", "fr-en", "en-it", "it-en"] {
            let direction = try #require(TranslationDirection(rawValue: raw))
            let these = cases.filter { $0.direction == direction }
            #expect(these.count >= 5, "\(raw)")
            #expect(these.contains { $0.profileID != "colleagues" }, "\(raw)")
            #expect(these.contains { $0.text.contains("\n- ") }, "\(raw)")
        }
        let withTerms = cases.filter { !$0.terms.isEmpty }.map(\.direction.rawValue)
        #expect(Set(withTerms).isSuperset(of: ["en-fr", "fr-en", "en-it", "it-en"]))
    }
}
