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
}
