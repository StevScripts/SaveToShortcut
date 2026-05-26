import SwiftUI

@main
struct SaveToShortcutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("SaveToShortcut Settings", id: "settings") {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
