import BabelOtterKit
import SwiftUI

/// The scratchpad (#84): settings on top, source and result side by side,
/// progress and Copy below.
struct ScratchpadView: View {

    @Bindable var model: ScratchpadModel

    var body: some View {
        let policy = model.policy
        VStack(spacing: 0) {
            toolbar(policy).padding(12)
            if let question = model.question {
                questionBar(question).padding(.horizontal, 12).padding(.bottom, 10)
            }
            Divider()
            HSplitView {
                sourcePane.frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                resultPane(policy).frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            statusBar(policy).padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(minWidth: 640, minHeight: 380)
    }

    // MARK: - Toolbar

    private func toolbar(_ policy: ScratchpadPolicy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("Action", selection: $model.action) {
                    ForEach(Action.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()

                if model.action == .translate { directionControls }
                Spacer()
            }
            HStack(spacing: 10) {
                // An explanation is written for the user, not a reader (#65).
                if model.action != .explain { audiencePicker }
                TextField(stylePlaceholder, text: $model.styleNote)
                    .textFieldStyle(.roundedBorder)
                Button(policy.runTitle) { model.run() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!policy.canRun)
            }
        }
    }

    private var directionControls: some View {
        HStack(spacing: 6) {
            if model.usesTargetMenu { intoMenu }
            if let title = model.directionTitle {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Button("Swap", systemImage: "arrow.left.arrow.right") { model.swap() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .help("Translate the other way on the next run")
            }
        }
    }

    private var intoMenu: some View {
        Menu {
            Button("Into: automatic") { model.target = nil }
            ForEach(model.enabledLanguages, id: \.self) { code in
                Button("Into " + model.displayName(code)) { model.target = code }
            }
        } label: {
            Text(intoTitle)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var intoTitle: String {
        guard let target = model.target else { return "Into: automatic" }
        return "Into " + model.displayName(target)
    }

    private var audiencePicker: some View {
        HStack(spacing: 6) {
            Picker("Audience", selection: $model.profileID) {
                Text(model.automaticLabel).tag(String?.none)
                ForEach(model.profiles) { profile in
                    Text(profile.name).tag(String?.some(profile.id))
                }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            if let note = model.audienceNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .help("The audience the last run wrote for")
            }
        }
    }

    private var stylePlaceholder: String {
        switch model.action {
        case .explain: return "Style note, e.g. focus on grammar"
        case .repitch: return "Style note, e.g. shorter, warmer"
        case .translate, .correct: return "Style note, e.g. shorter, more encouraging"
        }
    }

    private func questionBar(_ question: ScratchpadModel.Question) -> some View {
        HStack {
            switch question {
            case .source(let candidates):
                Text("Which language is this?")
                ForEach(candidates, id: \.self) { code in
                    Button(model.displayName(code)) { model.answer(source: code) }
                }
            case .target(_, let candidates):
                Text("Translate into:")
                ForEach(candidates, id: \.self) { code in
                    Button(model.displayName(code)) { model.answer(target: code) }
                }
            }
            Spacer()
        }
    }

    // MARK: - Panes

    private var sourcePane: some View {
        TextEditor(text: $model.source)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .overlay(alignment: .topLeading) {
                if model.source.isEmpty {
                    Text("Type or paste your text here.")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
    }

    private func resultPane(_ policy: ScratchpadPolicy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                result(policy)
                ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .opacity(policy.isOutOfDate ? 0.55 : 1)
    }

    @ViewBuilder private func result(_ policy: ScratchpadPolicy) -> some View {
        if case .finished = policy.status, let correction = model.correction {
            correctionContent(correction)
        } else if case .finished = policy.status, let explanation = model.explanation {
            Text(explanation.summary).textSelection(.enabled)
            if !explanation.notes.isEmpty {
                Divider()
                ForEach(Array(explanation.notes.enumerated()), id: \.offset) { _, note in
                    ExplanationNoteRow(note: note)
                }
            }
        } else if model.resultText.isEmpty {
            Text(placeholder(policy)).foregroundStyle(.tertiary)
        } else {
            Text(model.resultText).textSelection(.enabled)
        }
    }

    private func placeholder(_ policy: ScratchpadPolicy) -> String {
        if policy.isRunning { return "Waiting for the model\u{2026}" }
        return "The result appears here. Press Run (\u{2318}\u{21A9})."
    }

    private func correctionContent(_ correction: CorrectionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DiffText(segments: correction.diff)
            if correction.hasNoErrors {
                Label("No errors found", systemImage: "checkmark.circle").foregroundStyle(.green)
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
    }

    // MARK: - Status bar

    private func statusBar(_ policy: ScratchpadPolicy) -> some View {
        HStack(spacing: 10) {
            if policy.isRunning { ProgressView().controlSize(.small) }
            if let refusal = model.refusal {
                Text(refusal).font(.caption).foregroundStyle(.secondary)
            } else if let problem = policy.problem {
                Text(problem).font(.caption).foregroundStyle(.secondary)
                if model.showsSetupButton {
                    Button("Open Setup") { model.showSetup() }.controlSize(.small)
                }
            } else if let progress = policy.progress {
                Text(progress).font(.caption).foregroundStyle(.secondary)
            }
            if policy.isOutOfDate {
                Text("Out of date")
                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .help("Something changed since this result. Press Run to update it.")
            }
            Spacer()
            if policy.canStop {
                Button("Stop") { model.stop() }.keyboardShortcut(.cancelAction)
            }
            // Not Command-C: copying part of the result must stay possible.
            Button(model.copied ? "\u{2713} Copied" : "Copy") { model.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!policy.canCopy)
        }
    }
}
