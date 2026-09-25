import BabelOtterKit
import SwiftUI

struct PopupView: View {

    @Bindable var model: PopupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            ForEach(model.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            actions
        }
        .padding(14)
        .frame(width: 440)
    }

    private var header: some View {
        HStack {
            Text("\u{1F9A6} babelOtter").font(.headline)
            Spacer()
            if let direction = model.direction {
                Text("\(model.displayName(direction.source)) \u{2192} \(model.displayName(direction.target))")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Swap", systemImage: "arrow.left.arrow.right") { model.swap() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .disabled(model.phase == .capturing)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .capturing:
            ProgressView("Reading the selection...").controlSize(.small)
        case .choosingDirection(let candidates):
            Text("Translate into:")
            HStack {
                ForEach(candidates, id: \.self) { code in
                    Button(model.displayName(code)) { model.choose(target: code) }
                }
            }
        case .translating, .finished:
            ScrollView {
                Text(model.text.isEmpty ? " " : model.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 40, maxHeight: 320)
            if model.phase == .translating {
                ProgressView().controlSize(.small)
            }
        case .failed(let reason):
            Text(reason).foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            Button("Copy") { model.copy() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(model.phase != .finished)
            Spacer()
            Button("Dismiss") { model.dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }
}
