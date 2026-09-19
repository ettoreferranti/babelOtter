import Foundation

/// Something wrong with the configuration file, named precisely enough to fix.
///
/// `FR-CFG-03` requires that a malformed file names the file *and the field*.
/// "Configuration could not be loaded" sends the user hunting through a file
/// they may have hand-edited minutes ago; "retentionDays: expected Int, found
/// String" sends them to the line.
public struct ConfigurationProblem: Sendable, Equatable {
    public let file: String
    public let field: String?
    public let detail: String
}

/// The result of a load that cannot fail.
public struct LoadedConfiguration: Sendable, Equatable {
    public let configuration: Configuration
    public let problems: [ConfigurationProblem]
}

extension JSONEncoder {
    /// Pretty-printed with sorted keys, because `FR-CFG-03` invites hand-editing
    /// and version control. Unsorted keys make every save a scrambled diff.
    static var configuration: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// Reads and writes the one configuration file.
///
/// ``load()`` deliberately **cannot throw**. A configuration file is the thing
/// most likely to be broken by the hand-editing this project encourages, and an
/// app that refuses to start because of it is worse than one that starts with
/// defaults and says what it could not read.
public struct ConfigurationStore: Sendable {

    public static let fileName = "config.json"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var fileURL: URL {
        directory.appending(path: Self.fileName)
    }

    /// The production factory: `~/Library/Application Support/ch.babelotter`,
    /// refused outright if that path is inside a synced tree (NFR-P7).
    public static func inApplicationSupport(locator: StorageLocator) throws -> ConfigurationStore {
        let directory = locator.applicationSupportDirectory()
        try locator.prepare(directory)
        return ConfigurationStore(directory: directory)
    }

    /// Defaults plus a list of what could not be read. Never throws, never traps.
    public func load() -> LoadedConfiguration {
        // Read by path rather than through Data's URL-taking initialiser. That
        // initialiser accepts any URL, including an http one, which is why
        // NFR-P4's guard refuses it outside the single reviewed networking call
        // site. Reading a path has no such reach, so the stricter API is also
        // the correct one here.
        //
        // The guard matches on spelling alone and does not exempt comments,
        // which is why this note describes the initialiser instead of naming
        // it. That is the conservative direction on purpose: a scanner that
        // parsed context is a scanner a real call site could hide behind.
        guard let data = FileManager.default.contents(atPath: fileURL.path(percentEncoded: false))
        else {
            // No file is not a problem: it is what a first launch looks like.
            return LoadedConfiguration(configuration: .default, problems: [])
        }
        do {
            let configuration = try JSONDecoder().decode(Configuration.self, from: data)
            return LoadedConfiguration(configuration: configuration, problems: [])
        } catch let error as DecodingError {
            return LoadedConfiguration(
                configuration: .default,
                problems: [Self.problem(from: error)]
            )
        } catch {
            return LoadedConfiguration(
                configuration: .default,
                problems: [
                    ConfigurationProblem(
                        file: Self.fileName, field: nil, detail: error.localizedDescription)
                ]
            )
        }
    }

    public func save(_ configuration: Configuration) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        try JSONEncoder.configuration.encode(configuration).write(to: fileURL, options: .atomic)
    }

    /// Turns a `DecodingError` into the field name the user has to go and fix.
    ///
    /// The `codingPath` is the only place that name exists, and it is empty for
    /// syntax errors — which is the honest answer there, since a file that is
    /// not JSON at all has no field to blame.
    private static func problem(from error: DecodingError) -> ConfigurationProblem {
        switch error {
        case .typeMismatch(let type, let context):
            return ConfigurationProblem(
                file: fileName,
                field: fieldName(context.codingPath),
                detail: "expected \(type), found something else"
            )
        case .valueNotFound(let type, let context):
            return ConfigurationProblem(
                file: fileName,
                field: fieldName(context.codingPath),
                detail: "expected \(type), found null"
            )
        case .keyNotFound(let key, let context):
            return ConfigurationProblem(
                file: fileName,
                field: fieldName(context.codingPath + [key]),
                detail: "required field is missing"
            )
        case .dataCorrupted(let context):
            return ConfigurationProblem(
                file: fileName,
                field: fieldName(context.codingPath),
                detail: context.debugDescription
            )
        @unknown default:
            return ConfigurationProblem(
                file: fileName, field: nil, detail: "could not be read")
        }
    }

    /// Dotted path, or `nil` when the error is about the file rather than a field.
    private static func fieldName(_ path: [any CodingKey]) -> String? {
        guard !path.isEmpty else { return nil }
        return path.map(\.stringValue).joined(separator: ".")
    }
}
