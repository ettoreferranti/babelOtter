import Foundation
import Testing

@testable import BabelOtterKit

@Suite("A history search ignores case and accents")
struct HistorySearchTests {

    @Test("case and accents are ignored")
    func folding() {
        #expect(HistorySearch.contains("Die \u{00DC}ber-Sitzung", "uber"))
        #expect(HistorySearch.contains("une \u{00E9}cole", "\u{00C9}COLE"))
        #expect(HistorySearch.contains("Strasse", "STRASSE"))
    }

    @Test("an eszett folds to ss, so either spelling finds the other")
    func eszett() {
        #expect(HistorySearch.contains("Stra\u{00DF}e", "strasse"))
        #expect(HistorySearch.contains("Strasse", "stra\u{00DF}e"))
    }

    @Test("text without the term does not match")
    func absent() {
        #expect(!HistorySearch.contains("Hallo zusammen", "tsch\u{00FC}ss"))
        #expect(!HistorySearch.contains("", "a"))
    }

    @Test("the same in every locale")
    func localeIndependent() {
        // A Turkish locale would fold "I" to a dotless i; search uses none.
        #expect(HistorySearch.contains("INFO", "info"))
        #expect(HistorySearch.contains("info", "INFO"))
    }

    @Test("the source or the result matches")
    func sourceOrResult() {
        let record = HistoryRecord.sample(source: "Gr\u{00FC}ezi", result: "Hello there")
        #expect(HistorySearch.matches(record, "GRUEZI"))
        #expect(HistorySearch.matches(record, "THERE"))
        #expect(!HistorySearch.matches(record, "bye"))
    }

    @Test("audience, app and model are not searched")
    func metadataIgnored() {
        let record = HistoryRecord.sample(
            profileID: "students", model: "mistral", appName: "Mail",
            source: "a", result: "b")
        #expect(!HistorySearch.matches(record, "students"))
        #expect(!HistorySearch.matches(record, "mistral"))
        #expect(!HistorySearch.matches(record, "Mail"))
    }

    @Test("a term is trimmed, and nothing left means every record")
    func normalized() {
        #expect(HistorySearch.normalized("  uber \n") == "uber")
        #expect(HistorySearch.normalized("a b") == "a b")
        #expect(HistorySearch.normalized("") == nil)
        #expect(HistorySearch.normalized(" \t\n") == nil)
    }
}
