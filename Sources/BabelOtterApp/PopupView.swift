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
            // Correct renders its own warnings inside `correctionContent`,
            // above the lists they qualify (design spec section 4). Only
            // Translate's finished text -- where `model.correction` is
            // always nil -- reaches this one.
            if model.correction == nil {
                ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
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
            Text(headerTitle).font(.headline)
            Spacer()
            if model.action != .correct, let direction = model.direction {
                Text("\(model.displayName(direction.source)) \u{2192} \(model.displayName(direction.target))")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Swap", systemImage: "arrow.left.arrow.right") { model.swap() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .disabled(model.phase == .capturing)
            }
        }
    }

    private var headerTitle: String {
        if model.action == .correct { return "\u{1F9A6} Correct" }
        return "\u{1F9A6} babelOtter"
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
        case .translating:
            plainText
            ProgressView().controlSize(.small)
        case .finished:
            if let correction = model.correction {
                correctionContent(correction)
            } else {
                plainText
            }
        case .failed(let reason):
            Text(reason).foregroundStyle(.secondary)
        case .needsAccessibility:
            Text("babelOtter needs Accessibility permission to read your selection.")
            Text("Turn it on for babelOtter in System Settings, then try again.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var plainText: some View {
        ScrollView {
            Text(model.text.isEmpty ? " " : model.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 40, maxHeight: 320)
    }

    /// The diff, the errors and the (unapplied) suggestions, for a finished
    /// Correct. `correction.corrected` -- what Replace pastes -- is exactly
    /// `same` plus `added` from `correction.diff`.
    private func correctionContent(_ correction: CorrectionResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                DiffText(segments: correction.diff)
                ForEach(Array(correction.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if correction.hasNoErrors {
                    Label("No errors found", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                if !correction.errors.isEmpty {
                    Text("Errors").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(correction.errors.enumerated()), id: \.offset) { _, item in
                        CorrectionRow(item: item)
                    }
                }
                if !correction.suggestions.isEmpty {
                    Text("Suggestions (not applied)").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(correction.suggestions.enumerated()), id: \.offset) { _, item in
                        CorrectionRow(item: item, dimmed: true) {
                            SystemPasteboard().write(item.corrected, concealed: false)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 420)
    }

    @ViewBuilder private var actions: some View {
        if model.phase == .needsAccessibility {
            HStack {
                Button("Open System Settings") { model.openAccessibilitySettings() }
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Dismiss") { model.dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        } else {
            resultActions
        }
    }

    private var resultActions: some View {
        HStack {
            // While the instruction field has focus, Return means
            // Regenerate. A default button would otherwise take Return
            // first and paste into the user's document mid-edit.
            Button("Replace") { model.replace() }
                .keyboardShortcut(instructionFocused ? nil : .defaultAction)
                .disabled(!model.canReplace)
            // Not Command-C: the result text is selectable, and a user
            // copying part of it with Command-C must not have that hijacked
            // into copying (and dismissing over) the whole translation.
            Button("Copy") { model.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.canReplace)
            Spacer()
            Button("Dismiss") { model.dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }
}
