import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Structure survives the round trip")
struct StructureExtractorTests {

    /// The property that matters: extract, re-apply unchanged, get the input
    /// back byte for byte — for every shape of text we claim to support.
    @Test(
        "extract then re-apply unchanged is byte-identical",
        arguments: [
            "Hello world.",
            "First paragraph.\n\nSecond paragraph.",
            "- one\n- two\n- three",
            "* star\n+ plus",
            "1. one\n2. two\n10. ten",
            "a) alpha\nb) beta",
            "    indented\n        more indented",
            "crlf line one\r\ncrlf line two\r\n",
            "mixed\r\nendings\nhere",
            "trailing whitespace   \nand a final newline\n",
            "no trailing newline",
            "\n\n\n",
            "",
            "   ",
            "  - indented bullet\n  - another",
            "-5 degrees is prose, not a bullet",
            "Ünïcödé — em dash, ß, and 🦦 emoji",
            "tabs\tinside\tprose",
            "\tleading tab",
        ]
    )
    func roundTripIsIdentity(_ input: String) throws {
        let extracted = StructureExtractor.extract(input)
        #expect(try StructureExtractor.reapply(extracted.blocks, to: extracted.skeleton) == input)
    }

    @Test("list markers are preserved and never sent to the model as prose")
    func markersAreNotProse() {
        #expect(StructureExtractor.extract("- one\n- two").blocks == ["one", "two"])
    }

    @Test("numbered and lettered markers are not prose either")
    func numberedMarkers() {
        #expect(StructureExtractor.extract("1. one\n2. two").blocks == ["one", "two"])
        #expect(StructureExtractor.extract("a) alpha\nb) beta").blocks == ["alpha", "beta"])
    }

    @Test("a hyphen not followed by a space is prose")
    func hyphenIsNotAlwaysAMarker() {
        #expect(StructureExtractor.extract("-5 degrees").blocks == ["-5 degrees"])
    }

    @Test("a number not followed by a space is prose")
    func numberIsNotAlwaysAMarker() {
        #expect(StructureExtractor.extract("1.5 metres").blocks == ["1.5 metres"])
    }

    @Test("indentation is preserved per line and kept out of the blocks")
    func indentationPreserved() throws {
        let extracted = StructureExtractor.extract("    four\n        eight")
        #expect(extracted.blocks == ["four", "eight"])
        #expect(
            try StructureExtractor.reapply(["vier", "acht"], to: extracted.skeleton)
                == "    vier\n        acht")
    }

    @Test("trailing whitespace stays on the line and out of the block")
    func trailingWhitespaceIsStructure() throws {
        let extracted = StructureExtractor.extract("hello   ")
        #expect(extracted.blocks == ["hello"])
        #expect(try StructureExtractor.reapply(["hallo"], to: extracted.skeleton) == "hallo   ")
    }

    @Test("blank lines produce no blocks")
    func blankLinesAreNotBlocks() {
        #expect(StructureExtractor.extract("one\n\n\ntwo").blocks == ["one", "two"])
    }

    @Test("a whitespace-only line is structure, not a block")
    func whitespaceOnlyLine() {
        #expect(StructureExtractor.extract("one\n   \ntwo").blocks == ["one", "two"])
    }

    @Test("translated blocks land in the right slots")
    func blocksLandInOrder() throws {
        let extracted = StructureExtractor.extract("- one\n\n- two")
        #expect(
            try StructureExtractor.reapply(["eins", "zwei"], to: extracted.skeleton)
                == "- eins\n\n- zwei")
    }

    @Test("a marker with no prose after it keeps its marker and makes no block")
    func markerWithoutProse() throws {
        let extracted = StructureExtractor.extract("- \n- two")
        #expect(extracted.blocks == ["two"])
        #expect(try StructureExtractor.reapply(["zwei"], to: extracted.skeleton) == "- \n- zwei")
    }

    @Test("CRLF endings are restored exactly, per line")
    func crlfPreserved() throws {
        let extracted = StructureExtractor.extract("one\r\ntwo\r\n")
        #expect(extracted.blocks == ["one", "two"])
        #expect(
            try StructureExtractor.reapply(["eins", "zwei"], to: extracted.skeleton)
                == "eins\r\nzwei\r\n")
    }

    @Test("too few blocks is an error, never a silent truncation")
    func tooFewBlocks() {
        let extracted = StructureExtractor.extract("one\ntwo")
        #expect(throws: StructureError.blockCountMismatch(expected: 2, received: 1)) {
            try StructureExtractor.reapply(["eins"], to: extracted.skeleton)
        }
    }

    @Test("too many blocks is an error too")
    func tooManyBlocks() {
        let extracted = StructureExtractor.extract("one")
        #expect(throws: StructureError.blockCountMismatch(expected: 1, received: 2)) {
            try StructureExtractor.reapply(["eins", "zwei"], to: extracted.skeleton)
        }
    }

    @Test("blockCount agrees with the number of blocks produced")
    func blockCountAgrees() {
        let extracted = StructureExtractor.extract("- one\n\n- two\n- three")
        #expect(extracted.skeleton.blockCount == extracted.blocks.count)
        #expect(extracted.skeleton.blockCount == 3)
    }

    @Test("text with no prose at all yields no blocks and still round-trips")
    func noProse() throws {
        let extracted = StructureExtractor.extract("\n\n")
        #expect(extracted.blocks.isEmpty)
        #expect(extracted.skeleton.blockCount == 0)
        #expect(try StructureExtractor.reapply([], to: extracted.skeleton) == "\n\n")
    }
}
