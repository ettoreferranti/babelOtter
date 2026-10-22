import BabelOtterKit
import SwiftUI

struct PopupView: View {

    @Bindable var model: PopupModel
    @FocusState private var instructionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if model.showsControls {
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
            if let mascot = Mascot.image {
                Image(nsImage: mascot).resizable().scaledToFit().frame(height: 22)
            } else {
                Text(Mascot.fallback).font(.headline)
            }
            Text(model.headerTitle).font(.headline)
            Spacer()
            if model.action == .translate, let direction = model.direction {
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
            // An explanation is written for the user, not a reader (#65).
            if model.action != .explain {
                Picker("Audience", selection: Binding(
                    get: { model.profileID },
                    set: { model.selectProfile($0) }
                )) {
                    ForEach(model.profiles) { profile in
                        Text(profile.label(in: model.writingLanguage)).tag(profile.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()

                if let note = model.audienceNote {
                    Text(model.audienceInferred ? "\u{2726} \(note)" : note)
                        .foregroundStyle(.secondary)
                        .help("Where this audience came from")
                }
            }

            TextField(stylePlaceholder, text: $model.instruction)
                .textFieldStyle(.roundedBorder)
                .focused($instructionFocused)
                .onSubmit { model.regenerate() }

            Button("Regenerate", systemImage: "arrow.clockwise") { model.regenerate() }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .help(regenerateHelp)
        }
        .font(.caption)
    }

    private var stylePlaceholder: String {
        switch model.action {
        case .explain: return "Style note, e.g. focus on grammar"
        case .repitch: return "Style note, e.g. shorter, warmer"
        case .translate, .correct: return "Style note, e.g. shorter, more encouraging"
        }
    }

    private var regenerateHelp: String {
        switch model.action {
        case .explain: return "Explain again with this instruction"
        case .repitch: return "Re-pitch again with this audience and instruction"
        case .translate, .correct: return "Translate again with this audience and instruction"
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .capturing:
            ProgressView("Reading the selection...").controlSize(.small)
        case .choosingDirection(let candidates):
            Text(model.action == .repitch ? "Which language is this?" : "Translate into:")
            HStack {
                ForEach(candidates, id: \.self) { code in
                    Button(model.displayName(code)) { model.choose(target: code) }
                }
            }
        case .choosingAudience:
            Text("Pick the audience to re-pitch for, then press Re-pitch.")
                .font(.caption).foregroundStyle(.secondary)
        case .translating:
            plainText
            ProgressView().controlSize(.small)
        case .finished:
            if let correction = model.correction {
                correctionContent(correction)
            } else if let explanation = model.explanation {
                ExplanationContent(explanation: explanation)
            } else {
                plainText
            }
        case .failed(let reason):
            Text(reason).foregroundStyle(.secondary)
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
        if model.phase == .choosingAudience {
            HStack {
                Button("Re-pitch") { model.startRepitch() }
                    .keyboardShortcut(instructionFocused ? nil : .defaultAction)
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
            // Explain has nothing to paste (#65): no button, so Return can
            // never paste an explanation over the user's text.
            if model.action != .explain {
                Button("Replace") { model.replace() }
                    .keyboardShortcut(instructionFocused ? nil : .defaultAction)
                    .disabled(!model.canReplace)
            }
            // Not Command-C: the result text is selectable, and a user
            // copying part of it with Command-C must not have that hijacked
            // into copying (and dismissing over) the whole translation.
            Button(model.copied ? "\u{2713} Copied" : "Copy") { model.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.canCopy && !model.copied)
            Spacer()
            Button("Dismiss") { model.dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }
}
