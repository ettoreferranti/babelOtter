import Foundation

@testable import BabelOtterKit

extension HistoryRecord {

    /// A synthetic record; every field can be overridden.
    static func sample(
        date: Date = Date(timeIntervalSince1970: 1_790_000_000),
        action: Action = .translate,
        sourceLanguage: LanguageCode = LanguageCode("de-CH"),
        targetLanguage: LanguageCode? = LanguageCode("en"),
        profileID: String? = "colleagues",
        model: String = "mistral-small3.2:24b",
        bundleID: String? = "com.apple.mail",
        appName: String? = "Mail",
        source: String = "Hallo zusammen",
        result: String = "Hello everyone"
    ) -> HistoryRecord {
        HistoryRecord(
            date: date, action: action, sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage, profileID: profileID, model: model,
            sourceBundleID: bundleID, sourceAppName: appName,
            source: UserText(source), result: UserText(result))
    }

    /// A synthetic Correct record with a word count and mistakes (#78).
    static func correction(
        date: Date = Date(timeIntervalSince1970: 1_790_000_000),
        language: LanguageCode = LanguageCode("de-CH"),
        words: Int = 100,
        mistakes: [Mistake] = []
    ) -> HistoryRecord {
        HistoryRecord(
            date: date, action: .correct, sourceLanguage: language, targetLanguage: nil,
            profileID: "colleagues", model: "m", sourceBundleID: nil, sourceAppName: nil,
            source: UserText("text"), result: UserText("text"), wordCount: words, mistakes: mistakes)
    }
}

extension Mistake {

    static func sample(
        _ category: ErrorCategory = .grammaticalCase, original: String = "mit der Kollege",
        corrected: String = "mit dem Kollegen", explanation: String = "mit takes the dative"
    ) -> Mistake {
        Mistake(
            category: category, original: UserText(original), corrected: UserText(corrected),
            explanation: UserText(explanation))
    }
}
