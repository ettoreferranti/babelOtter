import BabelOtterKit
import SwiftUI

/// Languages, history retention, the request timeout and the clipboard
/// switch (#61).
struct GeneralSettingsView: View {

    @ObservedObject var model: SettingsModel

    /// What is typed, written when Return is pressed or the field is left.
    @State private var days = ""
    @State private var timeout = ""
    @FocusState private var focused: SettingsField?

    private enum Keeping: Hashable { case days, unlimited, off }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FileProblemBanner(model: model).padding([.horizontal, .top])
            Form {
                Section("Languages") {
                    ForEach(model.configuration.languages, id: \.code) { language in
                        Toggle(language.displayName, isOn: Binding(
                            get: { language.enabled },
                            set: { on in model.edit(.languages) { try $0.setLanguage(language.code, enabled: on) } }))
                    }
                    RefusalText(text: model.refusals[.languages])
                }
                Section("History") {
                    Picker("Keep records", selection: Binding(get: { keeping }, set: setKeeping)) {
                        Text("For a number of days").tag(Keeping.days)
                        Text("Unlimited").tag(Keeping.unlimited)
                        Text("Off - record nothing").tag(Keeping.off)
                    }
                    if keeping == .days {
                        TextField("Days", text: $days)
                            .focused($focused, equals: .retention)
                            .onSubmit(commitDays)
                    }
                    RefusalText(text: model.refusals[.retention])
                }
                Section("Requests") {
                    TextField("Timeout in seconds", text: $timeout)
                        .focused($focused, equals: .timeout)
                        .onSubmit(commitTimeout)
                    RefusalText(text: model.refusals[.timeout])
                }
                Section("Clipboard") {
                    Toggle("Never read the selection through the clipboard", isOn: Binding(
                        get: { model.configuration.strictCaptureOnly },
                        set: { on in model.edit(.clipboard) { $0.setStrictCaptureOnly(on) } }))
                    Text("Then apps that only offer the selection through Copy (Teams, Word, VS Code) can't be used.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Language detection's tuning values stay in config.json.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .disabled(model.isReadOnly)
        }
        .onAppear(perform: resetDrafts)
        .onChange(of: model.configuration) { resetDrafts() }
        .onChange(of: focused) { old, _ in
            if old == .retention { commitDays() }
            if old == .timeout { commitTimeout() }
        }
    }

    private var keeping: Keeping {
        switch model.configuration.retentionDays {
        case .days: return .days
        case .unlimited: return .unlimited
        case .off: return .off
        }
    }

    private func setKeeping(_ wanted: Keeping) {
        let retention: HistoryRetention
        switch wanted {
        case .days: retention = .default
        case .unlimited: retention = .unlimited
        case .off: retention = .off
        }
        if wanted == keeping { return }
        model.edit(.retention) { try $0.setRetention(retention) }
    }

    private func commitDays() {
        guard let value = Int(days.trimmingCharacters(in: .whitespaces)) else {
            model.refuse(.retention, "Enter a whole number of days.")
            return
        }
        if case .days(value) = model.configuration.retentionDays { return }
        model.edit(.retention) { try $0.setRetention(.days(value)) }
    }

    private func commitTimeout() {
        guard let value = Double(timeout.trimmingCharacters(in: .whitespaces)) else {
            model.refuse(.timeout, "Enter a number of seconds.")
            return
        }
        if value == model.configuration.timeoutSeconds { return }
        model.edit(.timeout) { try $0.setTimeout(seconds: value) }
    }

    private func resetDrafts() {
        if case .days(let value) = model.configuration.retentionDays { days = String(value) }
        timeout = model.configuration.timeoutSeconds.formatted(.number.grouping(.never))
    }
}
