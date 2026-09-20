import Foundation
import Testing

@testable import BabelOtterKit

/// Every file in the mutation-tested core must be pure ASCII.
///
/// This is a workaround for a muter defect, not a style preference, and it is a
/// test rather than a convention because the failure it prevents is silent.
///
/// muter locates each mutation by a UTF-8 byte offset and then splices the
/// replacement using a character index. The two agree only while the file is
/// ASCII. One three-byte character earlier in the file shifts every later splice
/// by two, and the damage takes two forms:
///
/// - **Loud.** The mutant does not compile. Observed as
///   `best.value >= floor` becoming `best.value >=<= oor`, which ate two
///   characters of `floor`. Because muter compiles every mutant for a file into
///   one binary, a single bad splice makes the whole file unmeasurable.
/// - **Quiet, and worse.** The mutant compiles but changes something other than
///   what was intended -- often something inert. muter then reports it as a
///   *survivor*, and the score drops for a mutation that was never really
///   applied. Chasing those phantom survivors with new tests achieves nothing,
///   because the tests are already correct.
///
/// Both were observed on this package on 2026-09-20: the core measured 66% with
/// eighteen survivors and two build errors, and every one of them was an
/// artefact. Hand-planting the same mutations showed the existing tests killed
/// them.
///
/// Non-ASCII that the code genuinely needs is written as an escape --
/// `"\u{27E6}"` for the sentinel bracket, `"\u{00DF}"` for the eszett -- which
/// produces an identical string from an ASCII source file.
@Suite("Architecture: the mutated core is ASCII-only")
struct AsciiSourceTests {

    @Test("no file in BabelOtterKit contains a non-ASCII character")
    func coreIsAscii() throws {
        var offenders: [String] = []

        for url in try SourceTree.swiftFiles(inTarget: "BabelOtterKit") {
            let contents = try SourceTree.read(url)
            for (number, line) in contents.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
            {
                let found = Self.nonASCII(in: String(line))
                guard !found.isEmpty else { continue }
                offenders.append(
                    "\(SourceTree.relativePath(url)):\(number + 1) contains \(found)")
            }
        }

        #expect(
            offenders.isEmpty,
            """
            muter mis-splices mutations in files containing non-ASCII characters,
            which both breaks the build for some mutants and silently reports
            others as survivors that were never applied. Write the character as
            an escape -- "\\u{27E6}" rather than the glyph -- or use an ASCII
            spelling in prose.

            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The scanner has to be able to find what it claims to look for.
    ///
    /// Without this, a scanner that returned `[]` unconditionally would leave the
    /// suite green and the guarantee absent -- the exact shape of defect that
    /// shipped twelve times during M0.
    @Test(
        "the scanner detects the characters it exists to catch",
        arguments: [
            ("plain ascii line", false),
            ("an em dash \u{2014} here", true),
            ("the eszett \u{00DF}", true),
            ("a sentinel \u{27E6}DNT0\u{27E7}", true),
            ("a section sign \u{00A7}7", true),
            ("an escape written as \\u{27E6} is ascii", false),
            ("", false),
        ]
    )
    func scannerDetects(_ line: String, _ expected: Bool) {
        #expect(!Self.nonASCII(in: line).isEmpty == expected)
    }

    private static func nonASCII(in line: String) -> [String] {
        line.unicodeScalars
            .filter { $0.value > 127 }
            .map { String(format: "U+%04X", $0.value) }
    }
}
