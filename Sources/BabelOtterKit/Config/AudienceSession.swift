import Foundation

/// Where the audience shown in the popup came from (#52).
public enum AudienceOrigin: Sendable, Equatable {
    /// Picked in the popup.
    case chosen
    /// The model read it from the text.
    case inferred
    /// Last picked in this application.
    case rememberedForApp
    /// Last picked anywhere.
    case rememberedAnywhere
    /// Nothing remembered: Colleagues.
    case standard
}

/// The audience ids the user picked, per application and overall. Ids only,
/// never text (NFR-P3).
public protocol AudienceMemory: AnyObject {
    func lastChoice(forApp bundleIdentifier: String) -> String?
    func lastChoice() -> String?
    func remember(_ id: String, forApp bundleIdentifier: String?)
}

/// One popup's audience: where it starts, what each run is told, and what
/// picking another one does (#52).
///
/// A value, so the popup's observation sees every change. Translate's first
/// run infers; once a run has reported its audience, or the user has picked
/// one, every later run is fixed, so the label never changes under the user.
public struct AudienceSession {

    public private(set) var audience: AudienceProfile
    public private(set) var origin: AudienceOrigin
    private var settled = false
    /// False once a run has ended without reporting its audience (it
    /// failed), so the note stops saying "detecting..." beside the error.
    private var awaitingReport = true

    private let profiles: [AudienceProfile]
    private let action: Action
    private let application: SourceApplication?
    private let memory: any AudienceMemory

    public init(
        profiles: [AudienceProfile], action: Action, application: SourceApplication?,
        memory: any AudienceMemory
    ) {
        self.profiles = profiles
        self.action = action
        self.application = application
        self.memory = memory
        let start = Self.starting(profiles, application?.bundleIdentifier, memory)
        audience = start.profile
        origin = start.origin
    }

    /// True until Translate's first run reports its audience.
    public var isDetecting: Bool {
        guard action == .translate else { return false }
        return !settled
    }

    /// What the next run is told.
    public var request: AudienceRequest {
        if isDetecting {
            return .infer(profiles: profiles, fallback: audience)
        }
        return .fixed(audience)
    }

    /// The text beside the picker. Nil for an audience the user picked.
    public var note: String? {
        if isDetecting {
            if awaitingReport { return "detecting..." }
        }
        switch origin {
        case .chosen:
            return nil
        case .inferred:
            return "guessed from the text, change if wrong"
        case .rememberedForApp:
            return "last used in " + (application?.name ?? "this app")
        case .rememberedAnywhere:
            return "last used"
        case .standard:
            return "default"
        }
    }

    /// Records the audience a run reported. A guess is shown as one and
    /// never remembered; a fallback keeps its own origin. Ignored once the
    /// user has picked: that report came from a run the pick replaced.
    public mutating func apply(reported profile: AudienceProfile, inferred: Bool) {
        if origin == .chosen { return }
        settled = true
        audience = profile
        if inferred { origin = .inferred }
    }

    /// A run is starting: until it reports, the note says "detecting...".
    public mutating func runStarted() {
        awaitingReport = true
    }

    /// A run ended without reporting its audience. Its fallback's note is
    /// shown; the next run still infers.
    public mutating func runEnded() {
        awaitingReport = false
    }

    /// Picks an audience: remembered for this application and overall.
    /// Returns whether the result must be generated again. Picking the
    /// audience already shown does nothing, except while detecting: the
    /// shown one is then only the fallback, and the guess could replace it.
    @discardableResult
    public mutating func choose(_ id: String) -> Bool {
        guard let profile = Self.find(id, in: profiles) else { return false }
        if profile.id == audience.id {
            if !isDetecting { return false }
        }
        audience = profile
        origin = .chosen
        settled = true
        memory.remember(profile.id, forApp: application?.bundleIdentifier)
        return true
    }

    private static func starting(
        _ profiles: [AudienceProfile], _ bundleIdentifier: String?, _ memory: any AudienceMemory
    ) -> (profile: AudienceProfile, origin: AudienceOrigin) {
        if let bundleIdentifier {
            if let profile = find(memory.lastChoice(forApp: bundleIdentifier), in: profiles) {
                return (profile, .rememberedForApp)
            }
        }
        if let profile = find(memory.lastChoice(), in: profiles) {
            return (profile, .rememberedAnywhere)
        }
        if let profile = find(AudienceProfile.colleagues.id, in: profiles) {
            return (profile, .standard)
        }
        return (profiles.first ?? .colleagues, .standard)
    }

    private static func find(_ id: String?, in profiles: [AudienceProfile]) -> AudienceProfile? {
        guard let id else { return nil }
        for profile in profiles where profile.id == id {
            return profile
        }
        return nil
    }
}
