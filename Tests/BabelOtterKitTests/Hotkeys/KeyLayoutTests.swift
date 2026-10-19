import Testing

@testable import BabelOtterKit

@Suite("A hotkey's character is found on the current keyboard layout")
struct KeyLayoutTests {

    /// Key codes are positions: on Swiss German, Z sits where US has Y
    /// (kVK_ANSI_Y, 0x10) and Y where US has Z (kVK_ANSI_Z, 0x06).
    static let us = KeyLayout(characters: [0x06: "z", 0x08: "c", 0x0E: "e", 0x0F: "r", 0x10: "y", 0x11: "t", 0x12: "1"])
    static let swissGerman = KeyLayout(characters: [
        0x06: "y", 0x08: "c", 0x0E: "e", 0x0F: "r", 0x10: "z", 0x11: "t", 0x12: "1", 0x21: "\u{FC}",
    ])

    private func spec(_ text: String) -> HotKeySpec {
        switch HotKeySpec.parse(text) {
        case .success(let spec):
            return spec
        case .failure(let problem):
            Issue.record("could not parse \(text): \(problem)")
            return HotKeySpec(modifiers: 0, key: .character("?"))
        }
    }

    @Test("Z is the key labelled Z on each layout")
    func zFollowsTheLayout() throws {
        let z = spec("control+option+Z")
        #expect(try Self.us.resolve(z).get().keyCode == 0x06)
        #expect(try Self.swissGerman.resolve(z).get().keyCode == 0x10)
    }

    @Test("the combination keeps the modifiers and names the key in capitals")
    func combination() throws {
        let combination = try Self.swissGerman.resolve(spec("control+option+Z")).get()
        #expect(combination == HotKeyCombination(
            keyCode: 0x10, modifiers: 0x1800, displayName: "Control-Option-Z"))
    }

    @Test("a character the layout cannot type is reported")
    func notOnLayout() {
        let result = Self.us.resolve(spec("control+option+\u{FC}"))
        #expect(throws: HotKeyProblem.notOnLayout("\u{FC}")) { try result.get() }
        #expect(throws: Never.self) { try Self.swissGerman.resolve(spec("control+option+\u{FC}")).get() }
    }

    @Test("when two keys type the same character, the lowest code wins")
    func lowestCodeWins() throws {
        let layout = KeyLayout(characters: [0x32: "<", 0x0A: "<"])
        #expect(try layout.resolve(spec("control+<")).get().keyCode == 0x0A)
    }

    @Test("matching ignores case in the table too")
    func caseInsensitive() throws {
        let layout = KeyLayout(characters: [0x11: "T"])
        #expect(try layout.resolve(spec("control+t")).get().keyCode == 0x11)
    }

    @Test("named keys ignore the table")
    func namedKeys() throws {
        let combination = try KeyLayout(characters: [:]).resolve(spec("command+F5")).get()
        #expect(combination == HotKeyCombination(keyCode: 0x60, modifiers: 0x100, displayName: "Command-F5"))
    }

    @Test("the US table places the default keys where babelOtter registered them before #26")
    func usTable() throws {
        #expect(try KeyLayout.usANSI.resolve(spec("control+option+T")).get().keyCode == 0x11)
        #expect(try KeyLayout.usANSI.resolve(spec("control+option+C")).get().keyCode == 0x08)
    }

    @Test("same keys ignores the display name")
    func sameKeys() {
        let a = HotKeyCombination(keyCode: 0x10, modifiers: 0x1800, displayName: "Control-Option-Z")
        let b = HotKeyCombination(keyCode: 0x10, modifiers: 0x1800, displayName: "Control-Option-Y")
        let c = HotKeyCombination(keyCode: 0x10, modifiers: 0x1000, displayName: "Control-Z")
        let d = HotKeyCombination(keyCode: 0x11, modifiers: 0x1800, displayName: "Control-Option-Z")
        #expect(a.sameKeys(as: b))
        #expect(!a.sameKeys(as: c))
        #expect(!a.sameKeys(as: d))
    }
}
