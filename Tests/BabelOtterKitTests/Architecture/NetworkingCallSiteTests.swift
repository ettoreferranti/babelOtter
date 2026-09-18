import Testing
import Foundation

/// NFR-P4: exactly one file in the package may touch the network, and it must
/// route through `OllamaEndpoint`. A second call site is how accidental egress
/// gets introduced, so CI refuses one.
@Suite("Architecture: one networking call site")
struct NetworkingCallSiteTests {

    /// Symbols that can open a socket. Substring matching is intentional: it is
    /// better to flag a comment mentioning URLSession than to miss a real call.
    ///
    /// `connect(`, `send(`, and `recv(` are generic enough to collide with an
    /// unrelated method of the same name on a local type. That is accepted
    /// deliberately: over-matching is the safe direction here — a false positive
    /// costs one allowlist line and is loud, a false negative is silent. If one of
    /// these trips on non-networking code, the fix is an allowlist entry plus
    /// review, not deleting the symbol.
    static let networkingSymbols = [
        "URLSession", "URLRequest", "URLDownload", "NSURLConnection",
        "NWConnection", "NWBrowser", "NWListener",
        "CFSocket", "CFReadStream", "CFWriteStream", "import Network",
        "getaddrinfo", "getStreamsToHost", "NetService",
        "socket(", "connect(", "send(", "recv(",
    ]

    static func allowlist() throws -> Set<String> {
        let url = SourceTree.repositoryRoot.appending(path: "Config/networking-allowlist.txt")
        return Set(
            try SourceTree.read(url)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        )
    }

    /// A symbol that matches nothing (or that is a strict substring of another
    /// entry, so it never distinguishes anything the other entry doesn't already
    /// catch) is a silent hole in `networkingSymbols` — `"CFStream"` was exactly
    /// this: intended to catch `CFReadStream`/`CFWriteStream`, but not a
    /// contiguous substring of either, so it matched nothing. This check would
    /// have caught nothing else in today's list, but keeping the list well-formed
    /// is cheap insurance against the next edit reintroducing that mistake.
    @Test("the networking symbol list has no dud entries")
    func networkingSymbolListIsWellFormed() {
        let symbols = Self.networkingSymbols

        for symbol in symbols {
            #expect(!symbol.isEmpty, "networkingSymbols contains an empty string, which would match every file")
        }

        for a in symbols {
            for b in symbols where b != a {
                #expect(
                    !b.contains(a),
                    Comment(rawValue:
                        "\"\(a)\" is a strict substring of \"\(b)\" — anything matching "
                        + "\"\(b)\" already matches \"\(a)\", so \"\(a)\" never distinguishes "
                        + "anything on its own. Remove the redundant entry."
                    )
                )
            }
        }
    }

    @Test("no file outside the allowlist references networking APIs")
    func onlyAllowlistedFilesTouchTheNetwork() throws {
        let permitted = try Self.allowlist()
        var violations: [String] = []

        for file in try SourceTree.allSourceFiles() {
            let path = SourceTree.relativePath(file)
            guard !permitted.contains(path) else { continue }

            let contents = try SourceTree.read(file)
            let found = Self.networkingSymbols.filter { contents.contains($0) }
            if !found.isEmpty {
                violations.append("\(path) references \(found.joined(separator: ", "))")
            }
        }

        #expect(
            violations.isEmpty,
            """
            babelOtter opens no non-loopback connection (NFR-P2/P4), and that is
            provable only while a single, reviewed call site exists.

            Route this through the existing OllamaClient, or — if you genuinely
            need a new call site — add it to Config/networking-allowlist.txt in a
            commit that explains why, and make it use OllamaEndpoint.

            Violations:
            \(violations.joined(separator: "\n"))
            """
        )
    }

    @Test("the allowlist stays at a single entry")
    func allowlistDoesNotGrow() throws {
        let permitted = try Self.allowlist()
        #expect(
            permitted.count <= 1,
            Comment(rawValue:
                "The allowlist has grown to \(permitted.count) entries: \(permitted.sorted()). "
                + "One reviewed call site is what makes NFR-P4 checkable."
            )
        )
    }

    @Test("allowlisted paths that exist route through OllamaEndpoint")
    func allowlistedFilesUseTheEndpointType() throws {
        for path in try Self.allowlist() {
            let url = SourceTree.repositoryRoot.appending(path: path)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue  // not written yet — M1a adds OllamaClient
            }
            let contents = try SourceTree.read(url)
            #expect(
                contents.contains("OllamaEndpoint"),
                Comment(rawValue:
                    "\(path) may touch the network, so it must build its URL from "
                    + "OllamaEndpoint — that type is what makes a non-loopback "
                    + "destination unrepresentable."
                )
            )
        }
    }
}
