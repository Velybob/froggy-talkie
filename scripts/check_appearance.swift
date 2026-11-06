// Regression check for Light/Dark -> System transitions in real AppKit hosts.
// No visible windows, DictationModel, microphone, ASR or user preferences.
import AppKit
import SwiftUI
import DictationSystem

@MainActor private final class Observations {
    var schemes: [String: ColorScheme] = [:]
}

private struct SchemeProbe: View {
    let name: String
    let observations: Observations
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .onChange(of: scheme, initial: true) { _, value in
                observations.schemes[name] = value
            }
    }
}

@main struct CheckAppearance {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = nil
        let systemName = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])!
        let observations = Observations()
        let hosts = [
            host("main", view: DictationScreen(transcript: .constant("Проверка темы"), state: .init()), observations: observations),
            host("settings", view: DictationSettingsScreen(appearance: .constant(.system), modelsPath: "/Models",
                modelReady: true, isBusy: false, status: "Готово", hotKeyStatus: "⌃⌥Пробел", insertionAllowed: true), observations: observations),
            host("shortcut", view: ShortcutEditor(shortcut: .default, save: { _ in }, close: {}), observations: observations),
            host("panel", view: RecordingOverlayView(state: .init(recording: true, cancellable: true)), observations: observations, panel: true),
        ]
        for choice in [DictationAppearance.light, .system, .dark, .system, .light, .dark, .system] {
            choice.apply(to: app)
            // Pump AppKit layout/appearance delivery without showing or activating a window.
            RunLoop.main.run(until: Date().addingTimeInterval(0.12))
            let expectedName: NSAppearance.Name = choice == .system ? systemName : (choice == .dark ? .darkAqua : .aqua)
            let expected: ColorScheme = expectedName == .darkAqua ? .dark : .light
            for (name, window) in hosts {
                window.contentView?.layoutSubtreeIfNeeded()
                precondition(window.appearance == nil, "Unexpected window override: \(name)")
                precondition(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expectedName,
                    "Window appearance mismatch: \(name), \(choice.rawValue)")
                precondition(observations.schemes[name] == expected,
                    "SwiftUI content mismatch: \(name), \(choice.rawValue), observed \(String(describing: observations.schemes[name]))")
            }
            if choice == .system { precondition(app.appearance == nil, "System must clear the app override") }
            print("PASS \(choice.rawValue) -> \(expected): main, settings, shortcut, panel")
        }
        print("Passed 28 host transitions; system appearance: \(systemName.rawValue). No preferences or audio changed.")
    }

    @MainActor private static func host<V: View>(_ name: String, view: V,
        observations: Observations, panel: Bool = false) -> (String, NSWindow) {
        let rect = NSRect(x: 0, y: 0, width: 500, height: 600)
        let window: NSWindow = panel
            ? NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            : NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view.background(SchemeProbe(name: name, observations: observations)))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return (name, window)
    }
}
