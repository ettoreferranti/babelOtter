import Foundation

/// How ready babelOtter is, at the granularity the menu bar shows (`FR-UI-03`).
///
/// Declared in increasing severity: the synthesised `Comparable` follows
/// declaration order, so the worst of several readinesses is their `max`.
public enum Readiness: Sendable, Equatable, Comparable, CaseIterable {
    case ready
    case degraded
    case blocked
}
