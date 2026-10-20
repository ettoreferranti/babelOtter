import Foundation
import Testing

@testable import BabelOtterKit

@Suite("What the Models tab offers for an action")
struct ModelChoiceTests {

    @Test("the installed models, sorted, once each")
    func installed() {
        let choice = ModelChoice(configured: "b:1", installed: ["c:1", "b:1", "a:1", "c:1"])
        #expect(choice.options == ["a:1", "b:1", "c:1"])
        #expect(choice.isInstalled)
        #expect(choice.configured == "b:1")
    }

    @Test("a configured model that is not installed is listed and marked")
    func missing() {
        let choice = ModelChoice(configured: "b:1", installed: ["c:1", "a:1"])
        #expect(choice.options == ["a:1", "b:1", "c:1"])
        #expect(!choice.isInstalled)
    }

    @Test("with nothing installed, only the configured model")
    func none() {
        let choice = ModelChoice(configured: "m", installed: [])
        #expect(choice.options == ["m"])
        #expect(!choice.isInstalled)
    }
}
