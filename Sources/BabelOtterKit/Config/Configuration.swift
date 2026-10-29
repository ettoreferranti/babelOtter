import Foundation

/// The four things babelOtter can do to a selection.
///
/// Lives in the configuration layer rather than the LLM layer because
/// configuration is what enumerates it: `FR-CFG-02` keys a model per action, and
/// `FR-UI-01` keys a hotkey per action.
public enum Action: String, Sendable, Codable, CaseIterable {
    case translate
    case correct
    case explain
    case repitch

    /// The name the menu and the readiness causes show.
    public var displayName: String {
        switch self {
        case .translate: return "Translate"
        case .correct: return "Correct"
        case .explain: return "Explain"
        case .repitch: return "Re-pitch"
        }
    }
}

/// Everything the user can configure, as one value (spec section 6).
///
/// `FR-CFG-03` stores this as a human-readable file, which shapes the type: no
/// UUIDs, no opaque blobs, and every field a person could reasonably want to
/// change by hand is a named scalar rather than something derived.
public struct Configuration: Sendable, Equatable, Codable {

    public var languages: [LanguageConfig]
    public var profiles: [AudienceProfile]
    public var glossary: Glossary
    /// Terms masked to sentinels before generation and restored verbatim after
    /// (`FR-GLO-02`). See ``TokenProtector``.
    public var doNotTranslate: [String]
    /// A model per action (`FR-CFG-02`).
    public var models: [Action: String]
    public var timeoutSeconds: Double
    /// How long history keeps records, or "off" (#69).
    public var retentionDays: HistoryRetention
    /// Below this, detection is ambiguous and the user is asked rather than
    /// guessed at (`FR-TRN-03`).
    public var detectionConfidenceFloor: Double
    /// Selections shorter than this are never guessed at (`FR-TRN-03`).
    /// Measured in non-whitespace characters -- see ``LanguageDetector``.
    public var minimumLengthForDetection: Int
    /// Refuse the clipboard for *reading* (#77). Replacement still uses it.
    /// Off by default: turning it on means no capture at all in Teams, Word,
    /// OneNote or VS Code, which is a product decision rather than a detail.
    public var strictCaptureOnly: Bool
    /// Optional so a file written before #26 still loads: nil means each
    /// action's default.
    public var hotkeys: HotKeyBindings?
    /// The language the user reads best (#81): Correct's notes and Explain's
    /// text are written in it, and Correct judges false friends against it.
    /// Optional so an older file loads unchanged: nil means English. Use
    /// `mine`.
    public var myLanguage: LanguageCode?
    /// Which Ollama to talk to (#126). Optional so a file from before #126
    /// loads unchanged, as the user's own Ollama: everyone running lingoSwen
    /// then keeps what they have. Use `server`.
    public var modelServer: ModelServer?

    public init(
        languages: [LanguageConfig],
        profiles: [AudienceProfile],
        glossary: Glossary,
        doNotTranslate: [String],
        models: [Action: String],
        timeoutSeconds: Double,
        retentionDays: HistoryRetention,
        detectionConfidenceFloor: Double,
        minimumLengthForDetection: Int,
        strictCaptureOnly: Bool = false,
        hotkeys: HotKeyBindings? = nil,
        myLanguage: LanguageCode? = nil,
        modelServer: ModelServer? = nil
    ) {
        self.languages = languages
        self.profiles = profiles
        self.glossary = glossary
        self.doNotTranslate = doNotTranslate
        self.models = models
        self.timeoutSeconds = timeoutSeconds
        self.retentionDays = retentionDays
        self.detectionConfidenceFloor = detectionConfidenceFloor
        self.minimumLengthForDetection = minimumLengthForDetection
        self.strictCaptureOnly = strictCaptureOnly
        self.hotkeys = hotkeys
        self.myLanguage = myLanguage
        self.modelServer = modelServer
    }

    /// The model server in use: the one named, else the user's own Ollama.
    public var server: ModelServer {
        modelServer ?? .own
    }

    /// Where every request goes.
    public var endpoint: OllamaEndpoint {
        server.endpoint
    }

    public var enabledLanguages: [LanguageConfig] {
        languages.filter(\.enabled)
    }

    public func language(for code: LanguageCode) -> LanguageConfig? {
        languages.first { $0.code == code }
    }

    public func profile(id: String) -> AudienceProfile? {
        profiles.first { $0.id == id }
    }

    /// My language's code (#81). Named in the file: the configured language
    /// with that code, else with that base code (`de` finds `de-ch`). Not
    /// named: English while it is on, else the first enabled language, so a
    /// file from before #81 with English off keeps working.
    public var myLanguageCode: LanguageCode {
        guard let myLanguage else {
            let english = LanguageConfig.english.code
            if enabledLanguages.contains(where: { $0.code == english }) { return english }
            return enabledLanguages.first?.code ?? english
        }
        if languages.contains(where: { $0.code == myLanguage }) { return myLanguage }
        let sameBase = languages.first { $0.code.baseSubtag == myLanguage.baseSubtag }
        return sameBase?.code ?? myLanguage
    }

    /// My language as configured; English as shipped when it is not
    /// configured, which `myLanguageProblem` reports.
    public var mine: LanguageConfig {
        language(for: myLanguageCode) ?? .english
    }

    /// Why `myLanguage` cannot be used, worded for "config.json: myLanguage
    /// ..."; nil when it is an enabled language, or not named at all.
    public var myLanguageProblem: String? {
        guard myLanguage != nil else { return nil }
        guard let language = language(for: myLanguageCode) else {
            return "\(myLanguageCode.rawValue) is not a configured language"
        }
        guard language.enabled else {
            return "\(language.displayName) is switched off"
        }
        return nil
    }

    /// This configuration with every shipped language it lacks appended,
    /// switched off, so an existing file gains French, Italian (#81) and
    /// Spanish (#132) as toggles; nil when none is missing, so the caller
    /// knows not to write.
    /// A language counts as present when any configured language shares its
    /// base subtag: a user's own `fr-CH` keeps `fr` out.
    public func addingMissingShippedLanguages() -> Configuration? {
        var added = self
        for shipped in LanguageConfig.shippedDefaults {
            if !hasLanguage(sharingBaseWith: shipped.code) {
                var language = shipped
                language.enabled = false
                added.languages.append(language)
            }
        }
        if added.languages.count == languages.count { return nil }
        return added
    }

    /// A loop, not `contains` with a closure: muter reports mutants inside
    /// closures as survivors.
    private func hasLanguage(sharingBaseWith code: LanguageCode) -> Bool {
        for language in languages where language.code.baseSubtag == code.baseSubtag {
            return true
        }
        return false
    }
}

extension Configuration {

    /// The model a fresh install points every action at.
    ///
    /// A starting point, not a settled answer: `FR-ONB-01` walks the user
    /// through choosing one, and `FR-EVL-01`'s harness exists to decide which is
    /// actually good. Named here so the first run has something to try.
    ///
    /// Mistral Small 3.2 rather than a small Llama, for three reasons that
    /// matter to this pipeline specifically:
    ///
    /// - It is trained with real European-language coverage, which is the whole
    ///   job here. A 24B model also has room for German case and word order
    ///   that an 8B one spends on English.
    /// - Apache 2.0, so nothing about it blocks signing and distribution
    ///   (issue #82). Several strong multilingual models -- Command R, Aya --
    ///   are non-commercial licences, which would.
    /// - The 3.2 release specifically improved instruction-following and
    ///   repetition. That is not incidental: this pipeline demands one JSON
    ///   object in a fixed shape, an exact block count, and DNT sentinels
    ///   copied through untouched. Format adherence is where a local model
    ///   actually fails us, more often than translation quality is.
    ///
    /// 15GB at the default Q4_K_M quantisation, 128K context.
    public static let defaultModel = "mistral-small3.2:24b"

    public static let `default` = Configuration(
        languages: LanguageConfig.shippedDefaults,
        profiles: AudienceProfile.shippedDefaults,
        glossary: Glossary(),
        doNotTranslate: [],
        models: Dictionary(uniqueKeysWithValues: Action.allCases.map { ($0, defaultModel) }),
        timeoutSeconds: 60,
        retentionDays: .default,
        detectionConfidenceFloor: 0.65,
        minimumLengthForDetection: 12,
        strictCaptureOnly: false,
        hotkeys: HotKeyBindings.defaults,
        modelServer: .builtIn
    )
}

extension Configuration {

    /// The model `action` runs on: the configured one, else the default.
    /// The pipelines and history both ask here, so a recorded model is by
    /// construction the one that produced the result (#67).
    public func model(for action: Action) -> String {
        models[action] ?? Configuration.defaultModel
    }
}
