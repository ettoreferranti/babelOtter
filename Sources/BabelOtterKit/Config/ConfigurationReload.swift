import Foundation

public struct ConfigurationReloadResult: Sendable, Equatable {
    public let configuration: Configuration
    public let problems: [ConfigurationProblem]
}

/// What a load of config.json changes (#26).
///
/// `ConfigurationStore.load()` is all-or-nothing: one wrong value gives the
/// defaults for everything. At launch that is the only option. Mid-session
/// it would throw away a working glossary over a missing comma, so a reload
/// with problems keeps the configuration in use and says so.
public enum ConfigurationReload {

    public static let keptNote = " - still using the previous settings"

    /// `fileExists` because `load()` treats a missing file as a first launch,
    /// which is wrong once babelOtter is running.
    public static func apply(
        previous: Configuration, loaded: LoadedConfiguration, fileExists: Bool, isLaunch: Bool
    ) -> ConfigurationReloadResult {
        if !isLaunch {
            if !fileExists {
                let missing = ConfigurationProblem(
                    file: ConfigurationStore.fileName, field: nil, detail: "the file is missing" + keptNote)
                return ConfigurationReloadResult(configuration: previous, problems: [missing])
            }
        }
        if loaded.problems.isEmpty {
            return ConfigurationReloadResult(configuration: loaded.configuration, problems: [])
        }
        if isLaunch {
            return ConfigurationReloadResult(configuration: loaded.configuration, problems: loaded.problems)
        }
        var kept: [ConfigurationProblem] = []
        for problem in loaded.problems {
            kept += [ConfigurationProblem(
                file: problem.file, field: problem.field, detail: problem.detail + keptNote)]
        }
        return ConfigurationReloadResult(configuration: previous, problems: kept)
    }
}

extension ConfigurationProblem {
    /// "retentionDays: expected Int, found something else", shown after
    /// "config.json: " in the menu.
    public var summary: String {
        if let field {
            return "\(field): \(detail)"
        }
        return detail
    }
}
