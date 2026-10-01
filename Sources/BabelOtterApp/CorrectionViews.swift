import BabelOtterKit
import SwiftUI

/// The diff as flowing text: removals struck through in red, additions in
/// green. Exactly what Replace pastes, with what it takes away.
struct DiffText: View {
    let segments: [DiffSegment]

    var body: some View {
        Text(attributed).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        var previousWasRemoval = false
        for segment in segments {
            // A replacement shows as removal-then-addition with nothing
            // between them ("jetzjetzt"). A thin space, display-only, keeps
            // the two words apart; the pasted text never passes through here.
            if case .added = segment, previousWasRemoval {
                result += AttributedString("\u{2009}")
            }
            if case .removed = segment {
                previousWasRemoval = true
            } else {
                previousWasRemoval = false
            }
            switch segment {
            case .same(let text):
                result += AttributedString(text)
            case .removed(let text):
                var part = AttributedString(text)
                part.strikethroughStyle = .single
                part.foregroundColor = .red
                result += part
            case .added(let text):
                var part = AttributedString(text)
                part.foregroundColor = .green
                part.font = .body.bold()
                result += part
            }
        }
        return result
    }
}

/// One itemised change: category, fragment to fragment, and the rule.
struct CorrectionRow: View {
    let item: CorrectionError
    var dimmed = false
    var onCopy: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(item.category.rawValue)
                    .font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Text("\(item.original) \u{2192} \(item.corrected)").font(.callout)
                Spacer()
                if let onCopy {
                    Button("Copy", systemImage: "doc.on.doc", action: onCopy)
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .help("Copy the suggested wording")
                }
            }
            Text(item.explanationEn).font(.caption).foregroundStyle(.secondary)
        }
        .opacity(dimmed ? 0.6 : 1)
    }
}
