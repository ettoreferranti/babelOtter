import Foundation

/// One error Correct found, as History keeps it for Progress (#78). The
/// fragments are the user's text, so they are `UserText` too.
public struct Mistake: Sendable, Equatable {
    public let category: ErrorCategory
    public let original: UserText
    public let corrected: UserText
    public let explanation: UserText

    public init(category: ErrorCategory, original: UserText, corrected: UserText, explanation: UserText) {
        self.category = category
        self.original = original
        self.corrected = corrected
        self.explanation = explanation
    }

    public init(_ error: CorrectionError) {
        self.init(
            category: error.category, original: UserText(error.original),
            corrected: UserText(error.corrected), explanation: UserText(error.explanation))
    }
}

/// One completed action, as history keeps it (#67, `FR-HIS-01`).
///
/// `source` and `result` are `UserText`, so describing or dumping a record
/// shows neither (`NFR-P5`).
public struct HistoryRecord: Sendable, Equatable {
    /// Nil until a store has kept the record.
    public var id: Int64?
    public let date: Date
    public let action: Action
    public let sourceLanguage: LanguageCode
    /// Translate's target, and English for Explain; nil for Correct and
    /// Re-pitch, which keep the text's language.
    public let targetLanguage: LanguageCode?
    /// The audience the result was written for; nil for Explain.
    public let profileID: String?
    public let model: String
    public let sourceBundleID: String?
    public let sourceAppName: String?
    public let source: UserText
    /// What Replace or Copy would have used.
    public let result: UserText
    /// Correct only (#78): the words corrected, and the errors found --
    /// never the suggestions. Nil and empty for the other actions.
    public let wordCount: Int?
    public let mistakes: [Mistake]

    public init(
        id: Int64? = nil, date: Date, action: Action, sourceLanguage: LanguageCode,
        targetLanguage: LanguageCode?, profileID: String?, model: String,
        sourceBundleID: String?, sourceAppName: String?, source: UserText, result: UserText,
        wordCount: Int? = nil, mistakes: [Mistake] = []
    ) {
        self.id = id
        self.date = date
        self.action = action
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.profileID = profileID
        self.model = model
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.source = source
        self.result = result
        self.wordCount = wordCount
        self.mistakes = mistakes
    }
}

extension HistoryRecord {

    public init(
        translation result: TranslationResult, source: UserText, model: String,
        application: SourceApplication?, date: Date
    ) {
        self.init(
            date: date, action: .translate, sourceLanguage: result.direction.source,
            targetLanguage: result.direction.target, profileID: result.audience.id,
            model: model, sourceBundleID: application?.bundleIdentifier,
            sourceAppName: application?.name, source: source, result: result.text)
    }

    /// Re-pitch runs with the source equal to the target: one language.
    public init(
        repitch result: TranslationResult, source: UserText, model: String,
        application: SourceApplication?, date: Date
    ) {
        self.init(
            date: date, action: .repitch, sourceLanguage: result.direction.source,
            targetLanguage: nil, profileID: result.audience.id,
            model: model, sourceBundleID: application?.bundleIdentifier,
            sourceAppName: application?.name, source: source, result: result.text)
    }

    public init(
        correction result: CorrectionResult, language: LanguageCode, profileID: String,
        model: String, application: SourceApplication?, date: Date
    ) {
        self.init(
            date: date, action: .correct, sourceLanguage: language,
            targetLanguage: nil, profileID: profileID,
            model: model, sourceBundleID: application?.bundleIdentifier,
            sourceAppName: application?.name, source: result.original, result: result.corrected,
            wordCount: WordCount.of(result.original.value), mistakes: result.errors.map(Mistake.init))
    }

    /// The result is what Copy writes: the summary and the notes. Explained
    /// from the text's language into my language (#81).
    public init(
        explanation result: ExplanationResult, source: UserText, language: LanguageCode,
        explainedIn: LanguageCode, model: String, application: SourceApplication?, date: Date
    ) {
        self.init(
            date: date, action: .explain, sourceLanguage: language,
            targetLanguage: explainedIn, profileID: nil,
            model: model, sourceBundleID: application?.bundleIdentifier,
            sourceAppName: application?.name, source: source,
            result: UserText(result.copyText))
    }
}
