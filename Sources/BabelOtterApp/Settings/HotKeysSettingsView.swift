import AppKit
import BabelOtterKit
import SwiftUI

/// A shortcut recorder per action (#61).
struct HotKeysSettingsView: View {

    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FileProblemBanner(model: model).padding([.horizontal, .top])
            Form {
                Section {
                    ForEach(HotKeyPlan.actions, id: \.self) { action in
                        row(action)
                    }
                } footer: {
                    Text("Click a shortcut and press the new one. Escape cancels.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(model.isReadOnly)
        }
    }

    private func row(_ action: Action) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action.displayName).frame(width: 90, alignment: .leading)
                HotKeyRecorder(
                    title: title(action),
                    isEnabled: !model.isReadOnly,
                    onStart: model.suspendHotKeys,
                    onStop: model.resumeHotKeys,
                    onRecord: { keyCode, modifiers in record(keyCode, modifiers, for: action) })
                    .frame(width: 200, height: 24)
                Button("Clear") {
                    model.edit(.hotKey(action)) { try $0.setHotKey(.off, for: action, layout: model.layout()) }
                }
                Button("Default") {
                    guard let text = HotKeyBindings.defaultText(for: action) else { return }
                    model.edit(.hotKey(action)) {
                        try $0.setHotKey(.text(text), for: action, layout: model.layout())
                    }
                }
            }
            RefusalText(text: model.refusals[.hotKey(action)])
        }
    }

    private func record(_ keyCode: UInt32, _ modifiers: UInt32, for action: Action) {
        let layout = model.layout()
        guard let text = HotKeyText.text(keyCode: keyCode, modifiers: modifiers, layout: layout) else {
            model.refuse(.hotKey(action), "lingoSwen can't use this key as a hotkey.")
            return
        }
        model.edit(.hotKey(action)) { try $0.setHotKey(.text(text), for: action, layout: layout) }
    }

    /// "Control-Option-T", or "None" for a menu-only action.
    private func title(_ action: Action) -> String {
        let binding = model.configuration.hotkeys?.binding(for: action) ?? .useDefault
        let text: String?
        switch binding {
        case .off: text = nil
        case .useDefault: text = HotKeyBindings.defaultText(for: action)
        case .text(let written): text = written
        }
        guard let text else { return "None" }
        guard case .success(let spec) = HotKeySpec.parse(text) else { return text }
        guard case .success(let combination) = model.layout().resolve(spec) else { return text }
        return combination.displayName
    }
}

/// The recorder as SwiftUI sees it.
struct HotKeyRecorder: NSViewRepresentable {
    let title: String
    let isEnabled: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onRecord: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> HotKeyRecorderView {
        HotKeyRecorderView()
    }

    func updateNSView(_ view: HotKeyRecorderView, context: Context) {
        view.title = title
        view.isEnabled = isEnabled
        view.onStart = onStart
        view.onStop = onStop
        view.onRecord = onRecord
    }
}

/// Click to listen; the next key with its modifiers is the shortcut.
/// Listening ends with that key, Escape, a click elsewhere, or the window
/// losing focus -- and with it the suspension of lingoSwen's hotkeys.
@MainActor
final class HotKeyRecorderView: NSView, KeyRecording {

    var title = "" { didSet { refresh() } }
    /// SwiftUI's disabled state does not reach an AppKit view.
    var isEnabled = true { didSet { refresh() } }
    var onStart: () -> Void = {}
    var onStop: () -> Void = {}
    var onRecord: (UInt32, UInt32) -> Void = { _, _ in }
    private(set) var isRecording = false

    private let label = NSTextField(labelWithString: "")
    private var resignObserver: (any NSObjectProtocol)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
        setAccessibilityRole(.button)
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if !isEnabled { return }
        if isRecording { return }
        if window.makeFirstResponder(self) {
            isRecording = true
            refresh()
            onStart()
        }
    }

    override func resignFirstResponder() -> Bool {
        stop()
        return true
    }

    override func keyDown(with event: NSEvent) {
        if isRecording { record(event) } else { super.keyDown(with: event) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let window else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    /// Every key while listening, Command ones included (`AppWindow`).
    func record(_ event: NSEvent) {
        let modifiers = Self.carbonModifiers(event.modifierFlags)
        // Escape alone cancels; with a modifier it is a shortcut like any other.
        if event.keyCode == 0x35 {
            if modifiers == 0 {
                cancel()
                return
            }
        }
        let keyCode = UInt32(event.keyCode)
        cancel()
        onRecord(keyCode, modifiers)
    }

    func cancel() {
        stop()
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        refresh()
        onStop()
    }

    private func refresh() {
        label.stringValue = isRecording ? "Type the shortcut\u{2026}" : title
        label.textColor = isRecording || !isEnabled ? .secondaryLabelColor : .labelColor
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        setAccessibilityLabel(label.stringValue)
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var bits: UInt32 = 0
        if flags.contains(.command) { bits |= HotKeySpec.command }
        if flags.contains(.shift) { bits |= HotKeySpec.shift }
        if flags.contains(.option) { bits |= HotKeySpec.option }
        if flags.contains(.control) { bits |= HotKeySpec.control }
        return bits
    }
}
