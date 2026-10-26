import Foundation

/// Whether the built-in model's download may start (#126).
public enum DiskSpacePolicy {

    /// The download is about 15 GB; the rest is room for Ollama to unpack
    /// and for the Mac to keep working.
    public static let requiredBytes: Int64 = 20_000_000_000

    /// Nil when there is room; otherwise what to tell the user.
    public static func refusal(availableBytes: Int64) -> String? {
        if availableBytes >= requiredBytes { return nil }
        return "\(BuiltInServer.modelDisplayName) needs about \(gigabytes(requiredBytes)) free, "
            + "and this Mac has \(gigabytes(availableBytes)). Free some space, then try again."
    }

    /// Decimal gigabytes, as Finder counts them, cut (not rounded) to one
    /// place, so a refusal never says the Mac has as much as it needs.
    public static func gigabytes(_ bytes: Int64) -> String {
        let tenths = max(bytes, 0) / 100_000_000
        return "\(tenths / 10).\(tenths % 10) GB"
    }
}
