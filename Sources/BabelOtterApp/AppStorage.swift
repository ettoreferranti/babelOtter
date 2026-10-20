import BabelOtterKit
import Foundation

/// Where the app may keep files, decided once (NFR-P7). `config.json` and
/// `history.sqlite` live in the same folder, so they are always checked
/// against the same synced roots.
enum AppStorage {

    static func locator() -> StorageLocator {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // The directories iCloud Drive can sync on this machine.
        return StorageLocator(
            home: home,
            iCloudRoots: ["Library/Mobile Documents", "Documents", "Desktop"]
                .map { home.appending(path: $0) })
    }
}
