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

    @Test("null means none; a language not shipped has none; written forms are used")
    func explicit() throws {
        let noForms = #"{"code": "de-ch", "displayName": "D", "localeRules": [], "enabled": true, "addressForms": null}"#
        #expect(try language(noForms).addressForms == nil)
        let italian = #"{"code": "it", "displayName": "Italian", "localeRules": [], "enabled": true}"#
        #expect(try language(italian).addressForms == nil)
        let withForms = #"{"code": "it", "displayName": "Italian", "localeRules": [], "enabled": true, "addressForms": {"formal": " Lei ", "informal": "tu"}}"#
        #expect(try language(withForms).addressForms == AddressForms(formal: "Lei", informal: "tu"))
    }

    @Test("a blank form is a problem")
    func blank() {
        let blank = #"{"code": "it", "displayName": "I", "localeRules": [], "enabled": true, "addressForms": {"formal": " ", "informal": "tu"}}"#
        #expect(throws: DecodingError.self) { _ = try language(blank) }
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
