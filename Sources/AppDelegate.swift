import AppKit
import SwiftUI
import Carbon
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let appState = AppState()
    var folderWatcher: FolderWatcher?
    var hotkeyRef: EventHotKeyRef?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        registerHotkey()
        startFolderWatcher()
        requestNotificationPermission()

        appState.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMenuBarIcon()
            }
        }.store(in: &cancellables)
    }

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon()
        updateMenu()
    }

    func updateMenuBarIcon() {
        if let button = statusItem.button {
            let symbolName = appState.isArmed ? "arrow.down.circle.fill" : "arrow.down.circle"
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "SaveToShortcut")
            image?.isTemplate = true
            button.image = image
        }
        updateMenu()
    }

    private func updateMenu() {
        let menu = NSMenu()

        let statusText = appState.isArmed ? "Armed — next download will prompt" : "Disarmed"
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        let toggleTitle = appState.isArmed ? "Disarm" : "Arm (redirect next download)"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleArmed), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit SaveToShortcut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    @objc private func toggleArmed() {
        appState.toggleArmed()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        // Find existing settings window or let SwiftUI create it
        if let window = NSApp.windows.first(where: { $0.title.contains("Settings") }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Trigger the SwiftUI Window scene by sending the standard open action
            if #available(macOS 14.0, *) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)

            // Fallback: find and show any window that was just created
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.title.contains("Settings") }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    // MARK: - Global Hotkey

    func registerHotkey() {
        unregisterHotkey()

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x53545343) // "STSC"
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        let appDelegatePtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                appDelegate.appState.toggleArmed()
            }
            return noErr
        }, 1, &eventType, appDelegatePtr, nil)

        let status = RegisterEventHotKey(
            appState.hotkeyKeyCode,
            appState.hotkeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status != noErr {
            print("Failed to register hotkey: \(status)")
        }
    }

    func unregisterHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }

    // MARK: - Folder Watcher

    private func startFolderWatcher() {
        folderWatcher = FolderWatcher(appState: appState) { [weak self] fileURL in
            self?.handleNewFile(fileURL)
        }
    }

    private func handleNewFile(_ fileURL: URL) {
        guard appState.isArmed else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.appState.disarm()

            let panel = NSSavePanel()
            panel.nameFieldStringValue = fileURL.lastPathComponent
            panel.directoryURL = self.appState.recentDestinations.first ?? FileManager.default.homeDirectoryForCurrentUser
            panel.canCreateDirectories = true
            panel.title = "SaveToShortcut — Choose destination"

            NSApp.activate(ignoringOtherApps: true)

            let response = panel.runModal()
            if response == .OK, let destinationURL = panel.url {
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.moveItem(at: fileURL, to: destinationURL)
                    self.appState.addRecentDestination(destinationURL.deletingLastPathComponent())
                    self.sendNotification(fileName: fileURL.lastPathComponent, destination: destinationURL.deletingLastPathComponent().lastPathComponent)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Failed to move file"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    private func sendNotification(fileName: String, destination: String) {
        guard appState.notificationStyle != .silent else { return }
        guard Bundle.main.bundleIdentifier != nil else {
            print("✓ Moved: \(fileName) → \(destination)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "File Moved"
        content.body = "\(fileName) → \(destination)"
        if appState.notificationStyle == .sound {
            content.sound = .default
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

import Combine
