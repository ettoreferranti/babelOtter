import AppKit

/// Swen, the picture in the menu bar and the popup header.
///
/// `Tools/make-app.sh` copies it into the bundle's Resources, so it is nil
/// under `swift run`; callers then fall back to the otter emoji.
@MainActor
enum Mascot {

    static let image = NSImage(named: "Mascot")

    static let fallback = "\u{1F9A6}"

    /// The picture as text, so the readiness symbol can stay the button's
    /// template image beside it.
    static func menuBarTitle() -> NSAttributedString {
        guard let image else { return NSAttributedString(string: fallback) }
        let attachment = NSTextAttachment()
        attachment.image = image
        let height: CGFloat = 18
        let width = height * image.size.width / image.size.height
        attachment.bounds = CGRect(x: 0, y: -5, width: width, height: height)
        return NSAttributedString(attachment: attachment)
    }
}
