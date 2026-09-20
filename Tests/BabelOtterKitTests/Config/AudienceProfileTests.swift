import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Audience profiles")
struct AudienceProfileTests {

    @Test("a fresh install ships Students, Colleagues, Administration and Informal")
    func shippedDefaults() {
        #expect(
            AudienceProfile.shippedDefaults.map(\.id)
                == ["students", "colleagues", "administration", "informal"])
    }

    @Test("every shipped profile carries a name and tone guidance a prompt can use")
    func everyDefaultIsComplete() {
        for profile in AudienceProfile.shippedDefaults {
            #expect(!profile.name.isEmpty)
            #expect(!profile.toneGuidance.isEmpty, "\(profile.id) has no tone guidance to put in a prompt")
        }
    }

    @Test("Administration is formal and Informal is not")
    func registersDiffer() {
        #expect(AudienceProfile.administration.register == .formal)
        #expect(AudienceProfile.informal.register == .informal)
    }

    @Test("register encodes as the German pronoun a reader would expect")
    func registerRawValues() {
        #expect(Register.formal.rawValue == "Sie")
        #expect(Register.informal.rawValue == "du")
    }

    @Test("profile ids are stable strings, not UUIDs, so the file stays hand-editable")
    func idsAreReadable() {
        #expect(AudienceProfile.students.id == "students")
        #expect(UUID(uuidString: AudienceProfile.students.id) == nil)
    }

    @Test("a profile round-trips through Codable")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(AudienceProfile.students)
        #expect(try JSONDecoder().decode(AudienceProfile.self, from: data) == AudienceProfile.students)
    }

    @Test("the shipped ids are unique, so lookup by id cannot be ambiguous")
    func idsAreUnique() {
        let ids = AudienceProfile.shippedDefaults.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
