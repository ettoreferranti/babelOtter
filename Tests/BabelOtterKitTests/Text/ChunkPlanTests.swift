import Testing

@testable import BabelOtterKit

@Suite("Chunk plan: a long text cut at blank lines for the scratchpad (#84)")
struct ChunkPlanTests {

    private let one = String(repeating: "a", count: 10)
    private let two = String(repeating: "b", count: 10)
    private let three = String(repeating: "c", count: 10)

    @Test("a short text is one chunk")
    func short() {
        let plan = ChunkPlan("Hallo zusammen.\nWie geht es?")
        #expect(plan.chunks == ["Hallo zusammen.\nWie geht es?"])
        #expect(plan.separators.isEmpty)
        #expect(plan.leading.isEmpty)
        #expect(plan.trailing.isEmpty)
    }

    @Test("paragraphs are packed while they fit, separators included")
    func packs() {
        let text = one + "\n\n" + two + "\n\n" + three
        let plan = ChunkPlan(text, limit: 22)
        #expect(plan.chunks == [one + "\n\n" + two, three])
        #expect(plan.separators == ["\n\n"])
    }

    @Test("exactly at the limit still fits; one over does not")
    func boundary() {
        let text = one + "\n\n" + two
        #expect(ChunkPlan(text, limit: 22).chunks.count == 1)
        #expect(ChunkPlan(text, limit: 21).chunks.count == 2)
    }

    @Test("a paragraph longer than the limit is a chunk of its own, never cut")
    func longParagraph() {
        let long = String(repeating: "x", count: 50)
        let plan = ChunkPlan(one + "\n\n" + long + "\n\n" + two, limit: 20)
        #expect(plan.chunks == [one, long, two])
    }

    @Test("lines without a blank line between them stay one paragraph")
    func lines() {
        let text = one + "\n" + two + "\n" + three
        let plan = ChunkPlan(text, limit: 5)
        #expect(plan.chunks == [text])
    }

    @Test("a whitespace-only line counts as blank")
    func whitespaceLine() {
        let plan = ChunkPlan(one + "\n  \t\n" + two, limit: 10)
        #expect(plan.chunks == [one, two])
        #expect(plan.separators == ["\n  \t\n"])
    }

    @Test("leading and trailing blank lines are kept outside the chunks")
    func edges() {
        let plan = ChunkPlan("\n\n" + one + "\n\n\n", limit: 100)
        #expect(plan.leading == "\n\n")
        #expect(plan.chunks == [one])
        #expect(plan.trailing == "\n\n\n")
    }

    @Test("joining the chunks themselves rebuilds the text byte for byte", arguments: [
        "",
        "\n\n",
        "eins",
        "eins\n",
        "eins\n\nzwei",
        "\n eins\n  - zwei\n\n\n\tdrei\n \n",
        "eins\r\n\r\nzwei\r\n",
        "eins\n\n  \nzwei   \n\nvier",
    ])
    func roundTrip(_ text: String) {
        for limit in [1, 4, 8, 1_500] {
            let plan = ChunkPlan(text, limit: limit)
            #expect(plan.join(plan.chunks) == text)
        }
    }

    @Test("CRLF line breaks are kept as they are")
    func crlf() {
        let plan = ChunkPlan("eins\r\n\r\nzwei", limit: 4)
        #expect(plan.chunks == ["eins", "zwei"])
        #expect(plan.separators == ["\r\n\r\n"])
    }

    @Test("results go back between the separators")
    func join() {
        let plan = ChunkPlan("\n" + one + "\n\n" + two + "\n", limit: 10)
        #expect(plan.join(["A", "B"]) == "\nA\n\nB\n")
    }

    @Test("a partial result has the chunks so far and no trailing part")
    func partial() {
        let plan = ChunkPlan("\n" + one + "\n\n" + two + "\n\n" + three + "\n", limit: 10)
        #expect(plan.join([]) == "\n")
        #expect(plan.join(["A"]) == "\nA")
        #expect(plan.join(["A", "B"]) == "\nA\n\nB")
    }

    @Test("a blank text has no chunks")
    func blank() {
        let plan = ChunkPlan(" \n\n")
        #expect(plan.chunks.isEmpty)
        #expect(plan.leading == " \n\n")
    }

    @Test("the whole plan is the text as one chunk")
    func whole() {
        let text = "\n" + one + "\n\n" + two + "\n"
        let plan = ChunkPlan.whole(text)
        #expect(plan.chunks == [text])
        #expect(plan.join(["R"]) == "R")
    }

    @Test("the default limit is the spec's 1,500 characters")
    func defaultLimit() {
        #expect(ChunkPlan.defaultLimit == 1_500)
        let paragraph = String(repeating: "w", count: 700)
        let text = [paragraph, paragraph, paragraph].joined(separator: "\n\n")
        #expect(ChunkPlan(text).chunks.count == 2)
    }
}
