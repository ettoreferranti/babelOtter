import AppKit
import BabelOtterKit
import SwiftUI

/// Opens the Settings window from the menu (#61): one window with toolbar
/// tabs, made once and kept, like History.
@MainActor
final class SettingsWindowController {

    private let model: SettingsModel
    /// Shared with the setup window, whose Model and Hotkeys steps are the
    /// same code as these tabs (#70).
    var settingsModel: SettingsModel { model }
    private var window: AppWindow?

    init(
        source: ConfigurationSource, layout: @escaping () -> KeyLayout,
        client: @escaping () -> OllamaClient, suspendHotKeys: @escaping () -> Void,
        resumeHotKeys: @escaping () -> Void, modelsChanged: @escaping () -> Void,
        reloadConfiguration: @escaping () -> Void, openSetupGuide: @escaping () -> Void
    ) {
        model = SettingsModel(
            source: source, layout: layout, client: client, suspendHotKeys: suspendHotKeys,
            resumeHotKeys: resumeHotKeys, modelsChanged: modelsChanged,
            reloadConfiguration: reloadConfiguration, openSetupGuide: openSetupGuide)
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.configurationChanged()
        model.windowShown()
        window.present()
    }

    /// config.json was reloaded.
    func configurationChanged() {
        model.configurationChanged()
    }

    private func makeWindow() -> AppWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab("General", "gearshape", 560, GeneralSettingsView(model: model)))
        tabs.addTabViewItem(tab("Models", "cpu", 400, ModelsSettingsView(model: model)))
        tabs.addTabViewItem(tab("Audiences", "person.2", 480, AudiencesSettingsView(model: model)))
        tabs.addTabViewItem(tab("Glossary", "character.book.closed", 540, GlossarySettingsView(model: model)))
        tabs.addTabViewItem(tab("Hotkeys", "keyboard", 360, HotKeysSettingsView(model: model)))
        let window = AppWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        return window
    }

    /// A minimum size per tab, growing with the window: a grouped Form has
    /// no natural height of its own. Only the minimum is passed on, so the
    /// window can be resized and keeps its size when the tab changes.
    private func tab<Content: View>(
        _ label: String, _ symbol: String, _ height: CGFloat, _ view: Content
    ) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view.frame(
            minWidth: 560, maxWidth: .infinity, minHeight: height, maxHeight: .infinity))
        controller.sizingOptions = [.minSize]
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

/// The file's problem at the top of every tab, while the window is
/// read-only.
struct FileProblemBanner: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        if model.isReadOnly {
            VStack(alignment: .leading, spacing: 4) {
                Text("config.json can't be read, so settings can't be changed until it is fixed:")
                    .font(.callout.weight(.semibold))
                ForEach(model.fileProblems, id: \.self) { problem in
                    Text(problem).font(.callout)
                }
                Button("Show config.json in Finder") { model.showFile() }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// A refusal under its control.
struct RefusalText: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text).font(.caption).foregroundStyle(.red)
        }
    }
}
