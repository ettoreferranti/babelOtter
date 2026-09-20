import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Configuration is human-readable and never fatal")
struct ConfigurationStoreTests {

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "babelotter-config-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("first launch with no file yields the shipped defaults and no problems")
    func firstLaunch() throws {
        let loaded = ConfigurationStore(directory: try temporaryDirectory()).load()
        #expect(loaded.configuration == Configuration.default)
        #expect(loaded.problems.isEmpty)
    }

    @Test("a saved configuration reloads identically")
    func roundTrip() throws {
        let store = ConfigurationStore(directory: try temporaryDirectory())
        var configuration = Configuration.default
        configuration.retentionDays = 42
        try store.save(configuration)
        let loaded = store.load()
        #expect(loaded.configuration == configuration)
        #expect(loaded.problems.isEmpty)
    }

    @Test("the written file is indented, because the user is invited to edit it")
    func humanReadable() throws {
        let directory = try temporaryDirectory()
        let store = ConfigurationStore(directory: directory)
        try store.save(.default)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\n  "), "a hand-editable file must be indented")
        #expect(directory.appending(path: "config.json").lastPathComponent == store.fileURL.lastPathComponent)
    }

    @Test("keys are sorted, so a hand edit produces a readable diff")
    func sortedKeys() throws {
        let store = ConfigurationStore(directory: try temporaryDirectory())
        try store.save(.default)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        let detection = text.range(of: "detectionConfidenceFloor")
        let retention = text.range(of: "retentionDays")
        #expect(detection != nil && retention != nil)
        #expect(detection!.lowerBound < retention!.lowerBound)
    }

    @Test("a hand-edited change takes effect on reload")
    func handEdited() throws {
        let store = ConfigurationStore(directory: try temporaryDirectory())
        try store.save(.default)
        var text = try String(contentsOf: store.fileURL, encoding: .utf8)
        text = text.replacingOccurrences(
            of: #""retentionDays" : \d+"#,
            with: #""retentionDays" : 7"#,
            options: .regularExpression
        )
        try text.write(to: store.fileURL, atomically: true, encoding: .utf8)
        #expect(store.load().configuration.retentionDays == 7)
    }

    @Test("a malformed file names the file, falls back to defaults, and does not crash")
    func malformed() throws {
        let directory = try temporaryDirectory()
        let store = ConfigurationStore(directory: directory)
        try "{ this is not json".write(to: store.fileURL, atomically: true, encoding: .utf8)
        let loaded = store.load()
        #expect(loaded.configuration == Configuration.default)
        #expect(loaded.problems.count == 1)
        #expect(loaded.problems[0].file == "config.json")
    }

    @Test("a wrong-typed field is reported by name, not as an opaque failure")
    func wrongFieldType() throws {
        let directory = try temporaryDirectory()
        let store = ConfigurationStore(directory: directory)
        var text = try String(
            data: JSONEncoder.configuration.encode(Configuration.default), encoding: .utf8)!
        text = text.replacingOccurrences(
            of: #""retentionDays" : \d+"#,
            with: #""retentionDays" : "ninety""#,
            options: .regularExpression
        )
        try text.write(to: store.fileURL, atomically: true, encoding: .utf8)
        let loaded = store.load()
        #expect(loaded.configuration == Configuration.default)
        #expect(loaded.problems.count == 1)
        #expect(loaded.problems[0].field == "retentionDays")
    }

    @Test("a missing required field is reported by name too")
    func missingField() throws {
        let directory = try temporaryDirectory()
        let store = ConfigurationStore(directory: directory)
        try #"{"retentionDays" : 90}"#.write(to: store.fileURL, atomically: true, encoding: .utf8)
        let loaded = store.load()
        #expect(loaded.configuration == Configuration.default)
        #expect(loaded.problems.count == 1)
        #expect(loaded.problems[0].field != nil)
    }

    @Test("the defaults enable English and de-CH and ship four profiles")
    func defaultsMatchTheSpec() {
        #expect(Configuration.default.languages == LanguageConfig.shippedDefaults)
        #expect(Configuration.default.profiles == AudienceProfile.shippedDefaults)
        #expect(Configuration.default.models.count == Action.allCases.count)
    }

    @Test("every action has a model, so FR-CFG-02 is editable rather than implicit")
    func modelPerAction() {
        for action in Action.allCases {
            #expect(Configuration.default.models[action] != nil)
        }
    }

    @Test("language(for:) finds a configured language and refuses an unknown one")
    func languageLookup() {
        #expect(Configuration.default.language(for: LanguageCode("de-ch")) == .swissGerman)
        #expect(Configuration.default.language(for: LanguageCode("en")) == .english)
        #expect(Configuration.default.language(for: LanguageCode("fr")) == nil)
    }

    @Test("profile(id:) finds a configured profile and refuses an unknown one")
    func profileLookup() {
        #expect(Configuration.default.profile(id: "students") == .students)
        #expect(Configuration.default.profile(id: "administration") == .administration)
        #expect(Configuration.default.profile(id: "nobody") == nil)
    }

    @Test("enabledLanguages reflects the enabled flag rather than the whole list")
    func enabledLanguagesFilters() {
        var configuration = Configuration.default
        configuration.languages[1].enabled = false
        #expect(configuration.enabledLanguages.map(\.code) == [LanguageCode("en")])
    }

    @Test("the application-support factory refuses a synced location")
    func refusesSyncedLocation() throws {
        let home = URL(fileURLWithPath: "/Users/someone")
        let locator = StorageLocator(
            home: home,
            iCloudRoots: [home.appending(path: "Library")],
            resolve: { $0 }
        )
        #expect(throws: StorageLocationError.self) {
            try ConfigurationStore.inApplicationSupport(locator: locator)
        }
    }
}
