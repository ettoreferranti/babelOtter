import BabelOtterKit
import SwiftUI

struct PopupView: View {

    @Bindable var model: PopupModel
    @FocusState private var instructionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if model.canRegenerate {
                controls
            }
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

    /// Audience and a one-off instruction. Both re-run the translation.
    private var controls: some View {
        HStack(spacing: 8) {
            Picker("Audience", selection: Binding(
                get: { model.profileID },
                set: { model.selectProfile($0) }
            )) {
                ForEach(model.profiles) { profile in
                    Text("\(profile.name) (\(profile.register.rawValue))").tag(profile.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            TextField("Instruction, e.g. shorter", text: $model.instruction)
                .textFieldStyle(.roundedBorder)
                .focused($instructionFocused)
                .onSubmit { model.regenerate() }

            Button("Regenerate", systemImage: "arrow.clockwise") { model.regenerate() }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .help("Translate again with this audience and instruction")
        }
        .font(.caption)
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
            // While the instruction field has focus, Return means
            // Regenerate. A default button would otherwise take Return
            // first and paste into the user's document mid-edit.
            Button("Replace") { model.replace() }
                .keyboardShortcut(instructionFocused ? nil : .defaultAction)
                .disabled(model.phase != .finished)
            // Not Command-C: the result text is selectable, and a user
            // copying part of it with Command-C must not have that hijacked
            // into copying (and dismissing over) the whole translation.
            Button("Copy") { model.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.phase != .finished)
            Spacer()
            Button("Dismiss") { model.dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }
}
