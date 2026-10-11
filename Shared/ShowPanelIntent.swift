import AppIntents
import AppKit
import os

/// Runs in the widget extension and hands off to the app through its URL scheme, which opens the floating panel.
/// Foreground-mode intents and OpenURLIntent chaining both failed from Control Center (LNActionExecutorErrorDomain 2018).
struct ShowBudsPanelIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Buds Panel"
    static var description = IntentDescription("Opens the OnePlus Buds panel with battery and noise control.")

    func perform() async throws -> some IntentResult {
        let opened = await MainActor.run {
            NSWorkspace.shared.open(URL(string: "budscontrol://panel")!)
        }
        Logger(subsystem: "com.ayushwalia.budscontrol", category: "intent").info("show panel, opened=\(opened)")
        return .result()
    }
}
