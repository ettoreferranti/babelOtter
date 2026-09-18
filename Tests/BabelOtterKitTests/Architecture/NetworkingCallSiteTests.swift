import Testing
import Foundation

/// NFR-P4: exactly one file in the package may touch the network, and it must
/// route through `OllamaEndpoint`. A second call site is how accidental egress
/// gets introduced, so CI refuses one.
///
/// ## What this guard is, and is not
///
/// This is a lexical scan for symbol names in source text. It exists to catch
/// the **accidental** introduction of networking — a contributor reaching for
/// `URLSession` because it is the obvious tool, without noticing the file
/// isn't allowlisted. It is not, and cannot be, a defence against a
/// contributor who is deliberately evading it. A reviewer demonstrated
/// several ways past it, among others:
///
/// - A string assembled at runtime (e.g. `"URL" + "Session"`) and resolved
///   reflectively instead of named directly in source.
/// - `dlsym` to look up a networking symbol by string at runtime.
/// - `@_silgen_name` to bind straight to a C symbol under a name this scan
///   does not recognise.
/// - A `typealias` declared inside the allowlisted file and re-exported, so
///   the call site elsewhere in the tree never spells the banned name.
/// - `Process` shelling out to `curl`, `nc`, or any other binary that opens
///   its own connection entirely outside this process.
///
/// A lexical scan cannot be complete against a determined adversary, and
/// implying otherwise would repeat the `"CFStream"` mistake at a larger
/// scale: coverage this guard doesn't actually provide. The real guarantee —
/// that babelOtter cannot address a non-loopback host — lives in
/// `OllamaEndpoint`, which makes that destination unrepresentable in the
/// type system. This suite is defence in depth on top of that guarantee, not
/// a substitute for it.
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
    ///
    /// `"(contentsOf:"` catches Foundation's `String(contentsOf:)`,
    /// `Data(contentsOf:)`, and `NSData(contentsOf:)` — each performs real
    /// network I/O when given a non-file URL, and each is more idiomatic than
    /// several symbols already in this list. The colon is load-bearing: it
    /// excludes `contentsOfFile:`, whose `String`/local-path overload never
    /// leaves the machine.
    static let networkingSymbols = [
        "URLSession", "URLRequest", "URLDownload", "NSURLConnection",
        "NWConnection", "NWBrowser", "NWListener",
        "CFSocket", "CFReadStream", "CFWriteStream", "import Network",
        "getaddrinfo", "getStreamsToHost", "NetService",
        "socket(", "connect(", "send(", "recv(",
        "(contentsOf:",
    ]

    /// Real API names/spellings that each entry in `networkingSymbols` is
    /// meant to target. This is the check `"CFStream"` needed and never had:
    /// every symbol above must be a substring of *something in here*, or it
    /// is a dud — a list entry that reads as coverage but matches no real
    /// networking API. See `networkingSymbolListIsWellFormed` for how this is
    /// used.
    static let networkingAPIReferenceCorpus = [
        // Foundation URL loading
        "URLSession.shared", "URLSessionConfiguration.default", "URLRequest(url: url)",
        "NSURLDownload(request: request, delegate: self)",
        "NSURLConnection.sendSynchronousRequest(request, returning: &response)",
        // Network.framework
        "NWConnection(host: host, port: port, using: .tcp)",
        "NWBrowser(for: .bonjour(type: \"_http._tcp\", domain: nil), using: parameters)",
        "NWListener(using: .tcp, on: port)",
        // CFNetwork / Core Foundation
        "CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, nil, nil)",
        "CFReadStreamCreateWithFTPURL(kCFAllocatorDefault, ftpURL)",
        "CFWriteStreamCreateWithFTPURL(kCFAllocatorDefault, ftpURL)",
        "import Network",
        // BSD sockets / POSIX
        "getaddrinfo(hostname, service, &hints, &result)",
        "Stream.getStreamsToHost(withName: host, port: port, inputStream: &input, outputStream: &output)",
        // Bonjour
        "NetServiceBrowser().searchForServices(ofType: \"_http._tcp\", inDomain: \"\")",
        "socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)",
        "connect(fd, addr, len)",
        "send(fd, buffer, length, 0)",
        "recv(fd, buffer, length, 0)",
        // Foundation's contentsOf: family
        "String(contentsOf: url, encoding: .utf8)",
        "Data(contentsOf: url)",
        "NSData(contentsOf: url)",
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

    /// The well-formedness check for `networkingSymbols` itself. Two
    /// independent failure modes, both real:
    ///
    /// 1. **Internal redundancy** — an entry that is a strict substring of
    ///    another entry in this same list never distinguishes anything the
    ///    other entry doesn't already catch. Not dangerous, just dead
    ///    weight.
    /// 2. **External validity** — an entry that is not a substring of
    ///    anything in `networkingAPIReferenceCorpus`. This is the check that
    ///    actually would have caught `"CFStream"`: it was not a substring of
    ///    any other list entry (so check 1 passed on the pre-fix list), and
    ///    it was also not a substring of the real APIs it was meant to
    ///    catch — `CFReadStreamCreateWithFTPURL` /
    ///    `CFWriteStreamCreateWithFTPURL` — because `"Read"`/`"Write"` sits
    ///    in between. A reviewer confirmed the redundancy check alone
    ///    passes against the pre-fix list containing `"CFStream"`; check 2
    ///    is what closes that gap.
    @Test("the networking symbol list has no dud entries")
    func networkingSymbolListIsWellFormed() {
        let symbols = Self.networkingSymbols
        let corpus = Self.networkingAPIReferenceCorpus

        for symbol in symbols {
            #expect(!symbol.isEmpty, "networkingSymbols contains an empty string, which would match every file")
        }

        // Check 1: internal redundancy.
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

        // Check 2: external validity — every symbol must match something real.
        for symbol in symbols {
            let matchesSomethingReal = corpus.contains { $0.contains(symbol) }
            #expect(
                matchesSomethingReal,
                Comment(rawValue:
                    "\"\(symbol)\" does not appear as a substring of anything in "
                    + "networkingAPIReferenceCorpus — it matches no known real networking "
                    + "API. Either it targets a real API and the corpus is missing an entry "
                    + "for it, or it is a dud (like \"CFStream\" was) and should be fixed or "
                    + "removed."
                )
            )
        }
    }

    @Test("no file outside the allowlist references networking APIs")
    func onlyAllowlistedFilesTouchTheNetwork() throws {
        let permitted = try Self.allowlist()
        var violations: [String] = []

        for file in try SourceTree.allSourceFiles() {
            let path = SourceTree.relativePath(file)
            let contents = try SourceTree.read(file)
            let found = NetworkingSymbolScanner.violatingSymbols(
                path: path,
                contents: contents,
                symbols: Self.networkingSymbols,
                allowlist: permitted
            )
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

    // MARK: - Scanner coverage
    //
    // The two tests above are only as good as the detection logic they run —
    // and today's tree has no networking code in Sources/, so both pass
    // vacuously. An inverted condition in the allowlist check would sail
    // through CI undetected. These cases exercise `NetworkingSymbolScanner`
    // directly against sample content in memory, so detection is proven
    // regardless of what currently happens to live in Sources/.

    @Test("networking symbol scanner: flags real hits, ignores clean content and allowlisted paths", arguments: [
        // A listed symbol in a non-allowlisted file must be flagged.
        (
            path: "Sources/BabelOtterKit/Rogue.swift",
            contents: "import Foundation\nfunc sneak() { _ = URLSession.shared }",
            allowlist: Set<String>(),
            expectFlagged: true
        ),
        // Clean content must not be flagged.
        (
            path: "Sources/BabelOtterKit/Clean.swift",
            contents: "struct Translator { func translate(_ text: String) -> String { text } }",
            allowlist: Set<String>(),
            expectFlagged: false
        ),
        // A listed symbol in an allowlisted file must not be flagged.
        (
            path: "Sources/BabelOtterKit/LLM/OllamaClient.swift",
            contents: "import Foundation\nfunc send() { _ = URLSession.shared }",
            allowlist: ["Sources/BabelOtterKit/LLM/OllamaClient.swift"],
            expectFlagged: false
        ),
    ] as [(path: String, contents: String, allowlist: Set<String>, expectFlagged: Bool)])
    func scannerDetectsViolationsAndRespectsTheAllowlist(
        path: String,
        contents: String,
        allowlist: Set<String>,
        expectFlagged: Bool
    ) {
        let found = NetworkingSymbolScanner.violatingSymbols(
            path: path,
            contents: contents,
            symbols: Self.networkingSymbols,
            allowlist: allowlist
        )
        #expect(
            found.isEmpty == !expectFlagged,
            "path=\(path) expectFlagged=\(expectFlagged) found=\(found)"
        )
    }
}

/// Extracted so the detection logic driving `onlyAllowlistedFilesTouchTheNetwork`
/// can be exercised against sample content in memory, exactly as
/// `ImportLineMatcher` does for `NoUIImportsTests`. Without this extraction,
/// every assertion in this file runs only against whatever currently happens to
/// be in `Sources/` — and since there is no networking code there today, the
/// whole suite passes vacuously and a broken guard (e.g. an inverted allowlist
/// check) would not be caught by CI.
enum NetworkingSymbolScanner {
    /// The symbols found in `contents`, or empty if `path` is allowlisted.
    static func violatingSymbols(
        path: String,
        contents: String,
        symbols: [String],
        allowlist: Set<String>
    ) -> [String] {
        guard !allowlist.contains(path) else { return [] }
        return symbols.filter { contents.contains($0) }
    }
}
