import Foundation
import Testing

@testable import BabelOtterKit

/// Returns fixed hypotheses and records whether it was asked at all.
///
/// The policy — floor comparison, length check, picking a winner — must be
/// deterministic and mutation-killable. `NLLanguageRecognizer` is a system model
/// whose confidences vary by OS version, and this project runs two majors apart
/// locally and in CI, so asserting a live confidence against a floor would give
/// a test that passes on one machine and fails on the other.
private final class StubRecognizer: LanguageRecognizing, @unchecked Sendable {
    let hypotheses: [LanguageCode: Double]
    private(set) var wasConsulted = false

    init(_ hypotheses: [LanguageCode: Double]) {
        self.hypotheses = hypotheses
    }

    func hypotheses(for text: String) -> [LanguageCode: Double] {
        wasConsulted = true
        return hypotheses
    }
}

@Suite("Language detection policy")
struct LanguageDetectorTests {

    private func detector(
        _ recognizer: any LanguageRecognizing,
        floor: Double = 0.65,
        minimumLength: Int = 12
    ) -> LanguageDetector {
        LanguageDetector(recognizer: recognizer, floor: floor, minimumLength: minimumLength)
    }

    @Test("confidence above the floor is confident")
    func aboveFloor() {
        let result = detector(StubRecognizer([LanguageCode("en"): 0.9]))
            .detect("a selection long enough to try")
        #expect(result == .confident(LanguageCode("en"), confidence: 0.9))
    }

    @Test("confidence exactly at the floor is confident")
    func exactlyAtFloor() {
        let result = detector(StubRecognizer([LanguageCode("en"): 0.65]))
            .detect("a selection long enough to try")
        #expect(result == .confident(LanguageCode("en"), confidence: 0.65))
    }

    @Test("confidence just below the floor is ambiguous, and says what it guessed")
    func belowFloor() {
        let result = detector(StubRecognizer([LanguageCode("en"): 0.64]))
            .detect("a selection long enough to try")
        #expect(
            result
                == .ambiguous(.belowFloor(best: LanguageCode("en"), confidence: 0.64, floor: 0.65)))
    }

    @Test("the highest-confidence hypothesis wins")
    func highestWins() {
        let recognizer = StubRecognizer([
            LanguageCode("en"): 0.7, LanguageCode("de"): 0.95, LanguageCode("fr"): 0.2,
        ])
        #expect(
            detector(recognizer).detect("a selection long enough to try")
                == .confident(LanguageCode("de"), confidence: 0.95))
    }

    /// A dictionary has no order, so on equal confidences `max(by:)` returns
    /// whichever the hash order happened to put last — a different answer
    /// between runs, for the one input where it matters most.
    @Test("a tie breaks deterministically by language code, not by hash order")
    func tieBreaksDeterministically() {
        let recognizer = StubRecognizer([LanguageCode("en"): 0.8, LanguageCode("de"): 0.8])
        #expect(
            detector(recognizer).detect("a selection long enough to try")
                == .confident(LanguageCode("de"), confidence: 0.8))
    }

    @Test("the tie-break is stable across repeated detections")
    func tieBreakIsStable() {
        let recognizer = StubRecognizer([
            LanguageCode("en"): 0.8, LanguageCode("de"): 0.8, LanguageCode("fr"): 0.8,
        ])
        let subject = detector(recognizer)
        let results = (0..<20).map { _ in subject.detect("a selection long enough to try") }
        #expect(Set(results.map(\.languageCode?.rawValue)).count == 1)
    }

    @Test("text shorter than the minimum is ambiguous without guessing")
    func tooShort() {
        let result = detector(StubRecognizer([LanguageCode("en"): 0.99])).detect("hallo")
        #expect(result == .ambiguous(.tooShort(length: 5, minimum: 12)))
    }

    @Test("a short selection never reaches the recognizer at all")
    func shortSelectionSkipsTheModel() {
        let recognizer = StubRecognizer([LanguageCode("en"): 0.99])
        _ = detector(recognizer).detect("hallo")
        #expect(recognizer.wasConsulted == false)
    }

    @Test("length counts non-whitespace characters only")
    func lengthIgnoresWhitespace() {
        let result = detector(StubRecognizer([LanguageCode("en"): 0.99]), minimumLength: 3)
            .detect("   hi   ")
        #expect(result == .ambiguous(.tooShort(length: 2, minimum: 3)))
    }

    @Test("whitespace-only text is length zero")
    func whitespaceOnly() {
        let result = detector(StubRecognizer([LanguageCode("en"): 0.99])).detect("   \n\t  ")
        #expect(result == .ambiguous(.tooShort(length: 0, minimum: 12)))
    }

    @Test("no hypothesis at all is reported rather than guessed")
    func noHypothesis() {
        let result = detector(StubRecognizer([:])).detect("a selection long enough to try")
        #expect(result == .ambiguous(.noHypothesis))
    }

    @Test("a minimum of zero lets even a tiny selection through to the recognizer")
    func zeroMinimum() {
        let recognizer = StubRecognizer([LanguageCode("en"): 0.9])
        let result = detector(recognizer, minimumLength: 0).detect("hi")
        #expect(result == .confident(LanguageCode("en"), confidence: 0.9))
    }
}

@Suite("NaturalLanguage recognizer smoke tests")
struct NaturalLanguageRecognizerTests {

    private let detector = LanguageDetector(
        recognizer: NaturalLanguageRecognizer(), floor: 0.5, minimumLength: 12)

    @Test("a plainly English paragraph detects as English")
    func english() {
        let text = """
            The committee has agreed to postpone the decision until the next meeting, \
            when the revised budget figures will finally be available for review.
            """
        #expect(detector.detect(text).languageCode?.baseSubtag == LanguageCode("en"))
    }

    @Test("a plainly German paragraph detects as German")
    func german() {
        let text = """
            Der Ausschuss hat beschlossen, die Entscheidung bis zur nächsten Sitzung \
            zu verschieben, wenn die überarbeiteten Budgetzahlen endlich vorliegen.
            """
        #expect(detector.detect(text).languageCode?.baseSubtag == LanguageCode("de"))
    }

    @Test("a constrained recognizer only answers with the languages it is limited to")
    func constrained() {
        let english = """
            The committee has agreed to postpone the decision until the next meeting, \
            when the revised budget figures will finally be available for review.
            """
        let recognizer = NaturalLanguageRecognizer(constraints: [LanguageCode("fr"), LanguageCode("it")])
        let guesses = Set(recognizer.hypotheses(for: english).keys)
        #expect(!guesses.isEmpty)
        #expect(guesses.isSubset(of: [LanguageCode("fr"), LanguageCode("it")]))
        #expect(Set(NaturalLanguageRecognizer().hypotheses(for: english).keys).contains(LanguageCode("en")))
    }

    @Test("French and Italian paragraphs detect as themselves among four languages")
    func frenchAndItalian() {
        let recognizer = NaturalLanguageRecognizer(
            constraints: ["en", "de-ch", "fr", "it"].map(LanguageCode.init))
        let constrained = LanguageDetector(recognizer: recognizer, floor: 0.5, minimumLength: 12)
        let french = """
            Le comité a décidé de reporter la décision à la prochaine séance, \
            lorsque les chiffres révisés du budget seront enfin disponibles.
            """
        let italian = """
            Il comitato ha deciso di rinviare la decisione alla prossima riunione, \
            quando le cifre riviste del bilancio saranno finalmente disponibili.
            """
        #expect(constrained.detect(french).languageCode == LanguageCode("fr"))
        #expect(constrained.detect(italian).languageCode == LanguageCode("it"))
    }
}

@Suite("Detection screens with the open recognizer, then chooses among the enabled languages (#81)")
struct DetectionConstraintTests {

    private func screened(_ detector: LanguageDetector) -> ScreenedRecognizer? {
        detector.recognizer as? ScreenedRecognizer
    }

    @Test("a detector built from configuration screens, then limits to the enabled base codes")
    func fromConfiguration() throws {
        var configuration = Configuration.default
        let two = try #require(screened(LanguageDetector(configuration: configuration)))
        #expect((two.constrained as? NaturalLanguageRecognizer)?.constraints == [LanguageCode("en"), LanguageCode("de")])
        #expect((two.open as? NaturalLanguageRecognizer)?.constraints.isEmpty == true)
        #expect(two.enabled == [LanguageCode("en"), LanguageCode("de")])
        #expect(two.floor == configuration.detectionConfidenceFloor)
        configuration.languages[2].enabled = true
        configuration.detectionConfidenceFloor = 0.8
        let three = try #require(screened(LanguageDetector(configuration: configuration)))
        #expect((three.constrained as? NaturalLanguageRecognizer)?.constraints
            == [LanguageCode("en"), LanguageCode("de"), LanguageCode("fr")])
        #expect(three.floor == 0.8)
    }

    @Test("an injected recognizer is used as given")
    func injected() {
        let detector = LanguageDetector(
            configuration: .default, recognizer: NaturalLanguageRecognizer(constraints: [LanguageCode("it")]))
        #expect((detector.recognizer as? NaturalLanguageRecognizer)?.constraints == [LanguageCode("it")])
        #expect(NaturalLanguageRecognizer().constraints.isEmpty)
    }

    private let enabled = [LanguageCode("en"), LanguageCode("de-ch")]

    @Test("a confident guess outside the enabled languages stands; the constrained one is not asked")
    func outsiderStands() {
        let open = StubRecognizer([LanguageCode("it"): 0.99, LanguageCode("es"): 0.01])
        let constrained = StubRecognizer([LanguageCode("de"): 0.72])
        let subject = ScreenedRecognizer(open: open, constrained: constrained, enabled: enabled, floor: 0.65)
        #expect(subject.hypotheses(for: "x") == [LanguageCode("it"): 0.99, LanguageCode("es"): 0.01])
        #expect(!constrained.wasConsulted)
    }

    @Test("an outsider exactly at the floor stands too")
    func outsiderAtFloor() {
        let constrained = StubRecognizer([LanguageCode("de"): 0.9])
        let subject = ScreenedRecognizer(
            open: StubRecognizer([LanguageCode("it"): 0.65]), constrained: constrained, enabled: enabled, floor: 0.65)
        #expect(subject.hypotheses(for: "x") == [LanguageCode("it"): 0.65])
    }

    @Test("an enabled guess, by base code, or an unsure outsider goes to the constrained recognizer")
    func constrainedOtherwise() {
        let constrained = StubRecognizer([LanguageCode("fr"): 0.8])
        for open in [[LanguageCode("de"): 0.95], [LanguageCode("it"): 0.64, LanguageCode("fr"): 0.3], [:]] {
            let subject = ScreenedRecognizer(
                open: StubRecognizer(open), constrained: constrained, enabled: enabled, floor: 0.65)
            #expect(subject.hypotheses(for: "x") == [LanguageCode("fr"): 0.8], "\(open)")
        }
    }

    @Test("with English and German on, an Italian sentence is Italian, not German (live)")
    func italianNotEnabled() {
        let italian = """
            Il comitato ha deciso di rinviare la decisione alla prossima riunione, \
            quando le cifre riviste del bilancio saranno finalmente disponibili.
            """
        #expect(LanguageDetector(configuration: .default).detect(italian).languageCode == LanguageCode("it"))
    }
}
