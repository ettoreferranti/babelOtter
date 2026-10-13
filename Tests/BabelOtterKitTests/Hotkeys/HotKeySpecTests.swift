import Testing

@testable import BabelOtterKit

@Suite("Hotkey text is parsed into modifiers and a key")
struct HotKeySpecTests {

    private func parse(_ text: String) -> HotKeySpec? {
        try? HotKeySpec.parse(text).get()
    }

    private func problem(_ text: String) -> HotKeyProblem? {
        switch HotKeySpec.parse(text) {
        case .success:
            return nil
        case .failure(let problem):
            return problem
        }
    }

    @Test("the default is control and option with the letter t")
    func controlOptionT() {
        #expect(parse("control+option+T") == HotKeySpec(modifiers: 0x1800, key: .character("t")))
    }

    @Test("short spellings, any order, any case, spaces around parts")
    func spellings() {
        let expected = HotKeySpec(modifiers: 0x1800, key: .character("t"))
        #expect(parse(" Ctrl + Alt + t ") == expected)
        #expect(parse("t+option+CONTROL") == expected)
        #expect(parse("cmd+shift+a") == HotKeySpec(modifiers: 0x300, key: .character("a")))
        #expect(parse("command+option+a")?.modifiers == 0x900)
    }

    @Test("named keys carry their fixed key codes")
    func namedKeys() {
        #expect(parse("control+F5") == HotKeySpec(modifiers: 0x1000, key: .named(.f5)))
        #expect(NamedKey.f1.keyCode == 0x7A)
        #expect(NamedKey.f5.keyCode == 0x60)
        #expect(NamedKey.f12.keyCode == 0x6F)
        #expect(NamedKey.f20.keyCode == 0x5A)
        #expect(NamedKey.space.keyCode == 0x31)
        #expect(NamedKey.returnKey.keyCode == 0x24)
        #expect(NamedKey.tab.keyCode == 0x30)
        #expect(NamedKey.escape.keyCode == 0x35)
        #expect(NamedKey.delete.keyCode == 0x33)
        #expect(NamedKey.left.keyCode == 0x7B)
        #expect(NamedKey.right.keyCode == 0x7C)
        #expect(NamedKey.down.keyCode == 0x7D)
        #expect(NamedKey.up.keyCode == 0x7E)
        #expect(parse("option+return")?.key == .named(.returnKey))
        #expect(NamedKey.returnKey.label == "Return")
        #expect(NamedKey.f12.label == "F12")
    }

    @Test("every F key from 1 to 20 is named, each with its own code")
    func allFunctionKeys() {
        var codes: Set<UInt32> = []
        for number in 1...20 {
            let key = NamedKey(rawValue: "f\(number)")
            #expect(key != nil)
            if let key {
                codes.insert(key.keyCode)
            }
        }
        #expect(codes.count == 20)
    }

    @Test("a letter outside ASCII is a character key")
    func nonASCIICharacter() {
        #expect(parse("control+option+\u{FC}")?.key == .character("\u{FC}"))
    }

    @Test("each mistake has its own problem")
    func problems() {
        #expect(problem("") == .empty)
        #expect(problem("   ") == .empty)
        #expect(problem("control++") == .emptyPart)
        #expect(problem("contrl+option+T") == .unknownPart("contrl"))
        #expect(problem("control+option") == .noKey)
        #expect(problem("control+T+C") == .severalKeys)
        #expect(problem("shift+T") == .needsModifier)
        #expect(problem("T") == .needsModifier)
    }

    @Test("problems are worded for the menu")
    func details() {
        #expect(HotKeyProblem.empty.detail == "is empty")
        #expect(HotKeyProblem.emptyPart.detail == "has an empty part (\"+\" cannot be the key)")
        #expect(HotKeyProblem.unknownPart("contrl").detail == "unknown key or modifier \"contrl\"")
        #expect(HotKeyProblem.noKey.detail == "names no key")
        #expect(HotKeyProblem.severalKeys.detail == "names more than one key")
        #expect(HotKeyProblem.needsModifier.detail == "needs control, option or command")
        #expect(HotKeyProblem.notOnLayout("\u{FC}").detail
            == "\"\u{FC}\" can't be typed on the current keyboard layout")
        #expect(HotKeyProblem.sharedWith(.translate).detail == "is also the Translate hotkey")
    }

    @Test("display names order modifiers as macOS does")
    func displayOrder() {
        #expect(HotKeySpec.displayName(modifiers: 0x1B00, keyLabel: "Z")
            == "Control-Option-Shift-Command-Z")
        #expect(HotKeySpec.displayName(modifiers: 0x1800, keyLabel: "T") == "Control-Option-T")
        #expect(HotKeySpec.displayName(modifiers: 0x100, keyLabel: "F5") == "Command-F5")
    }
}
