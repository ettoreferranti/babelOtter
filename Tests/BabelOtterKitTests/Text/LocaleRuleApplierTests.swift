import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Locale rules never rewrite protected spans")
struct LocaleRuleApplierTests {

    private let swiss = [LocaleRule(replace: "ß", with: "ss")]

    @Test("every ß outside a protected span becomes ss")
    func rewritesUnprotected() {
        #expect(
            LocaleRuleApplier.apply(swiss, to: "Die Straße ist groß.", protecting: [])
                == "Die Strasse ist gross.")
    }

    @Test("a protected span keeps its ß")
    func protectsSpans() {
        let text = "Das Großmünster ist groß."
        let range = text.range(of: "Großmünster")!
        #expect(
            LocaleRuleApplier.apply(swiss, to: text, protecting: [range])
                == "Das Großmünster ist gross.")
    }

    @Test("a language with no rules changes nothing")
    func noRulesIsNoOp() {
        #expect(
            LocaleRuleApplier.apply([], to: "Die Straße ist groß.", protecting: [])
                == "Die Straße ist groß.")
    }

    @Test("rules apply in the order configured")
    func rulesApplyInOrder() {
        let rules = [LocaleRule(replace: "a", with: "b"), LocaleRule(replace: "b", with: "c")]
        #expect(LocaleRuleApplier.apply(rules, to: "a", protecting: []) == "c")
    }

    @Test("text on both sides of a protected span is still rewritten")
    func rewritesAroundProtection() {
        let text = "groß Otterbach groß"
        let range = text.range(of: "Otterbach")!
        #expect(
            LocaleRuleApplier.apply(swiss, to: text, protecting: [range]) == "gross Otterbach gross")
    }

    @Test("several protected spans are all honoured")
    func multipleProtectedSpans() {
        let text = "groß Aß groß Bß groß"
        let ranges = [text.range(of: "Aß")!, text.range(of: "Bß")!]
        #expect(
            LocaleRuleApplier.apply(swiss, to: text, protecting: ranges)
                == "gross Aß gross Bß gross")
    }

    @Test("a protected span at the very start is honoured")
    func protectionAtStart() {
        let text = "ß groß"
        let range = text.startIndex..<text.index(after: text.startIndex)
        #expect(LocaleRuleApplier.apply(swiss, to: text, protecting: [range]) == "ß gross")
    }

    @Test("a protected span at the very end is honoured")
    func protectionAtEnd() {
        let text = "groß ß"
        let range = text.index(before: text.endIndex)..<text.endIndex
        #expect(LocaleRuleApplier.apply(swiss, to: text, protecting: [range]) == "gross ß")
    }

    @Test("ranges given out of order are still honoured")
    func unorderedRanges() {
        let text = "groß Aß groß Bß groß"
        let ranges = [text.range(of: "Bß")!, text.range(of: "Aß")!]
        #expect(
            LocaleRuleApplier.apply(swiss, to: text, protecting: ranges)
                == "gross Aß gross Bß gross")
    }

    @Test("the whole text protected means nothing changes")
    func everythingProtected() {
        let text = "groß"
        #expect(
            LocaleRuleApplier.apply(swiss, to: text, protecting: [text.startIndex..<text.endIndex])
                == "groß")
    }

    @Test("empty text is handled")
    func emptyText() {
        #expect(LocaleRuleApplier.apply(swiss, to: "", protecting: []) == "")
    }
}
