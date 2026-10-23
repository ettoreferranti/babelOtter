import Foundation
import Testing

/// No file in the repository carries a release signing secret or the identity
/// behind it.
///
/// Release builds are signed with a team Developer ID, and the team's name is
/// in the identity ("Developer ID Application: <Team> (<TEAMID>)"). This
/// repository is public, so `Tools/release.sh` finds the identity in the
/// keychain by its prefix alone and notarytool reads its credentials from a
/// keychain profile. Nothing that names the signer is ever written down here.
///
/// Refused: a signing identity's prefix followed by a name; a team ID, whether
/// in parentheses, after `--team-id` or assigned to `TEAM_ID` /
/// `DEVELOPMENT_TEAM`; and an address after `--apple-id`. A team ID is ten
/// capitals and digits with at least one of each, so "(DEPRECATED)" passes.
/// Placeholders such as `--apple-id …` and the bare prefix in quotes pass.
///
/// The files are the ones git tracks or would track (`git ls-files --cached
/// --others --exclude-standard`), every one that decodes as UTF-8, so no
/// extension list can leave a file unscanned.
@Suite("Privacy: no release signing secrets")
struct ReleaseSecretsTests {

    private static let teamID = #"(?=[A-Z0-9]*[0-9])(?=[A-Z0-9]*[A-Z])[A-Z0-9]{10}"#

    /// The pure scanner: which of the shapes occur in `text`.
    static func findings(in text: String) -> [String] {
        let patterns = [
            ("a named signing identity",
             #"(Developer ID (Application|Installer)|Apple (Development|Distribution)):[ \t ]*[\p{L}\p{N}]"#),
            ("a team ID", #"\("# + teamID + #"\)"#),
            ("a team ID", #"--team-id[ =]+["']?"# + teamID + #"\b"#),
            ("a team ID", #"(TEAM_ID|DEVELOPMENT_TEAM)\s*[=:]\s*["']?"# + teamID + #"\b"#),
            ("an Apple ID address", #"--apple-id[ =]+["']?[^ "'\n]*@"#),
        ]
        var found: [String] = []
        for (name, pattern) in patterns
        where !found.contains(name) && text.range(of: pattern, options: .regularExpression) != nil {
            found.append(name)
        }
        return found
    }

    /// Paths relative to the repository root, from git.
    private static func repositoryFiles() throws -> [String] {
        let git = Process()
        git.executableURL = URL(filePath: "/usr/bin/git")
        git.arguments = ["ls-files", "-z", "--cached", "--others", "--exclude-standard"]
        git.currentDirectoryURL = SourceTree.repositoryRoot
        let output = Pipe()
        git.standardOutput = output
        try git.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        guard git.terminationStatus == 0 else { return [] }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\u{0}")
            .map(String.init)
    }

    @Test("no file names a signing identity, team ID or Apple ID")
    func repositoryHoldsNoSigningSecrets() throws {
        let root = SourceTree.repositoryRoot
        var offenders: [String] = []
        var scanned = 0
        for path in try Self.repositoryFiles() {
            // This file holds the planted examples by necessity.
            guard !path.hasSuffix("ReleaseSecretsTests.swift") else { continue }
            guard let contents = try? String(contentsOf: root.appending(path: path), encoding: .utf8)
            else { continue }
            scanned += 1
            let found = Self.findings(in: contents)
            if !found.isEmpty {
                offenders.append("\(path): \(found.joined(separator: ", "))")
            }
        }

        // A listing that came back empty would leave the guard green and absent.
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
            == ["a named signing identity", "a team ID"])
        #expect(Self.findings(in: "identity: Developer ID Application:Norda") == ["a named signing identity"])
        #expect(Self.findings(in: "Developer ID Application:\t\u{00C4}rni AG") == ["a named signing identity"])
        #expect(Self.findings(in: "Developer ID Installer: Norda Labs") == ["a named signing identity"])
        #expect(Self.findings(in: "Apple Development: Jane Example") == ["a named signing identity"])
        #expect(Self.findings(in: "team (Q9W8E7R6T5) here") == ["a team ID"])
        #expect(Self.findings(in: "xcrun notarytool store-credentials p --team-id AB12CD34EF") == ["a team ID"])
        #expect(Self.findings(in: "--team-id=\"AB12CD34EF\"") == ["a team ID"])
        #expect(Self.findings(in: "DEVELOPMENT_TEAM = AB12CD34EF") == ["a team ID"])
        #expect(Self.findings(in: "TEAM_ID: 'AB12CD34EF'") == ["a team ID"])
        #expect(Self.findings(in: "xcrun notarytool store-credentials p --apple-id jane@example.org")
            == ["an Apple ID address"])
        #expect(Self.findings(in: #"--apple-id="jane@example.org""#) == ["an Apple ID address"])
    }

    @Test("the scanner passes placeholders, the bare prefix and ordinary words")
    func scannerPassesPlaceholders() {
        #expect(Self.findings(in: #"grep -F "Developer ID Application:" ids"#).isEmpty)
        #expect(Self.findings(in: #"awk '/"Developer ID Application:/ { print $2 }'"#).isEmpty)
        #expect(Self.findings(in: "--apple-id … --team-id …").isEmpty)
        #expect(Self.findings(in: "(see #82) (ab12cd34ef) (SHORT) (DEPRECATED) (UNVERIFIED) (1234567890)").isEmpty)
    }
}
