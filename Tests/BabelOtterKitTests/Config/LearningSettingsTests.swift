import Foundation
import Testing

@testable import BabelOtterKit

@Suite("The weekly learning goal in config.json (#136)")
struct LearningSettingsTests {

    private func decode(_ json: String) throws -> LearningSettings {
        try JSONDecoder().decode(LearningSettings.self, from: Data(json.utf8))
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "babelotter-learning-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("the default is on, three days")
    func defaults() {
        #expect(LearningSettings.default == LearningSettings(enabled: true, daysPerWeek: 3))
        #expect(LearningSettings.daysRange == 1...7)
    }

    @Test("a file without learning means the default, and stays without it")
    func absent() throws {
        let data = try JSONEncoder().encode(Configuration.default)
        let configuration = try JSONDecoder().decode(Configuration.self, from: data)
        #expect(configuration.learning == nil)
        #expect(configuration.learningSettings == .default)
        let again = String(decoding: try JSONEncoder().encode(configuration), as: UTF8.self)
        #expect(!again.contains("learning"))
    }

    @Test("what is in the file is what is used, and it round-trips")
    func present() throws {
        var configuration = Configuration.default
        configuration.learning = LearningSettings(enabled: false, daysPerWeek: 5)
        let data = try JSONEncoder.configuration.encode(configuration)
        let back = try JSONDecoder().decode(Configuration.self, from: data)
        #expect(back.learningSettings == LearningSettings(enabled: false, daysPerWeek: 5))
        #expect(back == configuration)
    }

    @Test("a field left out takes its default")
    func partial() throws {
        #expect(try decode("{}") == .default)
        #expect(try decode(#"{"enabled": false}"#) == LearningSettings(enabled: false, daysPerWeek: 3))
        #expect(try decode(#"{"daysPerWeek": 7}"#) == LearningSettings(enabled: true, daysPerWeek: 7))
        #expect(try decode(#"{"daysPerWeek": 1}"#) == LearningSettings(enabled: true, daysPerWeek: 1))
    }

    @Test("days outside 1 to 7 are refused")
    func outOfRange() {
        #expect(throws: DecodingError.self) { try decode(#"{"daysPerWeek": 0}"#) }
        #expect(throws: DecodingError.self) { try decode(#"{"daysPerWeek": 8}"#) }
    }

    @Test("a bad value is reported by field, and the defaults are used")
    func reported() throws {
        let store = ConfigurationStore(directory: try temporaryDirectory())
        var configuration = Configuration.default
        configuration.learning = LearningSettings(enabled: true, daysPerWeek: 3)
        try store.save(configuration)
        var text = try String(contentsOf: store.fileURL, encoding: .utf8)
        text = text.replacingOccurrences(of: #""daysPerWeek" : 3"#, with: #""daysPerWeek" : 9"#)
        try text.write(to: store.fileURL, atomically: true, encoding: .utf8)
        let loaded = store.load()
        #expect(loaded.configuration == .default)
        #expect(loaded.problems == [
            ConfigurationProblem(
                file: "config.json", field: "learning.daysPerWeek",
                detail: "expected a number of days from 1 to 7")
        ])
    }
}

@Suite("Settings edits to the weekly learning goal (#136)")
struct SettingsLearningTests {

    @Test("the switch keeps the days, and writes the entry")
    func enabled() throws {
        var editor = SettingsEditor(configuration: .default)
        try editor.setLearningDays(5)
        editor.setLearning(enabled: false)
        #expect(editor.configuration.learning == LearningSettings(enabled: false, daysPerWeek: 5))
        editor.setLearning(enabled: true)
        #expect(editor.configuration.learning == LearningSettings(enabled: true, daysPerWeek: 5))
        try expectRoundTrip(editor)
    }

    @Test("the days take 1 to 7 and keep the switch")
    func days() throws {
        var editor = SettingsEditor(configuration: .default)
        editor.setLearning(enabled: false)
        try editor.setLearningDays(1)
        #expect(editor.configuration.learningSettings == LearningSettings(enabled: false, daysPerWeek: 1))
        try editor.setLearningDays(7)
        #expect(editor.configuration.learningSettings.daysPerWeek == 7)
        let range = SettingsRefusal.outOfRange("Between 1 and 7 days")
        expectRefusal(range) { try editor.setLearningDays(0) }
        expectRefusal(range) { try editor.setLearningDays(8) }
        #expect(editor.configuration.learningSettings.daysPerWeek == 7)
    }
}
