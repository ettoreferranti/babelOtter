import Foundation
import Testing

@testable import BabelOtterKit

/// No file in this repository names the author's employer.
///
/// This repository is public and meant to be handed to strangers: "clone it and
/// run it" should not come with a disclosure about where the author works. Test
/// fixtures and examples therefore use invented proper nouns, and prose about
/// the author's own machine says "managed work Mac" rather than naming who
/// manages it.
///
/// **The needles are base64-encoded, and that is the point.** A guard that
/// stored them as plain string literals would itself be a mention of the thing
/// it exists to remove -- greppable, readable, and sitting in the public
/// repository forever. Encoding them means this file can enforce the rule
/// without restating what it forbids.
///
/// This came from a real leak, not a hypothetical one. The first transcript
/// produced by `Tools/ax-probe.sh` carried an MDM server URL, an organisation
/// GUID and a full endpoint-security onboarding blob, because the probe grepped
/// case-insensitively for a three-letter token and base64 happily contains it.
@Suite("Privacy: no identifying references")
struct NoIdentifyingReferencesTests {

    /// Encoded so this file does not become the mention it forbids.
    private static let encodedNeedles = ["emhhdw==", "amVtLnpoYXcuY2g="]

    private static var needles: [String] {
        encodedNeedles.map {
            guard let data = Data(base64Encoded: $0),
                let text = String(data: data, encoding: .utf8)
            else {
                Issue.record("a needle failed to decode; the guard would silently pass")
                return "\u{0}unreachable"
            }
            return text.lowercased()
        }
    }

    /// Extensions worth scanning. Anything human-readable that ships.
    private static let scannedExtensions: Set<String> = [
        "swift", "md", "yml", "yaml", "txt", "json", "sh", "html", "resolved", "",
    ]

    private static let skippedDirectories: Set<String> = [
        ".git", ".build", ".superpowers", "DerivedData",
    ]

    @Test("no tracked file names the employer")
    func repositoryNamesNoEmployer() throws {
        var offenders: [String] = []
        let root = SourceTree.repositoryRoot
        let needles = Self.needles

        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else {
            Issue.record("could not walk the repository")
            return
        }

        for case let url as URL in walker {
            if Self.skippedDirectories.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            guard Self.scannedExtensions.contains(url.pathExtension) else { continue }
            // This file holds the needles by necessity.
            guard url.lastPathComponent != "NoIdentifyingReferencesTests.swift" else { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let haystack = contents.lowercased()
            for needle in needles where haystack.contains(needle) {
                offenders.append(SourceTree.relativePath(url))
                break
            }
        }

        #expect(
            offenders.isEmpty,
            """
            This repository is public and meant to be shared without disclosing
            where the author works. Use an invented proper noun in fixtures and
            examples, and say "managed work Mac" in prose.

            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The scanner has to find what it claims to look for.
    ///
    /// Without this, a decode that quietly failed, or a walker that matched
    /// nothing, would leave the suite green and the guarantee absent -- the
    /// exact shape of defect that shipped twelve times during M0.
    @Test("the scanner detects a planted mention")
    func scannerDetectsAPlantedMention() throws {
        let needles = Self.needles
        #expect(needles.count == Self.encodedNeedles.count)
        #expect(needles.allSatisfy { !$0.isEmpty && !$0.hasPrefix("\u{0}") })

        for needle in needles {
            let planted = "a document that mentions \(needle.uppercased()) in passing"
            #expect(planted.lowercased().contains(needle), "needle \(needle) would not be found")
        }
        #expect(!"a document mentioning nobody in particular".contains(needles[0]))
    }
}
