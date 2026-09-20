# M0 Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the Swift package split, the CI pipeline with a mutation-testing gate, and the six privacy enforcement mechanisms that make "no user content leaves this machine" provable rather than promised — plus two time-boxed spikes that de-risk everything after them.

**Architecture:** A single SwiftPM package with four targets. `BabelOtterKit` is pure Swift with zero UI-framework imports and carries all real logic; `BabelOtterApp` is a thin AppKit shell; `babelotter-eval` is a CLI reusing the core; `BabelOtterKitTests` holds unit tests *and* architecture guard tests that read the source tree and assert structural invariants about it. Nothing user-facing ships in M0.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM, Swift Testing, GitHub Actions on macOS runners, `muter` for mutation testing, system `libsqlite3` later. **Zero third-party runtime dependencies.**

**Spec:** [`docs/superpowers/specs/2026-09-18-babelotter-design.md`](../specs/2026-09-18-babelotter-design.md)
**Architecture:** [`docs/architecture.md`](../../architecture.md)
**Privacy model:** [`PRIVACY.md`](../../../PRIVACY.md)
**Backlog:** M0 Foundations milestone — issues #1, #2, #16–#25, #30

## Global Constraints

These apply to every task. Do not restate them per task; do not violate them.

- **Swift tools version 6.0**, language mode 6, `platforms: [.macOS(.v14)]`. No concurrency warnings.
- **Zero third-party runtime dependencies.** Any addition requires an allowlist entry and explicit approval. Prefer system libraries (`libsqlite3`) over packages.
- **`BabelOtterKit` must not import** `AppKit`, `SwiftUI`, `UIKit` or `Cocoa`. Enforced by Task 1's guard test.
- **Exactly one networking call site** may exist in `Sources/`, and it must go through `OllamaEndpoint`. Enforced by Task 6.
- **`OLLAMA_HOST` is deliberately ignored.** Never read it to configure a connection.
- **No user content in logs.** User text reaches logging only via the redacted representation from Task 8.
- **This repository is PUBLIC.** Every fixture, eval case and example must be synthetic. No real correspondence, no internal work material, no personal data. Enforced by Task 10.
- **TDD, without exception.** Write the failing test, watch it fail for the right reason, then implement. A step that says "run it to verify it fails" is not ceremony — a test that passes before implementation is testing nothing.
- **Mutation score ≥80%** on `BabelOtterKit`, gating CI (Task 11).
- **Commit messages** end with:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`
- **Close the issue in the commit** that completes it: `Closes #NN`.

---

## File Structure

| Path | Responsibility |
|---|---|
| `Package.swift` | Four targets, no dependencies |
| `Sources/BabelOtterKit/LLM/OllamaEndpoint.swift` | Loopback-only endpoint value type |
| `Sources/BabelOtterKit/Privacy/UserText.swift` | User content wrapper whose default description is redacted |
| `Sources/BabelOtterKit/Privacy/StorageLocator.swift` | Resolves and validates on-disk locations; refuses iCloud-synced trees |
| `Sources/BabelOtterApp/main.swift` | Placeholder shell entry point (fleshed out in M1b) |
| `Sources/babelotter-eval/main.swift` | Placeholder CLI entry point (fleshed out in M3) |
| `Tests/BabelOtterKitTests/Support/SourceTree.swift` | Locates `Sources/` at test time so guard tests can read the code |
| `Tests/BabelOtterKitTests/Architecture/*.swift` | Structural invariants: no UI imports, one networking call site, dependency allowlist |
| `Tests/BabelOtterKitTests/LLM/OllamaEndpointTests.swift` | Loopback enforcement |
| `Tests/BabelOtterKitTests/Privacy/*.swift` | Redaction, storage location, fixture content guard |
| `Config/dependency-allowlist.txt` | Reviewed runtime dependencies (starts empty) |
| `Config/networking-allowlist.txt` | Files permitted to reference networking APIs |
| `.github/workflows/ci.yml` | Build, test, guards, mutation gate |
| `muter.conf.yml` | Mutation testing configuration (created in Task 3) |

---

## Task 1: Package skeleton and the no-UI-import guard

**Issue:** #16 · **Files:**
- Create: `Package.swift`, `Sources/BabelOtterKit/BabelOtterKit.swift`, `Sources/BabelOtterApp/main.swift`, `Sources/babelotter-eval/main.swift`
- Create: `Tests/BabelOtterKitTests/Support/SourceTree.swift`, `Tests/BabelOtterKitTests/Architecture/NoUIImportsTests.swift`

**Interfaces:**
- Produces: `SourceTree.repositoryRoot: URL`, `SourceTree.swiftFiles(inTarget:) throws -> [URL]`, `SourceTree.read(_:) throws -> String` — every later architecture guard consumes these.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "babelOtter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BabelOtterKit", targets: ["BabelOtterKit"]),
        .executable(name: "babelotter-eval", targets: ["babelotter-eval"]),
    ],
    // No dependencies. Adding one requires an entry in
    // Config/dependency-allowlist.txt — see Task 7 and NFR-P6.
    targets: [
        .target(name: "BabelOtterKit"),
        .executableTarget(name: "BabelOtterApp", dependencies: ["BabelOtterKit"]),
        .executableTarget(name: "babelotter-eval", dependencies: ["BabelOtterKit"]),
        .testTarget(name: "BabelOtterKitTests", dependencies: ["BabelOtterKit"]),
    ]
)
```

- [ ] **Step 2: Create the three placeholder sources**

`Sources/BabelOtterKit/BabelOtterKit.swift`:
```swift
/// Namespace for package-wide constants.
///
/// `BabelOtterKit` deliberately imports no UI framework: all logic here must be
/// runnable without AppKit, a window server, or a user session. See NFR-Q3.
public enum BabelOtter {
    public static let bundleIdentifier = "ch.babelotter"
}
```

`Sources/BabelOtterApp/main.swift`:
```swift
import BabelOtterKit

// The AppKit shell is built in M1b. M0 only proves the target links.
print("babelOtter shell — \(BabelOtter.bundleIdentifier)")
```

`Sources/babelotter-eval/main.swift`:
```swift
import BabelOtterKit

// The evaluation harness is built in M3. M0 only proves the target links.
print("babelotter-eval — \(BabelOtter.bundleIdentifier)")
```

- [ ] **Step 3: Write the source-tree helper**

`Tests/BabelOtterKitTests/Support/SourceTree.swift`:
```swift
import Foundation

/// Locates the repository's source tree from this file's own compile-time path,
/// so architecture tests can read and assert about the code that ships.
enum SourceTree {
    /// `.../Tests/BabelOtterKitTests/Support/SourceTree.swift` → repository root.
    static let repositoryRoot: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()   // Support
        .deletingLastPathComponent()   // BabelOtterKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root

    static var sourcesDirectory: URL { repositoryRoot.appending(path: "Sources") }

    /// Every `.swift` file in one target, sorted for deterministic failure output.
    static func swiftFiles(inTarget target: String) throws -> [URL] {
        try swiftFiles(under: sourcesDirectory.appending(path: target))
    }

    /// Every `.swift` file under `Sources/`, across all targets.
    static func allSourceFiles() throws -> [URL] {
        try swiftFiles(under: sourcesDirectory)
    }

    static func swiftFiles(under directory: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            found.append(url)
        }
        return found.sorted { $0.path < $1.path }
    }

    static func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Path relative to the repository root, for readable assertion messages.
    static func relativePath(_ url: URL) -> String {
        url.path(percentEncoded: false)
            .replacingOccurrences(of: repositoryRoot.path(percentEncoded: false), with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
```

- [ ] **Step 4: Write the failing guard test**

`Tests/BabelOtterKitTests/Architecture/NoUIImportsTests.swift`:
```swift
import Testing
import Foundation

/// NFR-Q3: the core package must be runnable without AppKit, a window server or a
/// user session. That is what makes it unit-testable, mutation-testable, and what
/// keeps the privacy invariants provable — none of which survive a UI import.
@Suite("Architecture: core imports no UI framework")
struct NoUIImportsTests {
    static let bannedModules = ["AppKit", "SwiftUI", "UIKit", "Cocoa", "Carbon"]

    @Test("BabelOtterKit imports no UI framework")
    func coreImportsNoUIFramework() throws {
        var violations: [String] = []

        for file in try SourceTree.swiftFiles(inTarget: "BabelOtterKit") {
            let contents = try SourceTree.read(file)
            for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                let module = trimmed
                    .dropFirst("import ".count)
                    .trimmingCharacters(in: .whitespaces)
                if Self.bannedModules.contains(module) {
                    violations.append("\(SourceTree.relativePath(file)) imports \(module)")
                }
            }
        }

        #expect(
            violations.isEmpty,
            """
            BabelOtterKit must import no UI framework (NFR-Q3).
            Move this code into BabelOtterApp and talk to it through a protocol.
            Violations:
            \(violations.joined(separator: "\n"))
            """
        )
    }

    @Test("the source tree helper actually finds sources")
    func sourceTreeResolves() throws {
        let files = try SourceTree.swiftFiles(inTarget: "BabelOtterKit")
        #expect(!files.isEmpty, "SourceTree found no files — its path arithmetic is wrong")
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass for the right reason**

Run: `swift build 2>&1 | grep -i "warning" || echo "no warnings"`
Expected: no warnings. Story #16 requires a clean build under Swift 6 strict
concurrency — a warning here is a design problem surfacing early, not noise to
suppress.

Run: `swift test 2>&1 | tail -20`
Expected: both tests pass. Then deliberately break it to prove the guard works:

```bash
printf '\nimport AppKit\n' >> Sources/BabelOtterKit/BabelOtterKit.swift
swift test 2>&1 | grep -i "must import no UI framework"   # expect a FAILURE message
git checkout Sources/BabelOtterKit/BabelOtterKit.swift    # undo
swift test 2>&1 | tail -5                                  # expect PASS again
```

A guard test that has never been seen to fail is not a guard.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "$(cat <<'MSG'
feat: Swift package split with core / shell / eval targets

BabelOtterKit holds all real logic and imports no UI framework; the
AppKit shell and eval CLI are placeholders until M1b and M3.

Adds SourceTree, the helper every architecture guard test reads the
source tree through, and the first guard: NFR-Q3, no UI imports in the
core. Verified by deliberately breaking it.

Closes #16

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 2: Loopback-only `OllamaEndpoint`

**Issue:** #20 · **Files:**
- Create: `Sources/BabelOtterKit/LLM/OllamaEndpoint.swift`
- Create: `Tests/BabelOtterKitTests/LLM/OllamaEndpointTests.swift`

**Interfaces:**
- Produces: `OllamaEndpoint.init?(host:port:)`, `.loopback`, `.resolved(ignoring:)`, `.baseURL: URL`, `.url(path:) -> URL`. Task 6's guard and every M1a networking call consume these.

This is the flagship privacy type. It is built before the mutation-testing spike deliberately: it is the richest mutation target in the package, so it is the right specimen to evaluate the tool against.

- [ ] **Step 1: Write the failing tests**

`Tests/BabelOtterKitTests/LLM/OllamaEndpointTests.swift`:
```swift
import Testing
import Foundation
@testable import BabelOtterKit

/// NFR-P2/P3: babelOtter opens no non-loopback connection, ever. This type is
/// where that is enforced — a non-loopback endpoint is unrepresentable.
@Suite("OllamaEndpoint enforces loopback")
struct OllamaEndpointTests {

    @Test("accepts every loopback spelling", arguments: [
        "127.0.0.1", "localhost", "LOCALHOST", "::1", "[::1]", " 127.0.0.1 ",
    ])
    func acceptsLoopback(host: String) {
        #expect(OllamaEndpoint(host: host) != nil, "\(host) is loopback and must be accepted")
    }

    @Test("rejects everything that is not loopback", arguments: [
        "ollama.example.com",
        "0.0.0.0",                  // wildcard bind, NOT loopback
        "192.168.1.5",
        "10.0.0.1",
        "127.0.0.1.evil.example",   // prefix trap
        "evil-localhost.example",   // substring trap
        "localhost.evil.example",   // suffix trap
        "",
        "   ",
        "::",
    ])
    func rejectsNonLoopback(host: String) {
        #expect(OllamaEndpoint(host: host) == nil, "\(host) is not loopback and must be rejected")
    }

    @Test("rejects out-of-range ports", arguments: [0, -1, 65_536, 99_999])
    func rejectsInvalidPorts(port: Int) {
        #expect(OllamaEndpoint(host: "127.0.0.1", port: port) == nil)
    }

    @Test("accepts boundary ports", arguments: [1, 11_434, 65_535])
    func acceptsBoundaryPorts(port: Int) {
        #expect(OllamaEndpoint(host: "127.0.0.1", port: port) != nil)
    }

    @Test("defaults to Ollama's port")
    func defaultsToOllamaPort() throws {
        let endpoint = try #require(OllamaEndpoint(host: "127.0.0.1"))
        #expect(endpoint.port == 11_434)
    }

    @Test("OLLAMA_HOST is deliberately ignored")
    func ignoresOllamaHostEnvironment() {
        // A shell profile, a dotfile sync, or a hostile environment could point
        // OLLAMA_HOST at a remote server. Honouring it would send the user's
        // writing off the machine. babelOtter always talks to loopback.
        let hostile = [
            "OLLAMA_HOST": "https://ollama.example.com:443",
            "OLLAMA_ORIGINS": "*",
        ]
        #expect(OllamaEndpoint.resolved(ignoring: hostile) == .loopback)
    }

    @Test("builds an IPv4 base URL")
    func buildsIPv4URL() throws {
        let endpoint = try #require(OllamaEndpoint(host: "127.0.0.1", port: 11_434))
        #expect(endpoint.baseURL.absoluteString == "http://127.0.0.1:11434")
    }

    @Test("brackets IPv6 hosts in the URL")
    func bracketsIPv6() throws {
        let endpoint = try #require(OllamaEndpoint(host: "::1", port: 11_434))
        #expect(endpoint.baseURL.absoluteString == "http://[::1]:11434")
    }

    @Test("appends API paths without doubling separators", arguments: [
        "api/chat", "/api/chat",
    ])
    func appendsPaths(path: String) throws {
        let endpoint = try #require(OllamaEndpoint(host: "127.0.0.1"))
        #expect(endpoint.url(path: path).absoluteString == "http://127.0.0.1:11434/api/chat")
    }

    @Test("loopback constant is the IPv4 default")
    func loopbackConstant() {
        #expect(OllamaEndpoint.loopback.host == "127.0.0.1")
        #expect(OllamaEndpoint.loopback.port == 11_434)
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `swift test --filter OllamaEndpoint 2>&1 | tail -20`
Expected: compile failure — `cannot find 'OllamaEndpoint' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/BabelOtterKit/LLM/OllamaEndpoint.swift`:
```swift
import Foundation

/// The only address babelOtter is permitted to talk to.
///
/// NFR-P1 says no user content leaves the machine. The App Sandbox cannot enforce
/// that for us — `com.apple.security.network.client` is all-or-nothing with no
/// loopback-only variant, and denying it would block Ollama too. So the guarantee
/// lives here: a non-loopback endpoint is unrepresentable, and the architecture
/// guard in `NetworkingCallSiteTests` asserts that every network call in the
/// package goes through a value of this type.
public struct OllamaEndpoint: Sendable, Equatable, Hashable {

    /// Ollama's default port.
    public static let defaultPort = 11_434

    /// Exactly the hosts that cannot leave this machine.
    ///
    /// `0.0.0.0` is deliberately absent: it is a wildcard *bind* address, not a
    /// loopback destination.
    private static let permittedHosts: Set<String> = ["127.0.0.1", "::1", "localhost"]

    public let host: String
    public let port: Int

    /// Fails for any host that is not loopback, or any port outside 1...65535.
    public init?(host: String, port: Int = OllamaEndpoint.defaultPort) {
        let normalized = Self.normalize(host)
        guard Self.permittedHosts.contains(normalized) else { return nil }
        guard (1...65_535).contains(port) else { return nil }
        self.host = normalized
        self.port = port
    }

    private static func normalize(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("["), value.hasSuffix("]"), value.count > 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    /// The endpoint babelOtter always uses.
    public static let loopback = OllamaEndpoint(host: "127.0.0.1")!

    /// Always returns ``loopback``, whatever the environment says.
    ///
    /// The parameter exists so tests can prove the environment is ignored, and so
    /// the intent is visible at the call site. `OLLAMA_HOST` is never honoured:
    /// a remote value there would ship the user's writing off the machine.
    public static func resolved(ignoring environment: [String: String]) -> OllamaEndpoint {
        _ = environment
        return .loopback
    }

    /// `http://127.0.0.1:11434`, with IPv6 hosts bracketed.
    public var baseURL: URL {
        let hostComponent = host.contains(":") ? "[\(host)]" : host
        guard let url = URL(string: "http://\(hostComponent):\(port)") else {
            preconditionFailure("loopback host \(host):\(port) must form a valid URL")
        }
        return url
    }

    /// `baseURL` joined with an API path, tolerant of a leading slash.
    public func url(path: String) -> URL {
        baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `swift test --filter OllamaEndpoint 2>&1 | tail -20`
Expected: all cases pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/LLM Tests/BabelOtterKitTests/LLM
git commit -m "$(cat <<'MSG'
feat: loopback-only OllamaEndpoint

Makes a non-loopback endpoint unrepresentable rather than merely
discouraged. OLLAMA_HOST is deliberately ignored: a remote value there
would ship the user's writing off the machine.

Covers the prefix, substring and suffix traps (127.0.0.1.evil.example,
evil-localhost.example, localhost.evil.example) and excludes 0.0.0.0,
which is a wildcard bind address rather than a loopback destination.

Closes #20

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 3: SPIKE — verify `muter` on this toolchain

**Issue:** #18 · **Time-box: 1 day. Stop at the box and record what you found.**

The output of a spike is an answer, not code you keep. Anything built here is throwaway unless it is the `muter.conf.yml` that ends up working.

**Why now:** Tasks 1–2 produced a real mutation target (`OllamaEndpoint` has branching, boundary and set-membership logic). Everything after this task depends on knowing whether the ≥80% gate is achievable and *which test framework the tool can read*.

- [ ] **Step 1: Install and record the version**

```bash
brew install muter-mutation-testing/formulae/muter || brew install muter
muter --version
swift --version
```

Record both versions in issue #18.

- [ ] **Step 2: Answer each question and write the answer into the issue**

1. Does `muter` run against an SPM package on Swift 6.4 / macOS 27 at all?
2. **Does it understand Swift Testing output, or only XCTest?** This is the highest-risk question — muter determines mutant kill/survive by parsing the test run's result. If it cannot read Swift Testing, the remediation is to port `OllamaEndpointTests.swift` to XCTest and adopt XCTest for the whole core.
3. Can it be scoped to a single target, so `BabelOtterApp` is excluded? (`muter.conf.yml` → `excludeList`)
4. What is the wall-clock runtime on the current suite, and what does that extrapolate to at ~40 source files?
5. Does it emit a machine-readable score that CI can threshold?

- [ ] **Step 3: Record the decision**

Write one of these verdicts into issue #18, with the evidence:

- ✅ **Works** → commit `muter.conf.yml`, proceed to Task 11 as written.
- ⚠️ **Works with a workaround** → document the workaround in the issue *and* as a comment in `muter.conf.yml`.
- ❌ **Unusable** → **STOP. Do not improvise a replacement.** Report back and re-plan Task 11 for a SwiftSyntax-based harness. That is a design task, not something to invent mid-execution.

- [ ] **Step 4: If the framework had to change, port and commit that separately**

```bash
swift test 2>&1 | tail -5          # must still pass after any port
git add Tests muter.conf.yml
git commit -m "$(cat <<'MSG'
chore: pin mutation testing configuration

Records the spike's findings: tool version, test framework compatibility
and the exact invocation CI will use.

Refs #18

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

- [ ] **Step 5: Close #18 with the verdict**

```bash
gh issue close 18 --comment "Spike complete — verdict and evidence recorded above."
```

---

## Task 4: CI — build, test, and skip integration tests

**Issue:** #17 · **Files:**
- Create: `.github/workflows/ci.yml`
- Create: `Tests/BabelOtterKitTests/Support/IntegrationGate.swift`

- [ ] **Step 1: Write the integration gate helper**

Integration tests need a live Ollama and real models. CI runners have neither, and — because this repository is public — no real text may execute on a third-party runner. One switch, checked the same way everywhere.

`Tests/BabelOtterKitTests/Support/IntegrationGate.swift`:
```swift
import Foundation

/// Integration tests run locally only. CI runners have no Ollama and no models,
/// and this repository is public — nothing resembling real user text should ever
/// execute on a third-party runner. See NFR-P8.
///
/// Enable locally with:  BABELOTTER_INTEGRATION=1 swift test
enum IntegrationGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["BABELOTTER_INTEGRATION"] == "1"
    }
}
```

Integration suites from M1a onward are written as:
```swift
@Suite("…", .enabled(if: IntegrationGate.isEnabled))
```

- [ ] **Step 2: Write the workflow**

`.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
  pull_request:

# BABELOTTER_INTEGRATION is deliberately unset: integration tests are local-only.
jobs:
  test:
    name: Build and test
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Show toolchain
        run: |
          swift --version
          xcodebuild -version

      - name: Build
        run: swift build --build-tests

      - name: Test
        run: swift test
```

- [ ] **Step 3: Verify the runner's Swift is new enough**

The package declares `swift-tools-version: 6.0`. If the `macos-15` image ships an older toolchain, `swift build` fails with a tools-version error. If that happens, add a `Select Xcode` step *before* the build, using a version the image actually provides:

```bash
ls /Applications | grep Xcode     # run this once in CI to see what's available
```

then:
```yaml
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.4.app
```

Do not add a third-party setup action for this — the built-in switch is sufficient.

- [ ] **Step 4: Push and confirm CI is green**

```bash
git add .github Tests/BabelOtterKitTests/Support/IntegrationGate.swift
git commit -m "$(cat <<'MSG'
ci: build and test on every push

Integration tests are gated behind BABELOTTER_INTEGRATION and never run
in CI: runners have no Ollama and no models, and this repository is
public, so no text resembling real user content executes on a
third-party runner.

Closes #17

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
git push
gh run watch
```

Expected: green. If red, fix forward; do not proceed with a red pipeline.

---

## Task 5: SPIKE — does the selection survive the popup?

**Issue:** #30 · **Time-box: 1 day.**

The single most likely thing to make babelOtter feel broken. Showing a window can deactivate the source application and drop the selection, leaving the replace step with nothing to write into. Everything in M1b assumes this is solvable.

**This is throwaway code.** Build it under `Spikes/focus-loss/` and delete it when done — only the findings are kept.

- [ ] **Step 1: Note the permission gotcha before you start**

Accessibility permission attaches to the *binary that runs*. A `swift run` executable inherits the terminal's grant, so **grant Accessibility to your terminal app** (System Settings → Privacy & Security → Accessibility) or the prototype will silently read nothing. Record which approach you used — M1b needs to know whether a real `.app` bundle is required.

- [ ] **Step 2: Build the smallest prototype that answers the question**

It must do exactly this, and nothing more:
1. Register a hotkey with Carbon `RegisterEventHotKey`.
2. On trigger, read `kAXSelectedTextAttribute` from the focused element, and retain the `AXUIElement` plus the frontmost app's PID.
3. Show an `NSPanel` with `.nonactivatingPanel` in its style mask and `becomesKeyOnlyIfNeeded = true`.
4. After a delay, re-activate the source app by PID and write the text back, uppercased so the round trip is unmistakable.

- [ ] **Step 3: Answer each question in issue #30**

1. Does the source app stay frontmost and the selection stay selected when the panel appears?
2. Does the captured `AXUIElement` stay valid across the panel's lifetime?
3. Can the source app be re-activated reliably by PID before the write-back?
4. **Per app** — Mail, Safari, Chrome, Teams, Word, VS Code — does capture work, does replace work, and is AX or clipboard needed? A table in the issue.
5. If the panel must take focus to accept the style-note text field, can the selection still be restored afterwards? This decides whether the style note can live in the popup at all (story #52).

- [ ] **Step 4: Record findings, delete the prototype, close the issue**

```bash
rm -rf Spikes/focus-loss
gh issue close 30 --comment "Spike complete — per-app results table and chosen approach recorded above. Prototype deleted; findings inform #48 and #52."
```

If the answer is that focus loss is *not* solvable with a non-activating panel, **stop and report**. M1b's design depends on it and would need revisiting.

---

## Task 6: Architecture guard — exactly one networking call site

**Issue:** #21 · **Files:**
- Create: `Config/networking-allowlist.txt`
- Create: `Tests/BabelOtterKitTests/Architecture/NetworkingCallSiteTests.swift`

**Interfaces:**
- Consumes: `SourceTree` (Task 1).

- [ ] **Step 1: Write the allowlist**

`Config/networking-allowlist.txt`:
```
# Files permitted to reference networking APIs. NFR-P4.
#
# Adding a line here weakens the guarantee that babelOtter opens no
# non-loopback connection. Do not add one without understanding why the
# existing call site cannot serve. Every entry must route through
# OllamaEndpoint, which makes a non-loopback destination unrepresentable.
#
# Paths are relative to the repository root.
Sources/BabelOtterKit/LLM/OllamaClient.swift
```

`OllamaClient.swift` does not exist yet — it arrives in M1a. Listing it now means the file is pre-approved and every *other* file is not.

- [ ] **Step 2: Write the failing test**

`Tests/BabelOtterKitTests/Architecture/NetworkingCallSiteTests.swift`:
```swift
import Testing
import Foundation

/// NFR-P4: exactly one file in the package may touch the network, and it must
/// route through `OllamaEndpoint`. A second call site is how accidental egress
/// gets introduced, so CI refuses one.
@Suite("Architecture: one networking call site")
struct NetworkingCallSiteTests {

    /// Symbols that can open a socket. Substring matching is intentional: it is
    /// better to flag a comment mentioning URLSession than to miss a real call.
    static let networkingSymbols = [
        "URLSession", "URLRequest", "URLDownload",
        "NWConnection", "NWBrowser", "NWListener",
        "CFSocket", "CFStream", "import Network",
        "getaddrinfo", "socket(",
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
            "The allowlist has grown to \(permitted.count) entries: \(permitted.sorted()). "
            + "One reviewed call site is what makes NFR-P4 checkable."
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
                "\(path) may touch the network, so it must build its URL from "
                + "OllamaEndpoint — that type is what makes a non-loopback "
                + "destination unrepresentable."
            )
        }
    }
}
```

- [ ] **Step 3: Run and verify it passes, then prove it catches a violation**

```bash
swift test --filter NetworkingCallSite 2>&1 | tail -10     # expect PASS (vacuously)

cat > Sources/BabelOtterKit/Leak.swift <<'SWIFT'
import Foundation
func sneak() { _ = URLSession.shared }
SWIFT
swift test --filter NetworkingCallSite 2>&1 | grep -i "non-loopback"   # expect FAILURE
rm Sources/BabelOtterKit/Leak.swift
swift test --filter NetworkingCallSite 2>&1 | tail -5                   # expect PASS
```

- [ ] **Step 4: Commit**

```bash
git add Config/networking-allowlist.txt Tests/BabelOtterKitTests/Architecture
git commit -m "$(cat <<'MSG'
test: assert exactly one networking call site exists

Pre-approves the M1a OllamaClient path and refuses every other file that
references a socket-opening API. Also asserts allowlisted files build
their URLs from OllamaEndpoint, so the allowlist cannot become a way
around the loopback constraint.

Verified by planting a violation and watching it fail.

Closes #21

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 7: Dependency allowlist

**Issue:** #22 · **Files:**
- Create: `Config/dependency-allowlist.txt`
- Create: `Tests/BabelOtterKitTests/Architecture/DependencyAllowlistTests.swift`

- [ ] **Step 1: Write the allowlist**

`Config/dependency-allowlist.txt`:
```
# Reviewed runtime dependencies. NFR-P6.
#
# This file is intentionally empty. babelOtter has no third-party runtime
# dependencies, and that is a feature: every package added is code that could
# perform networking or telemetry inside a process holding the user's writing.
#
# Prefer system libraries. SQLite is reached through the system libsqlite3
# rather than a package wrapper, for exactly this reason.
#
# One identity per line, lowercase, as it appears in Package.resolved.
```

- [ ] **Step 2: Write the failing test**

`Tests/BabelOtterKitTests/Architecture/DependencyAllowlistTests.swift`:
```swift
import Testing
import Foundation

/// NFR-P6: every runtime dependency is reviewed. A transitive package is the
/// easiest way for telemetry to appear inside a process that holds the user's
/// writing, so the set is pinned and checked rather than trusted.
@Suite("Architecture: dependency allowlist")
struct DependencyAllowlistTests {

    static func allowlist() throws -> Set<String> {
        let url = SourceTree.repositoryRoot.appending(path: "Config/dependency-allowlist.txt")
        return Set(
            try SourceTree.read(url)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        )
    }

    /// Minimal shape of Package.resolved v2/v3.
    private struct Resolved: Decodable {
        struct Pin: Decodable { let identity: String }
        let pins: [Pin]?
    }

    @Test("every resolved dependency is on the allowlist")
    func resolvedDependenciesAreAllowlisted() throws {
        let url = SourceTree.repositoryRoot.appending(path: "Package.resolved")
        guard let data = try? Data(contentsOf: url) else {
            return  // no dependencies at all — the desired state
        }
        let resolved = try JSONDecoder().decode(Resolved.self, from: data)
        let permitted = try Self.allowlist()

        let unapproved = (resolved.pins ?? [])
            .map { $0.identity.lowercased() }
            .filter { !permitted.contains($0) }

        #expect(
            unapproved.isEmpty,
            """
            Unreviewed runtime dependencies: \(unapproved.sorted().joined(separator: ", ")).

            Adding a package puts third-party code inside the process that holds
            the user's writing. Prefer a system library. If the package is
            genuinely necessary, add its identity to
            Config/dependency-allowlist.txt in a commit that says what it does
            and confirms it performs no networking.
            """
        )
    }

    @Test("Package.swift declares no unreviewed package dependencies")
    func manifestDeclaresNoUnreviewedPackages() throws {
        let manifest = try SourceTree.read(
            SourceTree.repositoryRoot.appending(path: "Package.swift")
        )
        let declarations = manifest
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix(".package(") }

        #expect(
            declarations.isEmpty || !(try Self.allowlist()).isEmpty,
            "Package.swift declares dependencies but the allowlist is empty:\n"
            + declarations.joined(separator: "\n")
        )
    }
}
```

- [ ] **Step 3: Run and verify**

Run: `swift test --filter DependencyAllowlist 2>&1 | tail -10`
Expected: PASS — there is no `Package.resolved` and no `.package(` line.

- [ ] **Step 4: Commit**

```bash
git add Config/dependency-allowlist.txt Tests/BabelOtterKitTests/Architecture
git commit -m "$(cat <<'MSG'
test: check runtime dependencies against a reviewed allowlist

The allowlist starts empty and that is the intended steady state: every
package added is third-party code inside a process holding the user's
writing. SQLite will be reached through system libsqlite3 rather than a
wrapper package for this reason.

Closes #22

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 8: Redacted user content

**Issue:** #23 · **Files:**
- Create: `Sources/BabelOtterKit/Privacy/UserText.swift`
- Create: `Tests/BabelOtterKitTests/Privacy/UserTextTests.swift`

**Interfaces:**
- Produces: `UserText.init(_:)`, `.value`, `.characterCount`, `.isEmpty`, `UserTextSummary`. Every M1a type that carries user content takes `UserText` rather than `String`.

**Deviation from the issue's first acceptance criterion, recorded deliberately.** The issue asks that logging user content "does not compile". Swift cannot prevent string interpolation of an arbitrary type, so a compile-time bar is not achievable. What *is* achievable is stronger in practice: `UserText`'s own textual representations are redacted, so the accidental path — interpolating it into a log line — emits a redaction automatically, and reading the real content requires the explicit `.value`. Update issue #23 to say so rather than leaving the stated criterion unmet.

- [ ] **Step 1: Write the failing tests**

`Tests/BabelOtterKitTests/Privacy/UserTextTests.swift`:
```swift
import Testing
import Foundation
@testable import BabelOtterKit

/// NFR-P5: user content must not reach a log. Prompts in the unified log can be
/// swept into a sysdiagnose bundle and carried to Apple, so the accidental path
/// — interpolating a value into a log line — has to be safe by default.
@Suite("UserText redacts by default")
struct UserTextTests {

    let secret = "Sehr geehrte Frau Muster, anbei die Unterlagen zum Modul."

    @Test("string interpolation is redacted")
    func interpolationIsRedacted() {
        let text = UserText(secret)
        #expect(!"\(text)".contains("Muster"))
        #expect(!"\(text)".contains("Modul"))
    }

    @Test("description and debugDescription are redacted")
    func descriptionsAreRedacted() {
        let text = UserText(secret)
        #expect(!String(describing: text).contains("Muster"))
        #expect(!String(reflecting: text).contains("Muster"))
        #expect(!text.debugDescription.contains("Muster"))
    }

    @Test("the redaction reveals length but never content")
    func redactionShowsLengthOnly() {
        let text = UserText("Hallo Welt")
        #expect("\(text)" == "⟨redacted 10 chars⟩")
    }

    @Test("no substring of the original survives redaction")
    func noSubstringSurvives() {
        let text = UserText(secret)
        let rendered = "\(text)"
        for length in [4, 8, 16] where secret.count >= length {
            let fragment = String(secret.prefix(length))
            #expect(!rendered.contains(fragment))
        }
    }

    @Test("the explicit unwrap returns the real content")
    func explicitUnwrapReturnsContent() {
        #expect(UserText(secret).value == secret)
    }

    @Test("character count uses grapheme clusters")
    func characterCountIsGraphemeAware() {
        #expect(UserText("Grüezi").characterCount == 6)
        #expect(UserText("👩‍👩‍👧").characterCount == 1)
    }

    @Test("empty and whitespace-only text are reported as empty")
    func emptyDetection() {
        #expect(UserText("").isEmpty)
        #expect(UserText("   \n\t ").isEmpty)
        #expect(!UserText("a").isEmpty)
    }

    @Test("a summary carries metadata and no content")
    func summaryCarriesMetadataOnly() {
        let summary = UserText(secret).summary(languageCode: "de-CH", action: "translate")
        let rendered = "\(summary)"
        #expect(rendered.contains("de-CH"))
        #expect(rendered.contains("translate"))
        #expect(rendered.contains("\(secret.count)"))
        #expect(!rendered.contains("Muster"))
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `swift test --filter UserText 2>&1 | tail -20`
Expected: compile failure — `cannot find 'UserText' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/BabelOtterKit/Privacy/UserText.swift`:
```swift
import Foundation

/// Text belonging to the user — anything they selected, wrote, or got back.
///
/// NFR-P5: this must never reach a log. Swift cannot make interpolation a
/// compile error, so the defence is inverted instead: every textual
/// representation of this type is already redacted, and reading the real
/// content requires asking for ``value`` by name. The accidental path is safe;
/// the deliberate one is visible in review.
public struct UserText: Sendable, Equatable, Hashable {

    /// The real content. Referencing this in a logging context is a review
    /// finding — use ``summary(languageCode:action:)`` instead.
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    /// Grapheme-cluster count, so "👩‍👩‍👧" counts as one character.
    public var characterCount: Int { value.count }

    public var isEmpty: Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Loggable metadata about this text, carrying no part of it.
    public func summary(languageCode: String, action: String) -> UserTextSummary {
        UserTextSummary(
            characterCount: characterCount,
            languageCode: languageCode,
            action: action
        )
    }
}

extension UserText: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "⟨redacted \(characterCount) chars⟩" }
    public var debugDescription: String { description }
}

/// What babelOtter is allowed to say about the user's text in a log.
public struct UserTextSummary: Sendable, Equatable, CustomStringConvertible {
    public let characterCount: Int
    public let languageCode: String
    public let action: String

    public var description: String {
        "\(action) \(languageCode) \(characterCount) chars"
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `swift test --filter UserText 2>&1 | tail -20`
Expected: all pass.

- [ ] **Step 5: Update the issue, then commit**

```bash
gh issue comment 23 --body "Implemented with one deliberate deviation. The first acceptance criterion asked that logging user content 'does not compile'. Swift cannot prevent string interpolation of an arbitrary type, so a compile-time bar is not achievable. Implemented the stronger practical guarantee instead: \`UserText\`'s \`description\` and \`debugDescription\` are themselves redacted, so the accidental path emits a redaction automatically, and reading real content requires the explicit \`.value\`. Tests assert no substring of the original survives any textual representation."

git add Sources/BabelOtterKit/Privacy Tests/BabelOtterKitTests/Privacy
git commit -m "$(cat <<'MSG'
feat: redacted UserText wrapper

Inverts the defence rather than attempting a compile-time bar Swift
cannot provide: every textual representation of UserText is redacted, so
interpolating it into a log emits "<redacted N chars>" automatically,
while reading real content requires the explicit .value.

Prompts in the unified log can be swept into a sysdiagnose bundle and
carried to Apple, which is what NFR-P5 exists to prevent.

Closes #23

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 9: Storage location resolver

**Issue:** #24 · **Files:**
- Create: `Sources/BabelOtterKit/Privacy/StorageLocator.swift`
- Create: `Tests/BabelOtterKitTests/Privacy/StorageLocatorTests.swift`

**Interfaces:**
- Consumes: `BabelOtter.bundleIdentifier` (Task 1).
- Produces: `StorageLocator.init(home:iCloudRoots:)`, `.validate(_:) throws`, `.applicationSupportDirectory() throws -> URL`, `.prepare(_:) throws`, `StorageLocationError`. M3's `SQLiteHistoryStore` consumes these.

**This is not hypothetical:** `~/Documents` is iCloud-synced on the target machine. Putting the history database there would upload the user's writing.

- [ ] **Step 1: Write the failing tests**

`Tests/BabelOtterKitTests/Privacy/StorageLocatorTests.swift`:
```swift
import Testing
import Foundation
@testable import BabelOtterKit

/// NFR-P7: local storage must sit outside every iCloud-synced tree. On the
/// target machine ~/Documents *is* iCloud-synced, so a naive Application
/// Support fallback is not enough — the path is validated, not assumed.
@Suite("StorageLocator refuses synced locations")
struct StorageLocatorTests {

    let home = URL(filePath: "/Users/example")

    var locator: StorageLocator {
        StorageLocator(
            home: home,
            iCloudRoots: [
                URL(filePath: "/Users/example/Library/Mobile Documents"),
                URL(filePath: "/Users/example/Documents"),
                URL(filePath: "/Users/example/Desktop"),
            ]
        )
    }

    @Test("rejects a path inside an iCloud-synced tree", arguments: [
        "/Users/example/Documents/history.sqlite",
        "/Users/example/Documents/nested/deep/history.sqlite",
        "/Users/example/Desktop/history.sqlite",
        "/Users/example/Library/Mobile Documents/com~apple~CloudDocs/history.sqlite",
    ])
    func rejectsSyncedPaths(path: String) {
        let candidate = URL(filePath: path)
        #expect(throws: StorageLocationError.iCloudSynced(candidate)) {
            try locator.validate(candidate)
        }
    }

    @Test("rejects the synced root itself")
    func rejectsSyncedRoot() {
        let candidate = URL(filePath: "/Users/example/Documents")
        #expect(throws: StorageLocationError.self) { try locator.validate(candidate) }
    }

    @Test("accepts paths outside every synced tree", arguments: [
        "/Users/example/Library/Application Support/ch.babelotter/history.sqlite",
        "/Users/example/.babelotter/history.sqlite",
    ])
    func acceptsSafePaths(path: String) throws {
        try locator.validate(URL(filePath: path))
    }

    /// The classic prefix bug: "/Users/example/DocumentsArchive" is not inside
    /// "/Users/example/Documents", and a naive hasPrefix check says it is.
    @Test("does not reject a sibling whose name merely starts the same", arguments: [
        "/Users/example/DocumentsArchive/history.sqlite",
        "/Users/example/Documents-old/history.sqlite",
        "/Users/example/DesktopBackup/history.sqlite",
    ])
    func respectsPathComponentBoundaries(path: String) throws {
        try locator.validate(URL(filePath: path))
    }

    @Test("rejects relative paths")
    func rejectsRelativePaths() {
        let candidate = URL(filePath: "relative/history.sqlite")
        #expect(throws: StorageLocationError.self) { try locator.validate(candidate) }
    }

    @Test("resolves Application Support under the bundle identifier")
    func resolvesApplicationSupport() throws {
        let directory = try locator.applicationSupportDirectory()
        #expect(directory.path(percentEncoded: false)
            == "/Users/example/Library/Application Support/ch.babelotter")
    }

    @Test("prepare creates the directory with owner-only permissions")
    func prepareSetsPermissions() throws {
        let sandbox = URL(filePath: NSTemporaryDirectory())
            .appending(path: "babelotter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let real = StorageLocator(home: sandbox, iCloudRoots: [])
        let directory = try real.applicationSupportDirectory()
        try real.prepare(directory)

        let attributes = try FileManager.default
            .attributesOfItem(atPath: directory.path(percentEncoded: false))
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.int16Value == 0o700)

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("prepare refuses a synced directory")
    func prepareRefusesSyncedDirectory() {
        let synced = URL(filePath: "/Users/example/Documents/ch.babelotter")
        #expect(throws: StorageLocationError.self) { try locator.prepare(synced) }
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `swift test --filter StorageLocator 2>&1 | tail -20`
Expected: compile failure — `cannot find 'StorageLocator' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/BabelOtterKit/Privacy/StorageLocator.swift`:
```swift
import Foundation

public enum StorageLocationError: Error, Equatable {
    /// The path sits inside a tree that syncs to iCloud.
    case iCloudSynced(URL)
    /// The path is not absolute, so it cannot be reasoned about.
    case notAbsolute(URL)
}

/// Decides where babelOtter may keep data, and refuses anywhere that would
/// upload it.
///
/// NFR-P7. The synced roots are injected rather than detected inside this type,
/// so the boundary logic is pure and exhaustively testable; the app supplies the
/// real roots at start-up. On the target machine `~/Documents` is iCloud-synced,
/// which is exactly the case a hardcoded "just use Application Support" would
/// have got right by luck and a future refactor would have got wrong.
public struct StorageLocator: Sendable {

    public let home: URL
    public let iCloudRoots: [URL]

    public init(home: URL, iCloudRoots: [URL]) {
        self.home = home
        self.iCloudRoots = iCloudRoots
    }

    /// `~/Library/Application Support/ch.babelotter` — never validated here;
    /// callers pass the result to ``validate(_:)`` or ``prepare(_:)``.
    public func applicationSupportDirectory() throws -> URL {
        home
            .appending(path: "Library/Application Support")
            .appending(path: BabelOtter.bundleIdentifier)
    }

    /// Throws if `candidate` is relative, or sits at or beneath a synced root.
    public func validate(_ candidate: URL) throws {
        let path = Self.normalized(candidate)
        guard path.hasPrefix("/") else {
            throw StorageLocationError.notAbsolute(candidate)
        }
        for root in iCloudRoots {
            let rootPath = Self.normalized(root)
            // Compare on component boundaries: "/Users/x/DocumentsArchive" is not
            // inside "/Users/x/Documents", though a bare hasPrefix says it is.
            if path == rootPath || path.hasPrefix(rootPath + "/") {
                throw StorageLocationError.iCloudSynced(candidate)
            }
        }
    }

    /// Validates, creates if needed, then locks down: owner-only access and
    /// excluded from backup.
    public func prepare(_ directory: URL) throws {
        try validate(directory)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path(percentEncoded: false)
        )

        var mutable = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }

    private static func normalized(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `swift test --filter StorageLocator 2>&1 | tail -20`
Expected: all pass, including the three path-boundary cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/Privacy Tests/BabelOtterKitTests/Privacy
git commit -m "$(cat <<'MSG'
feat: storage locator that refuses iCloud-synced paths

~/Documents is iCloud-synced on the target machine, so a history
database placed there would upload the user's writing. Synced roots are
injected rather than detected internally, keeping the boundary logic
pure and exhaustively testable.

Compares on path-component boundaries so /Users/x/DocumentsArchive is
not mistaken for a child of /Users/x/Documents.

Closes #24

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 10: Fixture content guard

**Issue:** #25 · **Files:**
- Create: `Tests/Fixtures/README.md`
- Create: `Config/fixture-guard-allowlist.txt`
- Create: `Tests/BabelOtterKitTests/Privacy/FixtureContentGuardTests.swift`

**Why this exists:** the repository is public and CI runs on third-party machines. A fixture built from a real email would publish it.

- [ ] **Step 1: Write the fixtures README and allowlist**

`Tests/Fixtures/README.md`:
```markdown
# Fixtures — synthetic only

This repository is **public**, and CI runs on GitHub-hosted runners.

Every fixture, eval case, glossary default and example in this tree must be
invented. No real correspondence, no internal work material, no real names,
addresses, phone numbers or account details — not even lightly edited.

Write German and English that exercises the behaviour you need (case errors,
word order, bullets, protected terms) about invented subjects. `Frau Muster`
and `Herr Beispiel` are the placeholder names to use.

`FixtureContentGuardTests` scans this tree on every CI run.
```

`Config/fixture-guard-allowlist.txt`:
```
# Fixture paths exempted from the content guard, one per line, relative to the
# repository root.
#
# An entry here asserts a human read the file and confirmed it is synthetic
# despite tripping a heuristic. Empty is the expected state.
```

- [ ] **Step 2: Write the failing test**

`Tests/BabelOtterKitTests/Privacy/FixtureContentGuardTests.swift`:
```swift
import Testing
import Foundation

/// NFR-P8: this repository is public and CI runs on third-party machines, so a
/// fixture built from real correspondence would publish it. Heuristic, and
/// deliberately noisy in the safe direction: a false positive costs one
/// allowlist line, a false negative costs a disclosure.
@Suite("Fixtures contain no real correspondence")
struct FixtureContentGuardTests {

    struct Marker {
        let name: String
        let pattern: String
    }

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
                guard file.pathExtension != "" ,
                      let contents = try? SourceTree.read(file) else { continue }
                let relative = SourceTree.relativePath(file)
                guard !permitted.contains(relative) else { continue }

                for marker in Self.markers {
                    let regex = try NSRegularExpression(pattern: marker.pattern)
                    let range = NSRange(contents.startIndex..., in: contents)
                    if regex.firstMatch(in: contents, range: range) != nil {
                        violations.append("\(relative) contains a \(marker.name)")
                    }
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

    @Test("the guard detects a planted marker")
    func guardDetectsPlantedMarker() throws {
        // Proves the regexes work without committing anything that trips them.
        let sample = "Bitte antworten Sie an vorname.nachname@example.org."
        let regex = try NSRegularExpression(pattern: Self.markers[0].pattern)
        let range = NSRange(sample.startIndex..., in: sample)
        #expect(regex.firstMatch(in: sample, range: range) != nil)
    }
}
```

- [ ] **Step 3: Run and verify**

Run: `swift test --filter FixtureContentGuard 2>&1 | tail -10`
Expected: PASS. The self-check proves the regexes fire; the scan finds nothing because no fixtures exist yet.

- [ ] **Step 4: Commit**

```bash
git add Tests/Fixtures Config/fixture-guard-allowlist.txt Tests/BabelOtterKitTests/Privacy
git commit -m "$(cat <<'MSG'
test: guard public-repo fixtures against real correspondence

Scans Tests/Fixtures and evals for email addresses, Swiss phone numbers,
IBANs and AHV numbers. Deliberately noisy in the safe direction: a false
positive costs one allowlist line, a false negative publishes someone's
email.

Includes a self-check so the regexes are proven to fire without
committing anything that trips them.

Closes #25

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 11: Mutation testing gate in CI

**Issue:** #19 · **Depends on Task 3's verdict.**

> **If Task 3 returned ❌ Unusable, STOP HERE.** Do not improvise a replacement harness. Report back so Task 11 can be re-planned properly for a SwiftSyntax-based tool. Inventing a mutation engine mid-execution is how a quality gate becomes theatre.

**Files:**
- Create: `muter.conf.yml` (if Task 3 did not already commit it)
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Write the muter configuration**

Scope it to the core. `BabelOtterApp` is excluded deliberately: mutating UI glue produces surviving mutants that say nothing about correctness, and chasing them would train the team to ignore the report.

`muter.conf.yml`:
```yaml
# Mutation testing scope. NFR-Q2: the core must score >= 80%.
#
# BabelOtterApp is excluded on purpose — mutating AppKit glue yields
# equivalent mutants and noise, not signal. Shell correctness rests on the
# manual smoke checklist instead.
executable: swift
arguments:
  - test
excludeList:
  - Sources/BabelOtterApp
  - Sources/babelotter-eval
  - Tests
```

Reconcile the `executable`/`arguments` keys against what Task 3 actually recorded working — the spike's findings win over this template.

- [ ] **Step 2: Run muter locally and record the baseline**

```bash
muter run 2>&1 | tail -30
```

Expected: a mutation score for `BabelOtterKit`. `OllamaEndpoint`, `StorageLocator` and `UserText` should score high — their tests were written against the boundary and trap cases specifically.

If the score is below 80%, **read the surviving mutants before touching the threshold.** A survivor is usually a real gap: a boundary the tests assert loosely, or a branch nothing exercises. Add the missing test. Lower the bar only if a mutant is genuinely equivalent, and say so in the commit.

- [ ] **Step 3: Add the gate to CI**

Append to `.github/workflows/ci.yml`:
```yaml
  mutation:
    name: Mutation testing
    runs-on: macos-15
    needs: test
    steps:
      - uses: actions/checkout@v4

      - name: Install muter
        run: brew install muter-mutation-testing/formulae/muter

      - name: Run mutation testing
        run: muter run --output-json muter-report.json

      - name: Enforce the threshold
        run: |
          score=$(jq -r '.mutationScore' muter-report.json)
          echo "Mutation score: ${score}%"
          if [ "$(printf '%.0f' "$score")" -lt 80 ]; then
            echo "::error::Mutation score ${score}% is below the required 80%."
            echo "Surviving mutants indicate tests that do not actually catch regressions."
            exit 1
          fi

      - name: Upload report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: mutation-report
          path: muter-report.json
```

Substitute the exact flags Task 3 recorded. If muter's JSON uses a different key than `mutationScore`, use the real one — read the file rather than guessing.

- [ ] **Step 4: Push and confirm the gate is green**

```bash
git add muter.conf.yml .github/workflows/ci.yml
git commit -m "$(cat <<'MSG'
ci: gate on a mutation score of at least 80%

Scoped to BabelOtterKit. The AppKit shell is excluded deliberately:
mutating UI glue yields equivalent mutants and noise, and a report full
of noise is a report nobody reads.

Closes #19

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
git push
gh run watch
```

- [ ] **Step 5: Prove the gate bites**

```bash
# Weaken a test so a real mutant survives, and confirm CI notices.
# Comment out the "rejects everything that is not loopback" case, push to a
# branch, and confirm the mutation job fails. Then restore it.
```

A quality gate nobody has seen fail is a badge, not a gate.

- [ ] **Step 6: Close the milestone**

```bash
gh issue close 1 --comment "All foundation stories complete."
gh issue close 2 --comment "All six privacy enforcement mechanisms implemented and under CI."
gh api repos/ettoreferranti/babelOtter/milestones --jq '.[] | select(.title=="M0 Foundations") | "open: \(.open_issues)  closed: \(.closed_issues)"'
```

---

## Definition of done for M0

- [ ] `swift build` and `swift test` pass locally and in CI
- [ ] `BabelOtterKit` imports no UI framework, proven by a guard that has been seen to fail
- [ ] A non-loopback `OllamaEndpoint` is unrepresentable; `OLLAMA_HOST` is ignored
- [ ] Exactly one networking call site is permitted, pre-approved for M1a's `OllamaClient`
- [ ] The dependency allowlist is empty and enforced
- [ ] User content is redacted in every textual representation
- [ ] Storage refuses iCloud-synced paths, on component boundaries
- [ ] Fixture content guard runs on every CI build
- [ ] Mutation score ≥80% on the core, gating CI, **seen to fail** when a test is weakened
- [ ] Both spikes closed with recorded findings: #18 (muter verdict), #30 (per-app focus-loss table)
- [ ] Issues #1, #2, #16–#25, #30 closed
