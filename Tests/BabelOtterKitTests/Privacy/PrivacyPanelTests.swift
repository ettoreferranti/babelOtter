import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Where Ollama listens, from lsof's field output")
struct ListeningProbeTests {

    @Test("loopback addresses are this Mac only, listed once each", arguments: [
        ("p83426\nf3\nn127.0.0.1:11434\n", ["127.0.0.1"]), ("n[::1]:11434", ["[::1]"]),
        ("n127.0.0.1:11434\nn[::1]:11434\nn127.0.0.1:11434", ["127.0.0.1", "[::1]"]),
        ("nlocalhost:11434", ["localhost"]), ("n127.0.0.2:11434", ["127.0.0.2"]),
        // Only n lines are addresses, even one with a colon in it.
        ("p1:2\nfx:y\nn127.0.0.1:11434", ["127.0.0.1"]),
    ])
    func loopback(output: String, hosts: [String]) {
        #expect(ListeningProbe.parse(output) == .loopbackOnly(hosts))
    }

    @Test("near misses and mapped addresses are not loopback: a false warning, the safe way")
    func nearMisses() {
        #expect(ListeningProbe.parse("n1270.0.0.1:11434") == .exposed(["1270.0.0.1"], everywhere: false))
        #expect(ListeningProbe.parse("n[::ffff:127.0.0.1]:11434") == .exposed(["[::ffff:127.0.0.1]"], everywhere: false))
        #expect(ListeningProbe.parse("n*:11434\nn192.168.1.20:11434") == .exposed(["*", "192.168.1.20"], everywhere: true))
    }

    @Test("a wildcard is every network", arguments: ["n*:11434", "n0.0.0.0:11434", "n[::]:11434"])
    func everywhere(output: String) {
        #expect(ListeningProbe.parse(output) == .exposed([String(output.dropFirst().dropLast(6))], everywhere: true))
    }

    @Test("a specific other address is this network; any exposure with loopback is still exposure")
    func specific() {
        #expect(ListeningProbe.parse("n192.168.1.20:11434") == .exposed(["192.168.1.20"], everywhere: false))
        #expect(ListeningProbe.parse("n127.0.0.1:11434\nn*:11434\nn*:11434")
            == .exposed(["*"], everywhere: true))
        #expect(ListeningProbe.parse("n127.0.0.1:11434") == .loopbackOnly(["127.0.0.1"]))
    }

    @Test("no listening address is unknown, never safe")
    func unknown() {
        #expect(ListeningProbe.parse("") == .unknown)
        #expect(ListeningProbe.parse("p123\nf3\n") == .unknown)
        #expect(ListeningProbe.parse("nnoport") == .unknown)
    }

    @Test("at most 64 lines are read")
    func bounded() {
        let filler = String(repeating: "p1\n", count: 64)
        #expect(ListeningProbe.parse(filler + "n*:11434") == .unknown)
        #expect(ListeningProbe.parse(String(repeating: "p1\n", count: 63) + "n*:11434")
            == .exposed(["*"], everywhere: true))
    }

    @Test("lsof is asked about Ollama's port only")
    func arguments() {
        #expect(ListeningProbe.arguments() == ["-nP", "-iTCP:11434", "-sTCP:LISTEN", "-F", "n"])
    }
}

@Suite("What the Privacy panel says")
struct PrivacyReportTests {

    private func lines(
        _ listening: ListeningExposure = .loopbackOnly(["127.0.0.1"]),
        refusal: StorageLocationError? = nil, history: HistoryPolicy = .keep(.days(90)), packages: Int = 0
    ) -> [PrivacyLine] {
        PrivacyReport.lines(
            endpoint: .loopback, listening: listening,
            historyFolder: "~/Library/Application Support/ch.lingoswen",
            historyRefusal: refusal, history: history, packages: packages)
    }

    @Test("all is well: five lines, all checks, no remedy")
    func allWell() {
        let report = lines()
        #expect(report.map(\.title) == ["Model connection", "Ollama listens on", "History", "Dependencies", "Telemetry"])
        #expect(report.allSatisfy { $0.mark == .ok })
        #expect(report.allSatisfy { $0.remedy == nil })
        #expect(report[0].detail == "http://127.0.0.1:11434 - this Mac only (loopback).")
        #expect(report[1].detail == "This Mac only (127.0.0.1), for the Ollama running as you. "
            + "One run by another user or as root would not be seen here.")
        #expect(report[2].detail
            == "~/Library/Application Support/ch.lingoswen, outside iCloud. Records are kept for 90 days.")
        #expect(report[3].detail == "0 third-party packages; checked against the allowlist on every change.")
        #expect(report[4].detail
            == "No telemetry, analytics or crash reporting. Nothing is sent anywhere but the local model.")
    }

    @Test("an exposed Ollama warns, says who can reach it, and offers the fix")
    func exposed() {
        let everywhere = lines(.exposed(["*"], everywhere: true))[1]
        #expect(everywhere.mark == .warning)
        #expect(everywhere.detail.hasPrefix("All networks (*). Other devices on your network"))
        #expect(everywhere.remedy == "launchctl setenv OLLAMA_HOST 127.0.0.1:11434")
        let local = lines(.exposed(["192.168.1.20"], everywhere: false))[1]
        #expect(local.detail.hasPrefix("This network (192.168.1.20)."))
        #expect(local.remedy == PrivacyReport.bindingFix)
    }

    @Test("an unknown binding is a question, not a check")
    func unknown() {
        let line = lines(.unknown)[1]
        #expect(line.mark == .unknown)
        #expect(line.detail.contains("is run by another user or as root"))
        #expect(line.detail.contains("This is not a sign that it is safe."))
        #expect(line.remedy == nil)
    }

    @Test("history inside iCloud is a warning")
    func iCloud() {
        let line = lines(refusal: .iCloudSynced(URL(filePath: "/x")))[2]
        #expect(line.mark == .warning)
        #expect(line.detail == "~/Library/Application Support/ch.lingoswen is inside iCloud, so history is not saved.")
        #expect(line.remedy == nil)
    }

    @Test("history the recorder could not open is a warning, never a check")
    func unavailable() {
        let line = PrivacyReport.lines(
            endpoint: .loopback, listening: .unknown, historyFolder: "~/h", historyRefusal: nil,
            historyUnavailable: "could not open the database (file is not a database)",
            history: .keep(.days(90)))[2]
        #expect(line.mark == .warning)
        #expect(line.detail == "~/h: history is not saved - could not open the database (file is not a database).")
    }

    @Test("retention in words", arguments: [
        (HistoryPolicy.keep(.days(1)), "Records are kept for 1 day."),
        (.keep(.days(30)), "Records are kept for 30 days."),
        (.keep(.unlimited), "Records are kept until you clear them."),
        (.off, "History is off."), (.keep(.off), "History is off."),
        (.paused, "History is paused until config.json is fixed."),
    ])
    func retention(policy: HistoryPolicy, words: String) {
        #expect(lines(history: policy)[2].detail.hasSuffix(words))
    }

    @Test("one package is singular")
    func packages() {
        #expect(lines(packages: 1)[3].detail.hasPrefix("1 third-party package;"))
        #expect(lines(packages: 2)[3].detail.hasPrefix("2 third-party packages;"))
    }

    @Test("the clipboard note names Universal Clipboard and PRIVACY.md")
    func clipboard() {
        #expect(PrivacyReport.clipboardNote.contains("Universal Clipboard"))
        #expect(PrivacyReport.clipboardNote.hasSuffix("see PRIVACY.md."))
    }
}

@Suite("The dependency count the panel shows matches the package graph")
struct BuildFactsTests {

    @Test("as many packages as Package.swift declares and Package.resolved pins")
    func matchesGraph() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try String(contentsOf: root.appending(path: "Package.swift"), encoding: .utf8)
        let declared = manifest.components(separatedBy: ".package(").count - 1
        #expect(declared == BuildFacts.thirdPartyPackages)
        let resolved = root.appending(path: "Package.resolved")
        var pinned = 0
        if FileManager.default.fileExists(atPath: resolved.path(percentEncoded: false)) {
            let text = try String(contentsOf: resolved, encoding: .utf8)
            pinned = text.components(separatedBy: "\"identity\"").count - 1
        }
        #expect(pinned == BuildFacts.thirdPartyPackages)
    }
}
