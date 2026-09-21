import AppKit
import BabelOtterKit
import Foundation

/// `NSPasteboard`, behind the kit's narrow protocol.
///
/// The orchestration that matters -- save, capture, restore on every path --
/// is pure and lives in `BabelOtterKit`. This is the part that cannot be, and
/// is kept correspondingly small.
struct SystemPasteboard: PasteboardAccess {

    private var pasteboard: NSPasteboard { .general }

    var changeCount: Int { pasteboard.changeCount }

    /// Every type of every item.
    ///
    /// A string-shaped save would hand the user back a plain-text version of
    /// whatever they had copied -- losing the styled text, the image, the file
    /// reference. `NFR-P10` makes the restore a privacy mechanism, and a
    /// restore that quietly degrades what it restores is not one.
    func snapshot() -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var stored: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { stored[type.rawValue] = data }
            }
            return stored
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { stored -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in stored {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    /// `concealed` marks the item `org.nspasteboard.ConcealedType` and
    /// `com.apple.is-sensitive`.
    ///
    /// Measured 2026-09-20 across two Macs: these do **not** stop Universal
    /// Clipboard -- a concealed item pasted verbatim on the other machine.
    /// They are set anyway, because clipboard managers honour them and keeping
    /// the user's text out of a clipboard history application is worth
    /// something on its own. What bounds the Universal Clipboard exposure is
    /// dwell time, not concealment.
    func write(_ string: String, concealed: Bool) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        if concealed {
            item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            item.setString("", forType: NSPasteboard.PasteboardType("com.apple.is-sensitive"))
        }
        pasteboard.writeObjects([item])
    }

    /// Polls `changeCount`, which is the only signal that a copy worked.
    func awaitChange(from previous: Int, timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != previous { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }
}
