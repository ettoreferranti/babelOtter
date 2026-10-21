import Foundation
import Testing

@testable import BabelOtterKit

@Suite("An audience's id is made once from its first name")
struct AudienceIDTests {

    @Test("names become readable ids", arguments: [
        ("Students", "students"), ("Beh\u{00F6}rden", "behorden"), ("Stra\u{00DF}e", "strasse"),
        ("\u{00DC}-Pr\u{00FC}fung 2", "u-prufung-2"), ("  Die  neuen -- Kollegen! ", "die-neuen-kollegen"),
        ("STRASSE \u{1E9E}", "strasse-ss"), ("Zone 09 a", "zone-09-a"), ("az09", "az09"), ("   ", "audience"), ("!!!", "audience"), ("\u{65E5}\u{672C}", "audience"),
    ])
    func slug(name: String, id: String) {
        #expect(AudienceID.make(from: name, taken: []) == id)
    }

    @Test("a taken id gets the next free number")
    func taken() {
        #expect(AudienceID.make(from: "Students", taken: ["students"]) == "students-2")
        #expect(AudienceID.make(from: "Students", taken: ["students", "students-2"]) == "students-3")
        #expect(AudienceID.make(from: "Students", taken: ["students-2"]) == "students")
        #expect(AudienceID.make(from: "x", taken: ["x", "x-2", "x-3", "x-4"]) == "x-5")
    }

    @Test("past a thousand numbers, one more than all of them")
    func overflow() {
        var taken: Set<String> = ["x"]
        for number in 2...1_000 { taken.insert("x-\(number)") }
        #expect(AudienceID.make(from: "x", taken: taken) == "x-2000")
    }
}

@Suite("The Audiences tab's edits are checked before they change anything")
struct SettingsAudienceTests {

    private func editor() -> SettingsEditor { SettingsEditor(configuration: .default) }

    @Test("adding gives Sie, no guidance and an id from the name, and loads back")
    func add() throws {
        var editor = editor()
        let id = try editor.addAudience(named: "  Beh\u{00F6}rden ")
        #expect(id == "behorden")
        let added = try #require(editor.configuration.profile(id: id))
        #expect(added == AudienceProfile(id: "behorden", name: "Beh\u{00F6}rden", register: .formal, toneGuidance: ""))
        #expect(editor.configuration.profiles.last?.id == id)
        try expectRoundTrip(editor)
    }


    @Test("an id whose name is free but whose slug is taken is numbered")
    func idCollision() throws {
        var editor = editor()
        // Another name, but the same slug as "Students".
        let id = try editor.addAudience(named: "STUDENTS!")
        #expect(id == "students-2")
        #expect(editor.configuration.profile(id: "students")?.name == "Students")
        #expect(editor.configuration.profile(id: "students-2")?.name == "STUDENTS!")
    }

    @Test("names are trimmed, not empty, at most 40 characters and unique ignoring case")
    func names() throws {
        var editor = editor()
        expectRefusal(.emptyName) { _ = try editor.addAudience(named: "  ") }
        expectRefusal(.nameTooLong) { _ = try editor.addAudience(named: String(repeating: "a", count: 41)) }
        expectRefusal(.nameInUse("students")) { _ = try editor.addAudience(named: "students") }
        _ = try editor.addAudience(named: String(repeating: "a", count: 40))
        #expect(editor.configuration.profiles.count == 5)
        #expect(SettingsRefusal.nameTooLong.message == "At most 40 characters.")
        #expect(SettingsRefusal.nameInUse("X").message == "Another audience is called X.")
        #expect(SettingsRefusal.emptyName.message == "Enter a name.")
    }

    @Test("renaming keeps the id; its own name in another case is allowed")
    func rename() throws {
        var editor = editor()
        try editor.renameAudience("students", to: "STUDENTS")
        try editor.renameAudience("students", to: "  Studierende  ")
        #expect(editor.configuration.profile(id: "students")?.name == "Studierende")
        // Its own id is fine as its name; another audience's id is not.
        try editor.renameAudience("students", to: "students")
        expectRefusal(.nameInUse("Colleagues")) { try editor.renameAudience("informal", to: "Colleagues") }
        try editor.renameAudience("students", to: "Studierende")
        expectRefusal(.nameInUse("STUDENTS")) { try editor.renameAudience("informal", to: "STUDENTS") }
        expectRefusal(.nameInUse("colleagues")) { _ = try editor.addAudience(named: "colleagues") }
        let before = editor
        expectRefusal(.nameInUse("Colleagues")) { try editor.renameAudience("students", to: "Colleagues") }
        expectRefusal(.noSuchAudience("gone")) { try editor.renameAudience("gone", to: "X") }
        #expect(editor == before)
        try expectRoundTrip(editor)
        #expect(SettingsRefusal.noSuchAudience("gone").message == "There is no audience gone.")
    }

    @Test("register and guidance are written; guidance at most 2,000 characters")
    func registerAndGuidance() throws {
        var editor = editor()
        try editor.setRegister(.informal, forAudience: "students")
        try editor.setToneGuidance("  Kurz.\nFreundlich. \n", forAudience: "students")
        let students = try #require(editor.configuration.profile(id: "students"))
        #expect(students.register == .informal)
        #expect(students.toneGuidance == "Kurz.\nFreundlich.")
        try editor.setToneGuidance(" \n\t ", forAudience: "students")
        #expect(editor.configuration.profile(id: "students")?.toneGuidance == "")
        try editor.setToneGuidance(String(repeating: "a", count: 2_000), forAudience: "students")
        expectRefusal(.outOfRange("At most 2,000 characters")) {
            try editor.setToneGuidance(String(repeating: "a", count: 2_001), forAudience: "students")
        }
        expectRefusal(.noSuchAudience("x")) { try editor.setRegister(.formal, forAudience: "x") }
        expectRefusal(.noSuchAudience("x")) { try editor.setToneGuidance("", forAudience: "x") }
        try expectRoundTrip(editor)
    }

    @Test("terms are one per line, trimmed, blanks dropped, within the limits")
    func terms() throws {
        var editor = editor()
        try editor.setPreferredTerms("  Modul \n\n Studierende, nicht Studenten\r\n  \n", forAudience: "students")
        #expect(editor.configuration.profile(id: "students")?.glossaryBias
            == ["Modul", "Studierende, nicht Studenten"])
        let fifty = (1...50).map { "t\($0)" }.joined(separator: "\n")
        try editor.setPreferredTerms(fifty, forAudience: "students")
        #expect(editor.configuration.profile(id: "students")?.glossaryBias.count == 50)
        expectRefusal(.outOfRange("At most 50 terms")) {
            try editor.setPreferredTerms(fifty + "\nt51", forAudience: "students")
        }
        try editor.setPreferredTerms(String(repeating: "b", count: 80), forAudience: "students")
        expectRefusal(.outOfRange("A term has at most 80 characters")) {
            try editor.setPreferredTerms(String(repeating: "b", count: 81), forAudience: "students")
        }
        expectRefusal(.noSuchAudience("x")) { try editor.setPreferredTerms("a", forAudience: "x") }
        try editor.setPreferredTerms("", forAudience: "students")
        #expect(editor.configuration.profile(id: "students")?.glossaryBias == [])
        try expectRoundTrip(editor)
    }

    @Test("deleting removes it, but never the last one")
    func delete() throws {
        var editor = editor()
        try editor.deleteAudience("students")
        try editor.deleteAudience("colleagues")
        try editor.deleteAudience("administration")
        #expect(editor.configuration.profiles.map(\.id) == ["informal"])
        expectRefusal(.lastAudience) { try editor.deleteAudience("informal") }
        // An unknown id is that, not "the last one".
        expectRefusal(.noSuchAudience("students")) { try editor.deleteAudience("students") }
        #expect(editor.configuration.profiles.map(\.id) == ["informal"])
        try expectRoundTrip(editor)
        #expect(SettingsRefusal.lastAudience.message == "At least one audience stays.")
    }

    @Test("restore adds back missing shipped audiences at the end, skipping a name in use")
    func restore() throws {
        var editor = editor()
        #expect(editor.restoreShippedAudiences() == ([], []))
        try editor.deleteAudience("students")
        try editor.deleteAudience("administration")
        try editor.renameAudience("informal", to: "Students")
        try editor.setToneGuidance("mine", forAudience: "colleagues")
        let result = editor.restoreShippedAudiences()
        #expect(result.restored == ["Administration"])
        #expect(result.skipped == ["Students"])
        #expect(editor.configuration.profiles.map(\.id) == ["colleagues", "informal", "administration"])
        #expect(editor.configuration.profile(id: "colleagues")?.toneGuidance == "mine")
        try expectRoundTrip(editor)
    }

    @Test("a shipped audience whose id is now another's name is not restored")
    func restoreSkipsIdAsName() throws {
        var editor = editor()
        try editor.deleteAudience("informal")
        try editor.renameAudience("colleagues", to: "informal")
        let result = editor.restoreShippedAudiences()
        #expect(result.restored == [])
        #expect(result.skipped == ["Informal"])
    }
}
