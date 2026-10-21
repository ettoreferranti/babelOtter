import Foundation
import Testing

@testable import BabelOtterKit

@Suite("An audience's register is formal or informal, the old pronouns included")
struct RegisterTests {

    private struct Holder: Codable { let register: Register }

    private func decode(_ value: String) throws -> Register {
        try JSONDecoder().decode(Holder.self, from: Data(#"{"register": \#(value)}"#.utf8)).register
    }

    @Test("formal, informal and the pre-#110 pronouns are read", arguments: [
        (#""formal""#, Register.formal), (#""informal""#, .informal), (#""Sie""#, .formal),
        (#"" du ""#, .informal), (#""SIE""#, .formal), (#""Informal""#, .informal),
    ])
    func accepted(written: String, expected: Register) throws {
        #expect(try decode(written) == expected)
    }

    @Test("anything else names the two values", arguments: [#""vous""#, #""""#, "null", "1"])
    func refused(written: String) {
        do {
            _ = try decode(written)
            Issue.record("\(written) was accepted")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription == Register.expected)
        } catch {
            // null and 1 fail as the wrong type before the value is read.
            #expect(written == "null" || written == "1")
        }
    }

    @Test("written as formal or informal")
    func encoding() throws {
        let text = String(decoding: try JSONEncoder().encode(Holder(register: .informal)), as: UTF8.self)
        #expect(text == #"{"register":"informal"}"#)
        #expect(Register.formal.word == "formal")
        #expect(Register.informal.word == "informal")
        #expect(Register.formal.phrase == "a formal register")
        #expect(Register.informal.phrase == "an informal register")
    }
}

@Suite("A language's forms of address are data")
struct AddressFormsTests {

    private func language(_ json: String) throws -> LanguageConfig {
        try JSONDecoder().decode(LanguageConfig.self, from: Data(json.utf8))
    }

    private let germanWithout = #"{"code": "de-CH", "displayName": "Swiss Standard German", "localeRules": [], "enabled": true}"#

    @Test("a shipped language without the key gets its shipped forms")
    func absentTakesShipped() throws {
        #expect(try language(germanWithout).addressForms == AddressForms(formal: "Sie", informal: "du"))
        let english = #"{"code": "en", "displayName": "English", "localeRules": [], "enabled": true}"#
        #expect(try language(english).addressForms == nil)
    }

    @Test("another German without the key takes the shipped German forms by base code")
    func baseSubtag() throws {
        for code in ["de", "de-DE", "de-at"] {
            let json = #"{"code": "\#(code)", "displayName": "German", "localeRules": [], "enabled": true}"#
            #expect(try language(json).addressForms == AddressForms(formal: "Sie", informal: "du"), "\(code)")
        }
        let englishVariant = #"{"code": "en-GB", "displayName": "British English", "localeRules": [], "enabled": true}"#
        #expect(try language(englishVariant).addressForms == nil)
    }

    @Test("null means none; a language not shipped has none; written forms are used")
    func explicit() throws {
        let noForms = #"{"code": "de-ch", "displayName": "D", "localeRules": [], "enabled": true, "addressForms": null}"#
        #expect(try language(noForms).addressForms == nil)
        let italian = #"{"code": "it", "displayName": "Italian", "localeRules": [], "enabled": true}"#
        #expect(try language(italian).addressForms == nil)
        let withForms = #"{"code": "it", "displayName": "Italian", "localeRules": [], "enabled": true, "addressForms": {"formal": " Lei ", "informal": "tu"}}"#
        #expect(try language(withForms).addressForms == AddressForms(formal: "Lei", informal: "tu"))
    }

    @Test("a blank form, either one, is a problem; forms are trimmed")
    func blank() throws {
        for forms in [#"{"formal": " ", "informal": "tu"}"#, #"{"formal": "Lei", "informal": " "}"#] {
            let json = #"{"code": "it", "displayName": "I", "localeRules": [], "enabled": true, "addressForms": \#(forms)}"#
            #expect(throws: DecodingError.self) { _ = try language(json) }
        }
        let padded = #"{"code": "it", "displayName": "I", "localeRules": [], "enabled": true, "addressForms": {"formal": "Lei", "informal": " tu "}}"#
        #expect(try language(padded).addressForms?.informal == "tu")
    }

    @Test("a German with no forms stays without them through a round trip")
    func noneStaysNone() throws {
        let none = LanguageConfig(code: LanguageCode("de-ch"), displayName: "D", localeRules: [], enabled: true)
        let data = try JSONEncoder.configuration.encode(none)
        #expect(try JSONDecoder().decode(LanguageConfig.self, from: data).addressForms == nil)
    }

    @Test("the key is always written, null for none, and reads back")
    func roundTrip() throws {
        for config in [LanguageConfig.english, .swissGerman] {
            let text = String(decoding: try JSONEncoder.configuration.encode(config), as: UTF8.self)
            #expect(text.contains(#""addressForms""#))
            #expect(try JSONDecoder().decode(LanguageConfig.self, from: Data(text.utf8)) == config)
        }
        #expect(AddressForms(formal: "Lei", informal: "tu").form(for: .informal) == "tu")
        #expect(AddressForms(formal: "Lei", informal: "tu").form(for: .formal) == "Lei")
    }
}

@Suite("A config.json from before #110 loads and is saved in the new form")
struct PreFormalityFileTests {

    @Test("pronoun registers and languages without forms load as before, and save as formal and addressForms")
    func oldFile() throws {
        // What the build before #110 wrote: no addressForms, Sie/du registers.
        var text = String(decoding: try JSONEncoder.configuration.encode(Configuration.default), as: UTF8.self)
        text = text.replacingOccurrences(of: #""register" : "formal""#, with: #""register" : "Sie""#)
        text = text.replacingOccurrences(of: #""register" : "informal""#, with: #""register" : "du""#)
        text = text.replacingOccurrences(
            of: #",\s*"addressForms" : (null|\{[^}]*\})"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #""addressForms" : (null|\{[^}]*\}),\s*"#, with: "", options: .regularExpression)
        #expect(!text.contains("addressForms"))
        #expect(text.contains(#""register" : "Sie""#))

        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "babelotter-formality-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = ConfigurationStore(directory: folder)
        try text.write(to: store.fileURL, atomically: true, encoding: .utf8)

        let loaded = store.load()
        #expect(loaded.problems.isEmpty)
        #expect(loaded.configuration == Configuration.default)
        #expect(loaded.configuration.language(for: LanguageCode("de-ch"))?.addressForms
            == AddressForms(formal: "Sie", informal: "du"))
        #expect(loaded.configuration.profile(id: "students")?.register == .formal)
        #expect(loaded.configuration.profile(id: "colleagues")?.register == .informal)

        try store.save(loaded.configuration)
        let saved = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(saved.contains(#""register" : "formal""#))
        #expect(!saved.contains(#""register" : "Sie""#))
        #expect(saved.contains(#""addressForms""#))
    }
}
