import Testing

@testable import BabelOtterKit

private func close(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.001 }

@Suite("Eval: chrF")
struct ChrFTests {

    @Test("identical text scores 100")
    func identical() {
        #expect(close(ChrF.score(hypothesis: "Guten Morgen", reference: "Guten Morgen"), 100))
    }

    @Test("nothing in common scores 0")
    func disjoint() {
        #expect(ChrF.score(hypothesis: "ab", reference: "cd") == 0)
    }

    @Test("precision and recall are averaged over orders before the F-score")
    func handComputed() {
        #expect(close(ChrF.score(hypothesis: "ab", reference: "abc"), 63.6364))
    }

    @Test("matches are clipped to the reference count")
    func clipped() {
        #expect(close(ChrF.score(hypothesis: "aa", reference: "a"), 83.3333))
    }

    @Test("recall weighs more than precision")
    func betaTwo() {
        let short = ChrF.score(hypothesis: "ab", reference: "abc")
        let long = ChrF.score(hypothesis: "abc", reference: "ab")
        #expect(short < long)
    }

    @Test("whitespace is ignored")
    func whitespace() {
        #expect(close(ChrF.score(hypothesis: "a b\nc", reference: "abc"), 100))
    }

    @Test("an empty side scores 0")
    func empty() {
        #expect(ChrF.score(hypothesis: "", reference: "abc") == 0)
        #expect(ChrF.score(hypothesis: "abc", reference: "") == 0)
        #expect(ChrF.score(hypothesis: "  ", reference: " ") == 0)
    }

    @Test("orders above six are not used")
    func sixOrders() {
        // One wrong last character in seven. For each n = 1...6 both sides
        // have 8-n grams and 7-n of them match, so P_n = R_n = (7-n)/(8-n).
        // A seventh order would add a term to the mean and change the score.
        let score = ChrF.score(hypothesis: "abcdefX", reference: "abcdefg")
        let ratios = (1...6).map { Double(7 - $0) / Double(8 - $0) }
        let mean = ratios.reduce(0, +) / 6
        #expect(close(score, 100 * mean))
    }
}
