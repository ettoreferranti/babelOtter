import Foundation
import Testing

@testable import BabelOtterKit

/// The whole core path, driven with a canned model response.
///
/// Nothing here opens a connection: the "response" is a literal string, which is
/// what makes this a contract test rather than an integration test. Every
/// component below is covered by its own suite; this exists for the seams
/// *between* them, which is where M0's twelve looks-protective-but-isn't
/// defects all lived.
@Suite("The core pipeline, end to end")
struct PipelineTests {

    private let configuration = Configuration.default

    @Test("a German bullet list survives translation with its structure, terms and orthography")
    func translateABulletList() throws {
        let input = "- Die Straße ist groß\n- Otterbach ist eine Schule"

        // 1. Structure out.
        let extracted = StructureExtractor.extract(input)
        #expect(extracted.blocks == ["Die Straße ist groß", "Otterbach ist eine Schule"])

        // 2. Protected terms masked.
        let masked = extracted.blocks.map { TokenProtector.mask($0, terms: ["Otterbach"]) }
        #expect(masked[1].text == "⟦DNT0⟧ ist eine Schule")

        // 3. A prompt that names the count it expects.
        let prompt = PromptBuilder().build(
            PromptRequest(
                action: .translate,
                source: .swissGerman,
                target: .swissGerman,
                profile: .colleagues,
                doNotTranslate: ["Otterbach"],
                blocks: masked.map(\.text)
            ))
        #expect(prompt.contains("exactly 2 block"))

        // 4. A canned response in the documented shape.
        let raw = """
            ```json
            {"detected_source": "de", "detected_audience": "colleagues",
             "blocks": ["Die Straße ist groß", "⟦DNT0⟧ ist eine grosse Schule"]}
            ```
            """
        guard case .decoded(let response) = ResponseParser.parseTranslate(raw) else {
            Issue.record("the canned response should parse")
            return
        }

        // 5. Block count checked before anything is re-applied.
        #expect(
            BlockCountPolicy().decide(
                expected: extracted.skeleton.blockCount,
                received: response.blocks.count,
                attempt: 0) == .accept)

        // 6. Post-processing, in the order §8 fixes.
        let processor = PostProcessor(target: .swissGerman)
        let finished = zip(response.blocks, masked).map {
            processor.finish($0, protected: $1)
        }
        #expect(finished.allSatisfy { $0.problems.isEmpty })

        // 7. Structure back on.
        let output = try StructureExtractor.reapply(
            finished.map(\.text), to: extracted.skeleton)

        #expect(output == "- Die Strasse ist gross\n- Otterbach ist eine grosse Schule")
        #expect(!output.contains("ß"), "FR-TRN-05: ß must never survive to a de-CH output")
        #expect(output.contains("Otterbach"), "FR-GLO-02: the protected term must come back verbatim")
        #expect(output.hasPrefix("- "), "FR-TRN-04: the list marker must survive")
    }

    @Test("a wrong block count never reaches the skeleton")
    func wrongBlockCountIsCaught() {
        let extracted = StructureExtractor.extract("one\ntwo\nthree")
        let decision = BlockCountPolicy().decide(
            expected: extracted.skeleton.blockCount, received: 2, attempt: 0)
        #expect(decision == .retryWholeText)
        #expect(throws: StructureError.blockCountMismatch(expected: 3, received: 2)) {
            try StructureExtractor.reapply(["eins", "zwei"], to: extracted.skeleton)
        }
    }

    @Test("detection and resolution agree on direction for a German selection")
    func directionForGerman() {
        let detector = LanguageDetector(configuration: configuration)
        let detection = detector.detect(
            """
            Der Ausschuss hat beschlossen, die Entscheidung bis zur nächsten Sitzung zu \
            verschieben, weil die Zahlen noch nicht vorliegen.
            """)
        let resolution = TargetLanguageResolver(configuration: configuration).resolve(detection)
        #expect(
            resolution == .resolved(source: LanguageCode("de-ch"), target: LanguageCode("en")))
    }

    @Test("a selection too short to judge asks rather than guessing")
    func shortSelectionAsks() {
        let detector = LanguageDetector(configuration: configuration)
        let resolution = TargetLanguageResolver(configuration: configuration)
            .resolve(detector.detect("Hallo"))
        guard case .needsUserChoice(.tooShort) = resolution else {
            Issue.record("expected a request for user choice, got \(resolution)")
            return
        }
    }

    @Test("a mangled sentinel is surfaced rather than pasted into the user's text")
    func mangledSentinelSurfaces() {
        let masked = TokenProtector.mask("Otterbach ist gut", terms: ["Otterbach"])
        let finished = PostProcessor(target: .swissGerman)
            .finish("Die Schule ist gut", protected: masked)
        #expect(finished.problems == [.sentinelMissing(index: 0, term: "Otterbach")])
    }

    @Test("configuration written and reloaded drives the same pipeline decisions")
    func configurationRoundTripsIntoBehaviour() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "babelotter-pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ConfigurationStore(directory: directory)

        var edited = Configuration.default
        edited.minimumLengthForDetection = 500
        try store.save(edited)

        let reloaded = store.load().configuration
        let detector = LanguageDetector(configuration: reloaded)
        guard case .ambiguous(.tooShort(_, let minimum)) = detector.detect("A short sentence here.")
        else {
            Issue.record("a 500-character minimum should make this too short")
            return
        }
        #expect(minimum == 500)
    }
}
