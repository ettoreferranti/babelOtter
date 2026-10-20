import Foundation
import Testing

@testable import BabelOtterKit

@Suite("A pressed shortcut is written as config.json reads it")
struct HotKeyTextTests {

    /// US letters plus digits.
    static let us = KeyLayout(characters: KeyLayout.usANSI.characters.merging([
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5",
        0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0",
    ]) { first, _ in first })

    /// Swiss German: Y and Z swap, and umlauts have keys of their own.
    static let swiss = KeyLayout(characters: KeyLayout.usANSI.characters.merging([
        0x06: "y", 0x10: "z", 0x21: "\u{00FC}", 0x29: "\u{00F6}", 0x27: "\u{00E4}",
    ]) { _, swiss in swiss })

    static let modifierSets: [UInt32] = [
        HotKeySpec.control | HotKeySpec.option,
        HotKeySpec.command,
        HotKeySpec.command | HotKeySpec.shift,
        HotKeySpec.control | HotKeySpec.option | HotKeySpec.shift | HotKeySpec.command,
    ]

    @Test("every key reads back to the same key and modifiers", arguments: [us, swiss])
    func roundTrip(layout: KeyLayout) throws {
        var codes = Array(layout.characters.keys)
        codes += NamedKey.allCases.map(\.keyCode)
        for code in codes {
            for modifiers in Self.modifierSets {
                let text = try #require(HotKeyText.text(keyCode: code, modifiers: modifiers, layout: layout))
                let spec = try HotKeySpec.parse(text).get()
                let combination = try layout.resolve(spec).get()
                #expect(combination.keyCode == code, "\(text)")
                #expect(combination.modifiers == modifiers, "\(text)")
            }
        }
    }

    @Test("modifiers come in macOS's order, a letter in capitals, a named key by name")
    func spelling() {
        let all = HotKeySpec.command | HotKeySpec.shift | HotKeySpec.option | HotKeySpec.control
        #expect(HotKeyText.text(keyCode: 0x11, modifiers: all, layout: Self.us)
            == "control+option+shift+command+T")
        #expect(HotKeyText.text(keyCode: 0x11, modifiers: HotKeySpec.control | HotKeySpec.option, layout: Self.us)
            == "control+option+T")
        #expect(HotKeyText.text(keyCode: 0x60, modifiers: HotKeySpec.command, layout: Self.us) == "command+f5")
        #expect(HotKeyText.text(keyCode: 0x06, modifiers: HotKeySpec.command, layout: Self.swiss) == "command+Y")
        #expect(HotKeyText.text(keyCode: 0x21, modifiers: HotKeySpec.option, layout: Self.swiss)
            == "option+\u{00DC}")
    }

    @Test("a key with no name and no character, or one the syntax cannot hold, gives none")
    func unnamed() {
        let odd = KeyLayout(characters: [0x18: "+", 0x2A: " ", 0x2B: "ab"])
        for code: UInt32 in [0x18, 0x2A, 0x2B, 0x7F] {
            #expect(HotKeyText.text(keyCode: code, modifiers: HotKeySpec.command, layout: odd) == nil)
        }
    }

    @Test("a refusal reads as a sentence")
    func sentences() {
        #expect(HotKeyText.sentence(.needsModifier) == "Use Command, Control or Option with the key.")
        #expect(HotKeyText.sentence(.sharedWith(.correct)) == "Already the Correct hotkey.")
        #expect(HotKeyText.sentence(.previousTakenBy(.explain)) == "Already the Explain hotkey.")
        #expect(HotKeyText.sentence(.notOnLayout("\u{00E9}"))
            == "\"\u{00E9}\" can't be typed on this keyboard layout.")
        for problem in [HotKeyProblem.empty, .emptyPart, .unknownPart("x"), .noKey, .severalKeys] {
            #expect(HotKeyText.sentence(problem) == "lingoSwen can't use this key as a hotkey.")
        }
        #expect(SettingsRefusal.hotKey(.needsModifier).message == HotKeyText.sentence(.needsModifier))
    }
}

@Suite("The settings window sets a hotkey only when it can be used")
struct SettingsHotKeyTests {

    private let layout = HotKeyTextTests.us

    @Test("a recorded shortcut is written as text and loads back")
    func recorded() throws {
        var editor = SettingsEditor(configuration: .default)
        try editor.setHotKey(.text("control+shift+Y"), for: .explain, layout: layout)
        #expect(editor.configuration.hotkeys?.explain == .text("control+shift+Y"))
        #expect(editor.configuration.hotkeys?.translate == .text("control+option+T"))
        try expectRoundTrip(editor)
    }

    @Test("off and default are written as such")
    func offAndDefault() throws {
        var editor = SettingsEditor(configuration: .default)
        try editor.setHotKey(.off, for: .correct, layout: layout)
        #expect(editor.configuration.hotkeys?.correct == .off)
        try expectRoundTrip(editor)
        try editor.setHotKey(.useDefault, for: .correct, layout: layout)
        #expect(editor.configuration.hotkeys?.correct == .useDefault)
        try expectRoundTrip(editor)
    }

    @Test("a file with no hotkeys gets one for the edited action only")
    func noHotkeysYet() throws {
        var configuration = Configuration.default
        configuration.hotkeys = nil
        var editor = SettingsEditor(configuration: configuration)
        try editor.setHotKey(.text("command+F5"), for: .repitch, layout: layout)
        #expect(editor.configuration.hotkeys == HotKeyBindings(repitch: .text("command+F5")))
    }

    @Test("another action's keys are refused, whichever comes first")
    func shared() {
        var editor = SettingsEditor(configuration: .default)
        expectRefusal(.hotKey(.sharedWith(.correct))) {
            try editor.setHotKey(.text("option+control+c"), for: .translate, layout: layout)
        }
        expectRefusal(.hotKey(.sharedWith(.translate))) {
            try editor.setHotKey(.text("control+option+T"), for: .repitch, layout: layout)
        }
        // A default counts as the keys it stands for.
        var defaults = Configuration.default
        defaults.hotkeys = HotKeyBindings()
        var fromDefaults = SettingsEditor(configuration: defaults)
        expectRefusal(.hotKey(.sharedWith(.explain))) {
            try fromDefaults.setHotKey(.text("control+option+E"), for: .correct, layout: layout)
        }
        #expect(editor.configuration == .default)
    }

    @Test("an action's own keys, and keys of an action that is off, are free")
    func free() throws {
        var editor = SettingsEditor(configuration: .default)
        try editor.setHotKey(.text("control+option+T"), for: .translate, layout: layout)
        try editor.setHotKey(.off, for: .correct, layout: layout)
        try editor.setHotKey(.text("control+option+C"), for: .explain, layout: layout)
        #expect(editor.configuration.hotkeys?.explain == .text("control+option+C"))
    }

    @Test("another action's hotkey that does not resolve takes no keys")
    func brokenOther() throws {
        var configuration = Configuration.default
        configuration.hotkeys?.correct = .text("contrl+option+C")
        var editor = SettingsEditor(configuration: configuration)
        try editor.setHotKey(.text("control+option+C"), for: .explain, layout: layout)
        #expect(editor.configuration.hotkeys?.explain == .text("control+option+C"))
    }

    @Test("a shortcut that cannot be used is refused with its reason")
    func unusable() {
        var editor = SettingsEditor(configuration: .default)
        expectRefusal(.hotKey(.needsModifier)) { try editor.setHotKey(.text("shift+K"), for: .translate, layout: layout) }
        expectRefusal(.hotKey(.notOnLayout("\u{00E9}"))) {
            try editor.setHotKey(.text("command+\u{00E9}"), for: .translate, layout: layout)
        }
        expectRefusal(.hotKey(.empty)) { try editor.setHotKey(.text(" "), for: .translate, layout: layout) }
        #expect(editor.configuration == .default)
    }
}
