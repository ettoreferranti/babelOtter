import Foundation

/// How a selection was read, in the order the ladder tries them.
///
/// Three tiers, not two -- measured against real applications, not assumed.
/// WebKit surfaces return `noValue` for `kAXSelectedTextAttribute` and expose
/// the selection only through text markers, so treating Safari and Mail as
/// clipboard-only would be both less private and less reliable than necessary.
/// See `docs/architecture.md` section 7.
public enum CaptureTier: Sendable, Equatable, CaseIterable {
    /// `kAXSelectedTextAttribute`. Native AppKit text.
    case accessibilityText
    /// WebKit's `AXSelectedTextMarkerRange` plus `AXStringForTextMarkerRange`.
    case textMarkerRange
    /// Synthetic Command-C. The only path for Electron, and the only one that
    /// puts user content on the pasteboard.
    case clipboard

    /// Whether this tier exposes the text to Universal Clipboard (`NFR-P9`).
    public var usesPasteboard: Bool { self == .clipboard }
}

/// Something that can be asked for the current selection one tier at a time.
///
/// A protocol so the ladder below is pure and every ordering case is a CI test
/// against a fake. The real implementation talks to `AXUIElement` and cannot
/// run in CI at all.
public protocol SelectionSource: Sendable {
    func read(tier: CaptureTier) -> String?
}

/// Tries tiers in order and takes the first that produces real text.
///
/// **A tier is accepted only if it returns something non-empty.** Never ask an
/// application what it supports. VS Code advertises `AXSelectedText`,
/// `AXSelectedTextRange`, `AXSelectedTextRanges` *and*
/// `AXSelectedTextMarkerRange`, and returns empty from all of them -- probing
/// attribute names classifies it as tier 1 when it is tier 3. That was the
/// single most misleading result spike #30 produced, and this rule is the whole
/// of what it taught.
public struct TierLadder: Sendable {

    public init() {}

    /// The first tier that yields non-empty text, or `nil` if none does.
    ///
    /// Whitespace-only counts as empty. A selection of three spaces is not
    /// something to send to a model, and a tier that returns it has not
    /// succeeded (`FR-CAP-06`).
    public func capture(
        from source: any SelectionSource,
        allowing tiers: [CaptureTier] = CaptureTier.allCases
    ) -> (text: String, tier: CaptureTier)? {
        for tier in tiers {
            guard let text = source.read(tier: tier) else { continue }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            return (text: text, tier: tier)
        }
        return nil
    }
}
