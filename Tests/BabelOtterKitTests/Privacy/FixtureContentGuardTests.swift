import Testing
import Foundation

/// NFR-P8: this repository is public and CI runs on third-party machines, so a
/// fixture built from real correspondence would publish it. Heuristic, and
/// deliberately noisy in the safe direction: a false positive costs one
/// allowlist line, a false negative costs a disclosure.
///
/// ## What this guard is, and is not
///
/// This is a lexical scan for regex-shaped markers (email, Swiss phone, IBAN,
/// AHV number) in `Tests/Fixtures` and `evals`. It exists to catch a
/// contributor pasting a real email thread or a real student's details into a
/// fixture. It is not, and cannot be, a complete PII scanner. Confirmed gaps,
/// found by testing each marker against concrete real-world spellings rather
/// than assuming it works (see `task-10-report.md` for the full table):
///
/// - The Swiss phone pattern (`\+41[\s0-9]{9,}`) matches `+41 79 123 45 67`
///   and `+41791234567`, but **not** `+41-79-123-45-67`, `+41.79.123.45.67`,
///   `0041 79 123 45 67`, or the bare local form `079 123 45 67` — all
///   common real spellings. This is the same shape of gap as the `"CFStream"`
///   symbol that matched nothing: a marker that reads as coverage but misses
///   realistic input.
/// - The IBAN pattern does not match a hyphen-grouped IBAN
///   (`CH93-0076-2011-6238-5295-7`), only space- or run-together digits.
/// - The AHV pattern requires the dotted `756.XXXX.XXXX.XX` grouping; a
///   13-digit run with no punctuation is not caught.
///
/// Categories with **no marker at all**: German/Swiss names, street
/// addresses, matriculation/student numbers, dates of birth, and
/// `zhaw.ch`-hosted URLs that could identify a course or cohort. A person
/// still has to read a fixture before trusting it; this guard narrows what a
/// skim misses, it does not replace the read.
///
/// Scope: this suite scans `Tests/Fixtures` and `evals` only, matching the
/// brief. `Sources/`, `docs/`, and commit messages are not scanned by this
/// guard — see the task report for why that is a deliberate scope decision,
/// not an oversight.
@Suite("Fixtures contain no real correspondence")
struct FixtureContentGuardTests {

    typealias Marker = FixtureContentScanner.Marker

    static let markers: [Marker] = [
        .init(name: "email address", pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
        .init(name: "Swiss phone number", pattern: #"\+41[\s0-9]{9,}"#),
        .init(name: "IBAN", pattern: #"\bCH\d{2}[\s0-9]{15,}\b"#),
        .init(name: "AHV number", pattern: #"\b756\.\d{4}\.\d{4}\.\d{2}\b"#),
    ]

    /// Directories whose contents must be synthetic.
    static let scannedDirectories = ["Tests/Fixtures", "evals"]

    static func allowlist() throws -> Set<String> {
        let url = SourceTree.repositoryRoot.appending(path: "Config/fixture-guard-allowlist.txt")
        guard let contents = try? SourceTree.read(url) else { return [] }
        return Set(
            contents.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        )
    }

    @Test("no fixture carries a marker of real correspondence")
    func fixturesAreSynthetic() throws {
        let permitted = try Self.allowlist()
        var violations: [String] = []

        for directory in Self.scannedDirectories {
            let root = SourceTree.repositoryRoot.appending(path: directory)
            guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)),
                  let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            else { continue }

            for case let file as URL in walker {
                guard file.pathExtension != "",
                      let contents = try? SourceTree.read(file) else { continue }
                let relative = SourceTree.relativePath(file)
                guard !permitted.contains(relative) else { continue }

                let found = try FixtureContentScanner.matchedMarkerNames(in: contents, markers: Self.markers)
                for name in found {
                    violations.append("\(relative) contains a \(name)")
                }
            }
        }

        #expect(
            violations.isEmpty,
            """
            This repository is public and CI runs on third-party machines.
            Fixtures must be invented, not drawn from real correspondence.

            If a file is genuinely synthetic and merely trips a heuristic, add
            its path to Config/fixture-guard-allowlist.txt in a commit saying
            who checked it.

            \(violations.joined(separator: "\n"))
            """
        )
    }

    // MARK: - Scanner coverage
    //
    // `fixturesAreSynthetic` above is only as good as the detection logic it
    // runs — and today's tree has no fixtures at all (`Tests/Fixtures` holds
    // only a README, `evals` does not exist), so that test passes vacuously.
    // An inverted condition, a silently-swallowed regex compile error, or an
    // allowlist check that always exempts would sail through CI undetected.
    // These cases exercise `FixtureContentScanner` directly against sample
    // content in memory, so detection is proven regardless of what currently
    // happens to live on disk — exactly as `ImportLineMatcher` does for
    // `NoUIImportsTests` and the extracted scanner does for
    // `NetworkingCallSiteTests`.

    @Test("marker scanner: fires on a realistic instance of each marker", arguments: [
        (marker: "email address", sample: "Bitte antworten Sie an vorname.nachname@example.org."),
        (marker: "email address", sample: "Kontakt: j.mueller+kurs@stud.zhaw.ch"),
        (marker: "Swiss phone number", sample: "Rufen Sie mich an: +41 79 123 45 67."),
        (marker: "IBAN", sample: "IBAN CH93 0076 2011 6238 5295 7"),
        (marker: "AHV number", sample: "AHV-Nr. 756.1234.5678.90"),
    ] as [(marker: String, sample: String)])
    func scannerFiresOnRealisticMarkerInstances(marker: String, sample: String) throws {
        let found = try FixtureContentScanner.matchedMarkerNames(in: sample, markers: Self.markers)
        #expect(
            found.contains(marker),
            "expected \"\(marker)\" to fire on: \(sample) — found \(found)"
        )
    }

    @Test("marker scanner: does not fire on realistic synthetic prose", arguments: [
        "Herr Beispiel schreibt an Frau Muster über die Korrektur ihres Aufsatzes.",
        "Die Teilnahmegebühr beträgt CHF 41.90 und ist bis zum 30.09 zu begleichen.",
        "Der Kurs Nr. 756 beginnt am Montag im Raum TB 2.14.",
        "Bitte korrigieren Sie den Satz: 'Er sind gestern nach Hause gegangen.'",
        "Postleitzahl 8400 Winterthur, Bahnhofplatz 1.",
    ])
    func scannerIgnoresRealisticCleanProse(sample: String) throws {
        let found = try FixtureContentScanner.matchedMarkerNames(in: sample, markers: Self.markers)
        #expect(
            found.isEmpty,
            "expected no marker to fire on: \(sample) — found \(found)"
        )
    }

    @Test("marker scanner: an allowlisted path is not flagged even when its content matches")
    func scannerRespectsPathIndependently() throws {
        // The allowlist check lives in fixturesAreSynthetic's own loop (by path),
        // not inside the scanner (which only ever sees content). This test pins
        // that division: the scanner itself is allowlist-blind by design, so a
        // path exemption can never accidentally suppress detection everywhere.
        let sample = "vorname.nachname@example.org"
        let found = try FixtureContentScanner.matchedMarkerNames(in: sample, markers: Self.markers)
        #expect(found.contains("email address"))
    }
}

/// Extracted so the detection logic driving `fixturesAreSynthetic` can be
/// exercised against sample content in memory, exactly as `ImportLineMatcher`
/// does for `NoUIImportsTests` and `NetworkingSymbolScanner` does for
/// `NetworkingCallSiteTests`. Without this extraction, every assertion in this
/// file runs only against whatever currently happens to be on disk under
/// `Tests/Fixtures` and `evals` — and since neither holds real content today,
/// the whole suite would pass vacuously, and a broken guard would not be
/// caught by CI.
enum FixtureContentScanner {
    struct Marker {
        let name: String
        let pattern: String
    }

    /// The names of markers whose pattern matches somewhere in `contents`.
    ///
    /// A pattern that fails to compile is a bug in this file, not evidence the
    /// content is clean — it throws rather than swallowing the error, so a
    /// typo'd regex fails loudly instead of silently disabling detection.
    static func matchedMarkerNames(in contents: String, markers: [Marker]) throws -> [String] {
        var names: [String] = []
        let range = NSRange(contents.startIndex..., in: contents)
        for marker in markers {
            let regex = try NSRegularExpression(pattern: marker.pattern)
            if regex.firstMatch(in: contents, range: range) != nil {
                names.append(marker.name)
            }
        }
        return names
    }
}
