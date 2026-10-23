import Foundation
import Testing

/// No tracked file carries a release signing secret or the identity behind it.
///
/// Release builds are signed with a team Developer ID, and the team's name is
/// in the identity ("Developer ID Application: <Team> (<TEAMID>)"). This
/// repository is public, so `Tools/release.sh` finds the identity in the
/// keychain by its prefix alone and notarytool reads its credentials from a
/// keychain profile. Nothing that names the signer is ever written down here.
///
/// Three shapes are refused: the identity prefix followed by a name, a
/// parenthesised ten-character team ID, and an address after `--apple-id`.
/// Placeholders such as `--apple-id …` and the bare prefix in quotes pass.
@Suite("Privacy: no release signing secrets")
struct ReleaseSecretsTests {

    /// The pure scanner: which of the three shapes occur in `text`.
    static func findings(in text: String) -> [String] {
        let patterns = [
            ("a named Developer ID identity", #"Developer ID Application: *[A-Za-z0-9]"#),
            ("a team ID", #"\([A-Z0-9]{10}\)"#),
            ("an Apple ID address", #"--apple-id[ =]+["']?[^ "'\n]*@"#),
        ]
        var found: [String] = []
        for (name, pattern) in patterns where text.range(of: pattern, options: .regularExpression) != nil {
            found.append(name)
        }
        return found
    }

    private static let scannedExtensions: Set<String> = [
        "swift", "md", "yml", "yaml", "txt", "json", "sh", "plist", "html", "",
    ]

    private static let skippedDirectories: Set<String> = [
        ".git", ".build", ".superpowers", "DerivedData", "build",
    ]

    @Test("no tracked file names a signing identity, team ID or Apple ID")
    func repositoryHoldsNoSigningSecrets() throws {
        let root = SourceTree.repositoryRoot
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else {
            Issue.record("could not walk the repository")
            return
        }

        var offenders: [String] = []
        var scanned = 0
        for case let url as URL in walker {
            if Self.skippedDirectories.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            guard Self.scannedExtensions.contains(url.pathExtension) else { continue }
            // This file holds the planted examples by necessity.
            guard url.lastPathComponent != "ReleaseSecretsTests.swift" else { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            let found = Self.findings(in: contents)
            if !found.isEmpty {
                offenders.append("\(SourceTree.relativePath(url)): \(found.joined(separator: ", "))")
            }
        }

        // A walker that matched nothing would leave the guard green and absent.
        #expect(scanned > 100)
        #expect(
            offenders.isEmpty,
            """
            The repository is public and release builds are signed by a team
            whose name must not appear here. Find the identity in the keychain
            and keep credentials in a notarytool keychain profile.

            \(offenders.joined(separator: "\n"))
            """)
    }

    @Test("the scanner finds each planted shape")
    func scannerFindsPlantedShapes() {
        #expect(Self.findings(in: #"codesign --sign "Developer ID Application: Norda Labs (AB12CD34EF)""#)
            == ["a named Developer ID identity", "a team ID"])
        #expect(Self.findings(in: "identity: Developer ID Application:Norda") == ["a named Developer ID identity"])
        #expect(Self.findings(in: "team (Q9W8E7R6T5) here") == ["a team ID"])
        #expect(Self.findings(in: "xcrun notarytool store-credentials p --apple-id jane@example.org")
            == ["an Apple ID address"])
        #expect(Self.findings(in: #"--apple-id="jane@example.org""#) == ["an Apple ID address"])
    }

    @Test("the scanner passes placeholders and the bare prefix")
    func scannerPassesPlaceholders() {
        #expect(Self.findings(in: #"grep -F "Developer ID Application:" ids"#).isEmpty)
        #expect(Self.findings(in: "--apple-id … --team-id …").isEmpty)
        #expect(Self.findings(in: "(see #82) (ab12cd34ef) (SHORT)").isEmpty)
    }
}
