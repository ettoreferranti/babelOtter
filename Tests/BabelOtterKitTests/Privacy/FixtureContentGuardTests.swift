import Testing
import Foundation

/// NFR-P8: this repository is public and CI runs on third-party machines, so a
/// fixture built from real correspondence would publish it. Heuristic, and
/// deliberately noisy in the safe direction: a false positive costs one
/// allowlist line, a false negative costs a disclosure.
///
/// ## What this guard is, and is not
///
/// This guard catches exactly four machine-recognisable, regex-shaped
/// markers — an email address, a Swiss phone number, an IBAN, an AHV
/// number — in every file under `Tests/Fixtures` or `evals` **that decodes
/// as UTF-8 text**. That is the entire list. State it plainly, because a
/// guard that reads as more than it is trains people to trust it more than
/// it deserves:
///
/// **A file that does not decode as UTF-8 is not scanned — and is reported
/// as unscannable rather than skipped.** `.docx`, `.pdf`, `.eml`,
/// screenshots (NFR-P8 names them explicitly) and UTF-16 text — which is
/// what Word and TextEdit produce on export — carry no readable marker for
/// a UTF-8 regex scan. The previous version of this suite `continue`d past
/// exactly these, and past every extensionless file as well, and then
/// reported the tree clean while listing nothing: a `.docx`, an
/// extensionless file and a UTF-16 `.txt`, each containing a real email
/// address and phone number, all passed. On a public repo those are the
/// most likely way real correspondence actually arrives. They now fail the
/// suite until a human either removes them or adds them to
/// `Config/fixture-guard-allowlist.txt` — which for a binary fixture is the
/// right answer anyway, since that entry means exactly what the allowlist's
/// header says: a person read the file and confirmed it is synthetic.
///
/// **It does NOT detect names, street addresses, matriculation/student
/// numbers, dates of birth, institutional email domains, or any other free-text personal
/// detail.** None of these are reliably expressible as a regex without
/// either missing real instances or false-positiving on every ordinary
/// sentence a fixture contains (German prose is made of names). No marker
/// exists for them, and none will be added — a marker that fires
/// unpredictably would teach contributors to allowlist reflexively, which
/// destroys this guard's value for the markers it *can* check reliably.
///
/// **This narrows what a careless skim misses. It does not replace a human
/// reading a fixture before committing it.** `Tests/Fixtures/README.md`'s
/// instruction to write only about invented `Frau Muster`/`Herr Beispiel`
/// subjects is still the actual control; this test is a backstop against
/// the specific, mechanical mistake of a real email/phone/IBAN/AHV number
/// slipping through that review, not a substitute for the review itself.
///
/// **The allowlist is for genuine false positives, not for silencing a real
/// finding.** Every entry in `Config/fixture-guard-allowlist.txt` asserts
/// that a specific person read the flagged file and confirmed by hand that
/// it is synthetic; the commit adding an entry should name who did that
/// check.
///
/// Even within its four markers, this guard is not exhaustive — verified
/// against concrete real-world spellings, not assumed (see `task-10-report.md`
/// for the full table and Fix round 1 for the phone/IBAN corrections it
/// prompted):
///
/// - The Swiss phone pattern (fixed in Fix round 1) now matches `+41` and
///   `0041` international prefixes and the bare local `0xx` form, with
///   space, hyphen, dot, or no separator at all. Deliberately over-matching:
///   the bare local form cannot be distinguished from any other 10-digit
///   numeral that happens to start with `0` — confirmed as the one real
///   cost, and accepted, in exchange for not missing the way most Swiss
///   people actually write their own number.
/// - The IBAN pattern (fixed in Fix round 1) now matches hyphen-grouped
///   IBANs alongside the space-grouped and run-together forms it already
///   matched.
/// - The AHV pattern requires the dotted `756.XXXX.XXXX.XX` grouping; a
///   13-digit run with no punctuation is not caught. Left as-is by ruling —
///   widening it risks matching ordinary numbers with no punctuation to
///   anchor on.
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
        // Fix round 1 (Refs #25): the original `\+41[\s0-9]{9,}` only matched
        // one punctuation convention and missed the international `0041`
        // prefix and the bare local `0xx` form entirely — the same shape of
        // gap as the `"CFStream"` symbol that matched nothing, and worse
        // here, since `079 123 45 67` is the single most common way a Swiss
        // person writes their own number. This pattern matches `+41` or
        // `0041` or a lone leading `0`, then nine more digits grouped
        // 2-3-2-2 with space, hyphen, dot, or no separator at all between
        // groups. `(?<!\d)`/`(?!\d)` require the match not be glued to
        // further digits, so it can't fire on a fragment of a longer digit
        // run (an IBAN's digit groups, for instance) — without narrowing
        // what it catches of an actual phone number, since a real phone
        // number is never itself embedded inside a longer numeral.
        // Deliberately over-matching in the safe direction: the local form
        // is indistinguishable from any other bare 10-digit numeral that
        // happens to start with 0 (e.g. a matriculation number in that
        // exact shape) — confirmed as the one real cost, and accepted,
        // because a false positive there costs one allowlist line and is
        // loud, while a false negative on a real phone number costs a
        // disclosure. Tested against a battery of realistic non-phone
        // fixture content (dates, version numbers, room/course codes) that
        // must NOT match — see `scannerIgnoresRealisticCleanProse` — and
        // none of it does; see the task report for the full table.
        .init(
            name: "Swiss phone number",
            pattern: #"(?<!\d)(?:\+41|0041|0)[\s.-]?\d{2}[\s.-]?\d{3}[\s.-]?\d{2}[\s.-]?\d{2}(?!\d)"#
        ),
        // Fix round 1 (Refs #25): widened to also match a hyphen-grouped IBAN
        // (`CH93-0076-2011-6238-5295-7`), alongside the space-grouped and
        // run-together forms it already matched.
        .init(name: "IBAN", pattern: #"\bCH\d{2}[\s0-9-]{15,}\b"#),
        // AHV number: left as-is per ruling. An undotted 13-digit run is a
        // lower-realism gap, and widening this pattern risks matching
        // ordinary numbers with no punctuation to anchor on.
        .init(name: "AHV number", pattern: #"\b756\.\d{4}\.\d{4}\.\d{2}\b"#),
    ]

    /// Directories whose contents must be synthetic.
    static let scannedDirectories = ["Tests/Fixtures", "evals"]

    /// The only filename exempted by name rather than by allowlist entry.
    ///
    /// `.DS_Store` is Finder metadata: binary, regenerated the moment anyone
    /// opens the folder, and already unpublishable because `.gitignore`
    /// refuses it — so it can never reach the public repository this guard
    /// exists to protect. Reporting it as unscannable would fail the suite on
    /// every machine where someone has looked at `Tests/Fixtures` in Finder,
    /// and the only remedy on offer would be an allowlist line: precisely the
    /// reflexive allowlisting this suite's documentation warns destroys the
    /// guard's value. Nothing else is exempted by name — a hidden file that is
    /// *not* `.DS_Store` is scanned like any other.
    static let filenamesExemptedByName: Set<String> = [".DS_Store"]

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
        var unscannable: [String] = []

        for directory in Self.scannedDirectories {
            let root = SourceTree.repositoryRoot.appending(path: directory)
            guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)),
                  let walker = FileManager.default.enumerator(
                      at: root,
                      includingPropertiesForKeys: [.isDirectoryKey]
                  )
            else { continue }

            for case let file as URL in walker {
                // Directories are containers, not content. Everything else is
                // either scanned or reported — a file whose kind cannot even be
                // determined falls through to the unscannable list rather than
                // being skipped, which is the whole point of this rewrite.
                let isDirectory = (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
                guard isDirectory != true else { continue }
                guard !Self.filenamesExemptedByName.contains(file.lastPathComponent) else { continue }

                let relative = SourceTree.relativePath(file)
                guard !permitted.contains(relative) else { continue }

                guard let contents = try? SourceTree.read(file) else {
                    unscannable.append(
                        "\(relative) could not be read as UTF-8 text — "
                        + "the marker scan did not run on it"
                    )
                    continue
                }

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

        #expect(
            unscannable.isEmpty,
            """
            This repository is public and CI runs on third-party machines.

            These files are not UTF-8 text, so no marker scan ran on them at
            all. A binary attachment, a screenshot, a .docx, a .pdf, an .eml,
            or a UTF-16 export is exactly how real correspondence usually
            arrives — and a guard that quietly skipped them while reporting
            the tree clean would be worse than no guard.

            Read each file yourself. If it is genuinely synthetic, add its
            path to Config/fixture-guard-allowlist.txt in a commit saying who
            checked it — for a binary fixture that human check is the only
            control there is.

            \(unscannable.joined(separator: "\n"))
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
        (marker: "email address", sample: "Kontakt: j.mueller+kurs@stud.example.ch"),
        // Swiss phone number: every spelling a person actually writes, per
        // Fix round 1 — international with each separator, international
        // with none, local with each separator, local with none.
        (marker: "Swiss phone number", sample: "Rufen Sie mich an: +41 79 123 45 67."),
        (marker: "Swiss phone number", sample: "Rufen Sie mich an: +41-79-123-45-67."),
        (marker: "Swiss phone number", sample: "Rufen Sie mich an: +41.79.123.45.67."),
        (marker: "Swiss phone number", sample: "Rufen Sie mich an: +41791234567."),
        (marker: "Swiss phone number", sample: "Rufen Sie mich an: 0041 79 123 45 67."),
        (marker: "Swiss phone number", sample: "Rufen Sie mich an: 0041791234567."),
        (marker: "Swiss phone number", sample: "Rufen Sie mich an: 079 123 45 67."),
        (marker: "Swiss phone number", sample: "Rufen Sie mich an: 079-123-45-67."),
        (marker: "Swiss phone number", sample: "Rufen Sie mich an: 0791234567."),
        (marker: "IBAN", sample: "IBAN CH93 0076 2011 6238 5295 7"),
        (marker: "IBAN", sample: "IBAN CH93-0076-2011-6238-5295-7"),
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
        // Fix round 1: the widened bare-local phone shape (a lone leading
        // "0" plus nine more digits) is the part of the pattern that trades
        // away precision for recall, so it gets checked against exactly the
        // kind of short numerals ordinary fixture prose actually contains —
        // dates, versions, course/room numbers — not just clean sentences.
        "Kursnummer 079 2026 startet im Herbstsemester.",
        "Build v0.79.1 behebt einen Darstellungsfehler.",
        "Kurs Nr. 2026-079-123 ist ausgebucht.",
        "Am 07.09.2026 findet die Prüfung statt.",
        "Postfach 079, 8400 Winterthur.",
        // IBAN: a "CH"-prefixed course/date code must not be mistaken for a
        // hyphen-grouped IBAN merely because both start with "CH".
        "CH-2026-01-15 Sprachprüfung, Frau Muster.",
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
