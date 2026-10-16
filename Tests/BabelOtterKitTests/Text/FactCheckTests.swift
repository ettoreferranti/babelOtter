import Testing

@testable import BabelOtterKit

@Suite("Facts from the original that a rewrite lost")
struct FactCheckTests {

    @Test("a missing time is reported; a kept date is not")
    func missingTime() {
        #expect(FactCheck.missing(from: "Treffen am 12.11.2026 um 14:30.", in: "Treffen am 12.11.2026.") == ["14:30"])
    }

    @Test("dates, decimals and ranges are one fact each")
    func joinedNumbers() {
        #expect(FactCheck.missing(from: "Am 2026-11-12, 3,5 Stunden, Seiten 10-12, 1/2", in: "") == ["2026-11-12", "3,5", "10-12", "1/2"])
    }

    @Test("a fact kept in other surroundings is not reported")
    func keptElsewhere() {
        #expect(FactCheck.missing(from: "um 14:30 Uhr im Raum 2.13", in: "at 14:30 in room 2.13").isEmpty)
    }

    @Test("a repeated fact is reported once")
    func repeated() {
        #expect(FactCheck.missing(from: "10 und 10", in: "zehn") == ["10"])
    }

    @Test("web addresses lose the punctuation around them")
    func links() {
        #expect(FactCheck.missing(from: "Siehe https://example.ch/a. Oder (www.otterbach.ch)!", in: "") == ["https://example.ch/a", "www.otterbach.ch"])
        #expect(FactCheck.missing(from: "Siehe https://example.ch/a.", in: "see https://example.ch/a!").isEmpty)
    }

    @Test("email addresses are facts; an at sign without a domain is not")
    func emails() {
        #expect(FactCheck.missing(from: "Schreib an (anna@example.ch).", in: "") == ["anna@example.ch"])
        #expect(FactCheck.missing(from: "a@b", in: "").isEmpty)
    }

    @Test("a link with digits counts as the link, not as its numbers")
    func linkNotNumbers() {
        #expect(FactCheck.missing(from: "https://example.ch/2026", in: "") == ["https://example.ch/2026"])
    }

    @Test("text without facts gives nothing")
    func noFacts() {
        #expect(FactCheck.missing(from: "Hallo zusammen, bis bald.", in: "").isEmpty)
    }

    @Test("a trailing full stop is not part of a number")
    func trailingStop() {
        #expect(FactCheck.missing(from: "Es sind 42.", in: "") == ["42"])
    }
}
