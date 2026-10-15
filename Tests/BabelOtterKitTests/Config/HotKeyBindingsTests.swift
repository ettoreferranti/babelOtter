import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Hotkey bindings in config.json")
struct HotKeyBindingsTests {

    private func decode(_ json: String) throws -> HotKeyBindings {
        try JSONDecoder().decode(HotKeyBindings.self, from: Data(json.utf8))
    }

    @Test("a string is the text as written; an absent action is its default")
    func textAndAbsent() throws {
        let bindings = try decode(#"{"translate": "control+option+Y"}"#)
        #expect(bindings.translate == .text("control+option+Y"))
        #expect(bindings.correct == .useDefault)
    }

    @Test("null turns a hotkey off")
    func nullIsOff() throws {
        #expect(try decode(#"{"translate": null}"#).translate == .off)
    }

    @Test("an empty object leaves both at their defaults")
    func emptyObject() throws {
        #expect(try decode("{}") == HotKeyBindings())
    }

    @Test("a number where text belongs is a decoding error, not a silent default")
    func wrongType() {
        #expect(throws: DecodingError.self) { try decode(#"{"translate": 5}"#) }
    }

    @Test("off is written as null and a default is left out, so the file round-trips")
    func encoding() throws {
        let bindings = HotKeyBindings(translate: .useDefault, correct: .off)
        let data = try JSONEncoder().encode(bindings)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("translate"))
        #expect(text.contains(#""correct":null"#))
        #expect(try JSONDecoder().decode(HotKeyBindings.self, from: data) == bindings)
    }

    @Test("the defaults are Control-Option-T, -C and -E, as text")
    func defaults() {
        #expect(HotKeyBindings.defaults.translate == .text("control+option+T"))
        #expect(HotKeyBindings.defaults.correct == .text("control+option+C"))
        #expect(HotKeyBindings.defaults.explain == .text("control+option+E"))
        #expect(HotKeyBindings.defaultText(for: .translate) == "control+option+T")
        #expect(HotKeyBindings.defaultText(for: .correct) == "control+option+C")
        #expect(HotKeyBindings.defaultText(for: .explain) == "control+option+E")
        #expect(HotKeyBindings.defaultText(for: .repitch) == nil)
    }

    @Test("each action reads its own binding; Re-pitch has none yet")
    func bindingForAction() {
        let bindings = HotKeyBindings(translate: .text("a"), correct: .text("b"), explain: .text("e"))
        #expect(bindings.binding(for: .translate) == .text("a"))
        #expect(bindings.binding(for: .correct) == .text("b"))
        #expect(bindings.binding(for: .explain) == .text("e"))
        #expect(bindings.binding(for: .repitch) == .off)
    }

    @Test("explain is read from the file: text, null, or absent")
    func explainDecodes() throws {
        #expect(try decode(#"{"explain": "control+option+X"}"#).explain == .text("control+option+X"))
        #expect(try decode(#"{"explain": null}"#).explain == .off)
        #expect(try decode("{}").explain == .useDefault)
    }

    @Test("explain off is written as null and round-trips")
    func explainEncodes() throws {
        let bindings = HotKeyBindings(explain: .off)
        let data = try JSONEncoder().encode(bindings)
        #expect(String(decoding: data, as: UTF8.self).contains(#""explain":null"#))
        #expect(try JSONDecoder().decode(HotKeyBindings.self, from: data) == bindings)
    }

    @Test("a fresh configuration writes both defaults out, so the field is discoverable")
    func defaultConfigurationHasThem() {
        #expect(Configuration.default.hotkeys == HotKeyBindings.defaults)
    }
}
