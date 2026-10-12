import Foundation

/// Calls `onChange` when config.json's content changes on disk (#26).
///
/// Two sources, because editors save two ways: writing a new file and
/// renaming it over the old one changes the folder (TextEdit and most
/// macOS editors); writing into the existing file changes only the file
/// (VS Code). The file source is re-armed after every settled change,
/// because a rename-over save leaves it watching the old, unlinked file.
@MainActor
final class ConfigurationWatcher {

    var onChange: (@MainActor () -> Void)?

    private let directory: URL
    private let file: URL
    private var directorySource: (any DispatchSourceFileSystemObject)?
    private var fileSource: (any DispatchSourceFileSystemObject)?
    private var pending: Task<Void, Never>?
    /// Seeded at creation, so babelOtter's own first-launch save is not a
    /// change.
    private var lastContents: Data?

    /// An editor's save is several events in a burst; this waits them out.
    private static let settle = Duration.milliseconds(300)

    init(directory: URL, file: URL) {
        self.directory = directory
        self.file = file
        lastContents = FileManager.default.contents(atPath: file.path(percentEncoded: false))
    }

    /// False when the folder cannot be watched: changes then need a restart.
    func start() -> Bool {
        guard let source = makeSource(directory, events: .write) else { return false }
        directorySource = source
        armFile()
        return true
    }

    private func armFile() {
        fileSource?.cancel()
        fileSource = makeSource(file, events: [.write, .extend, .delete, .rename])
    }

    private func makeSource(
        _ url: URL, events: DispatchSource.FileSystemEvent
    ) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func changed() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled else { return }
            self?.settled()
        }
    }

    private func settled() {
        armFile()
        let contents = FileManager.default.contents(atPath: file.path(percentEncoded: false))
        guard contents != lastContents else { return }
        lastContents = contents
        onChange?()
    }
}
